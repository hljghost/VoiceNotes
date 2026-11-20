import Foundation
import SwiftData

/// DEBUG-only: run offline ASR on a fixture wav dropped into Application Support.
/// Trigger: launch argument `-AutoASRFixture`
@MainActor
enum ASRFixtureRunner {
    static let resultFileName = "asr-fixture-result.json"

    static func runIfRequested(dependencies: AppDependencies) async {
        guard ProcessInfo.processInfo.arguments.contains("-AutoASRFixture") else { return }

        let support = AppPaths.applicationSupport
        let fixtureCandidates = [
            support.appendingPathComponent("Fixtures/zh-16k.wav"),
            AppPaths.audioDirectory.appendingPathComponent("fixture-zh-16k.wav"),
        ]
        let resultURL = support.appendingPathComponent(resultFileName)

        struct Payload: Codable {
            var ok: Bool
            var transcript: String?
            var title: String?
            var summary: String?
            var bullets: [String]?
            var llmModelID: String?
            var noteID: String?
            var status: String?
            var asrReady: Bool
            var qwenReady: Bool
            var error: String?
            var asrModelPath: String
            var llmModelPath: String
            var fixturePath: String?
        }

        let asrModelPath = AppPaths.asrModelsDirectory
            .appendingPathComponent(SenseVoiceRecognizer.defaultModelID)
            .path
        let llmModelPath = AppPaths.llmModelsDirectory
            .appendingPathComponent(OnDeviceEnricher.defaultModelID)
            .path
        let asrReady = SenseVoiceModelLayout.isReady(
            at: AppPaths.asrModelsDirectory.appendingPathComponent(SenseVoiceRecognizer.defaultModelID)
        )
        let qwenReady = QwenModelCatalog.isReady(
            at: AppPaths.llmModelsDirectory.appendingPathComponent(OnDeviceEnricher.defaultModelID)
        )

        guard let fixture = fixtureCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            write(
                Payload(
                    ok: false,
                    transcript: nil,
                    title: nil,
                    summary: nil,
                    bullets: nil,
                    llmModelID: nil,
                    noteID: nil,
                    status: nil,
                    asrReady: asrReady,
                    qwenReady: qwenReady,
                    error: "fixture wav not found under Application Support/Fixtures or Audio",
                    asrModelPath: asrModelPath,
                    llmModelPath: llmModelPath,
                    fixturePath: nil
                ),
                to: resultURL
            )
            return
        }

        do {
            // Place a copy under Audio/ so NotePipeline relative paths work.
            try FileManager.default.createDirectory(
                at: AppPaths.audioDirectory,
                withIntermediateDirectories: true
            )
            let audioName = "fixture-zh-16k.wav"
            let audioURL = AppPaths.audioDirectory.appendingPathComponent(audioName)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.removeItem(at: audioURL)
            }
            try FileManager.default.copyItem(at: fixture, to: audioURL)

            let durationMs = try approximateDurationMs(url: audioURL)
            let note = try dependencies.notePipeline.createNote(
                audioURL: audioURL,
                durationMs: durationMs
            )
            await dependencies.notePipeline.process(noteID: note.id)

            // Re-fetch status/transcript after pipeline
            let noteID = note.id
            let descriptor = FetchDescriptor<Note>(
                predicate: #Predicate { $0.id == noteID }
            )
            let refreshed = try dependencies.modelContainer.mainContext.fetch(descriptor).first
            let transcript = refreshed?.transcriptRaw
            let status = refreshed?.status.rawValue
            let pipelineError = dependencies.notePipeline.lastError

            let hasText = !(transcript ?? "").isEmpty
            let pipelineOK = hasText && status == NoteStatus.ready.rawValue
            write(
                Payload(
                    ok: pipelineOK,
                    transcript: transcript,
                    title: refreshed?.title,
                    summary: refreshed?.summary,
                    bullets: refreshed?.bullets,
                    llmModelID: refreshed?.llmModelID,
                    noteID: note.id.uuidString,
                    status: status,
                    asrReady: asrReady,
                    qwenReady: qwenReady,
                    error: pipelineOK ? nil : pipelineError,
                    asrModelPath: asrModelPath,
                    llmModelPath: llmModelPath,
                    fixturePath: fixture.path
                ),
                to: resultURL
            )
            dependencies.modelStore.refresh()
        } catch {
            write(
                Payload(
                    ok: false,
                    transcript: nil,
                    title: nil,
                    summary: nil,
                    bullets: nil,
                    llmModelID: nil,
                    noteID: nil,
                    status: nil,
                    asrReady: asrReady,
                    qwenReady: qwenReady,
                    error: error.localizedDescription,
                    asrModelPath: asrModelPath,
                    llmModelPath: llmModelPath,
                    fixturePath: fixture.path
                ),
                to: resultURL
            )
        }
    }

    private static func approximateDurationMs(url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? NSNumber ?? 0
        // 16-bit mono 16 kHz ≈ 32000 bytes/sec
        let seconds = size.doubleValue / 32_000.0
        return max(Int(seconds * 1000), 1)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            print("[ASRFixtureRunner] wrote \(url.path)")
            if let text = String(data: data, encoding: .utf8) {
                print("[ASRFixtureRunner] \(text)")
            }
        } catch {
            print("[ASRFixtureRunner] failed to write result: \(error)")
        }
    }
}
