import Foundation
import SwiftData

/// Composition root. UI / pipeline depend on protocols, not concrete engines.
@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let speechRecognizer: any SpeechRecognizer
    let enricher: any Enricher
    let modelStore: ModelStore
    let modelPreferences: ModelPreferences
    let audioRecorder: AudioRecorder
    let audioPlayer: AudioPlayer
    let notePipeline: NotePipeline

    init() {
        let schema = Schema([Note.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }

        let context = modelContainer.mainContext
        let prefs = ModelPreferences()
        let recognizer = SenseVoiceRecognizer(modelDirectory: AppPaths.asrModelsDirectory)
        let onDevice = OnDeviceEnricher(
            modelDirectory: AppPaths.llmModelsDirectory,
            modelPreferences: prefs
        )

        speechRecognizer = recognizer
        enricher = onDevice
        modelStore = ModelStore()
        modelPreferences = prefs
        audioRecorder = AudioRecorder(audioDirectory: AppPaths.audioDirectory)
        audioPlayer = AudioPlayer()
        notePipeline = NotePipeline(
            speechRecognizer: recognizer,
            enricher: onDevice,
            modelContext: context,
            audioDirectory: AppPaths.audioDirectory
        )

        let asrReady = SenseVoiceModelLayout.isReady(
            at: AppPaths.asrModelsDirectory.appendingPathComponent(SenseVoiceModelCatalog.modelID)
        )
        let llmReady = QwenModelCatalog.isReady(
            at: AppPaths.llmModelsDirectory.appendingPathComponent(QwenModelCatalog.modelID)
        )
        prefs.healIfNeeded(asrReady: asrReady, llmReady: llmReady)
    }
}
