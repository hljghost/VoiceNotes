import Foundation
import SwiftData

/// Owns the recording → ASR → enrich state machine.
/// Only one of ASR / LLM should be resident at a time.
@MainActor
@Observable
final class NotePipeline {
    private let speechRecognizer: any SpeechRecognizer
    private let enricher: any Enricher
    private let modelContext: ModelContext
    private let audioDirectory: URL

    private(set) var activeNoteID: UUID?
    private(set) var lastError: String?

    init(
        speechRecognizer: any SpeechRecognizer,
        enricher: any Enricher,
        modelContext: ModelContext,
        audioDirectory: URL
    ) {
        self.speechRecognizer = speechRecognizer
        self.enricher = enricher
        self.modelContext = modelContext
        self.audioDirectory = audioDirectory
    }

    // MARK: - Create from recording

    @discardableResult
    func createNote(audioURL: URL, durationMs: Int) throws -> Note {
        let relative = audioURL.lastPathComponent
        let note = Note(
            audioRelativePath: relative,
            durationMs: durationMs,
            status: .draftAudio
        )
        modelContext.insert(note)
        try modelContext.save()
        return note
    }

    // MARK: - Full pipeline

    func process(noteID: UUID) async {
        activeNoteID = noteID
        lastError = nil
        defer { activeNoteID = nil }

        do {
            try await transcribe(noteID: noteID)
            try await enrich(noteID: noteID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func retryASR(noteID: UUID) async {
        activeNoteID = noteID
        lastError = nil
        defer { activeNoteID = nil }
        do {
            try await transcribe(noteID: noteID)
            try await enrich(noteID: noteID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func retryEnrich(noteID: UUID) async {
        activeNoteID = noteID
        lastError = nil
        defer { activeNoteID = nil }
        do {
            try await enrich(noteID: noteID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Delete

    /// Removes the SwiftData row and its local audio file (if any).
    func deleteNote(noteID: UUID) throws {
        guard let note = fetch(noteID) else { return }
        if activeNoteID == noteID {
            activeNoteID = nil
        }
        if let relative = note.audioRelativePath {
            let url = audioDirectory.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        modelContext.delete(note)
        try modelContext.save()
    }

    // MARK: - Steps

    private func transcribe(noteID: UUID) async throws {
        guard let note = fetch(noteID) else { return }
        guard let relative = note.audioRelativePath else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        let url = audioDirectory.appendingPathComponent(relative)
        note.status = .transcribing
        try modelContext.save()

        do {
            await enricher.unload()
            let text = try await speechRecognizer.transcribe(url: url)
            note.transcriptRaw = text
            note.asrModelID = speechRecognizer.modelID
            note.status = .transcribed
            try modelContext.save()
            await speechRecognizer.unload()
        } catch {
            note.status = .failedASR
            try? modelContext.save()
            throw error
        }
    }

    private func enrich(noteID: UUID) async throws {
        guard let note = fetch(noteID) else { return }
        guard let transcript = note.transcriptRaw, !transcript.isEmpty else {
            throw EnricherError.emptyTranscript
        }

        note.status = .enriching
        try modelContext.save()

        do {
            await speechRecognizer.unload()
            let result = try await enricher.enrich(transcript: transcript)
            note.title = result.title
            note.summary = result.summary
            note.bullets = result.bullets
            note.tags = result.tags
            if let clean = result.transcriptClean {
                note.transcriptClean = clean
            }
            note.llmModelID = result.modelID
            note.status = .ready
            try modelContext.save()
            await enricher.unload()
        } catch {
            // Keep transcript; mark enrich failure for retry.
            note.status = .failedEnrich
            try? modelContext.save()
            throw error
        }
    }

    private func fetch(_ id: UUID) -> Note? {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
