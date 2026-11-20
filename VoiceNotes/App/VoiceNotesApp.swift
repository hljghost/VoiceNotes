import SwiftData
import SwiftUI

@main
struct VoiceNotesApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies.notePipeline)
                .environment(dependencies.audioRecorder)
                .environment(dependencies.audioPlayer)
                .environment(dependencies.modelStore)
                .environment(\.appDependencies, dependencies)
                .task {
                    await ASRFixtureRunner.runIfRequested(dependencies: dependencies)
                    await ModelDownloadRunner.runIfRequested(dependencies: dependencies)
                }
        }
        .modelContainer(dependencies.modelContainer)
    }
}

// MARK: - Environment key

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies? = nil
}

extension EnvironmentValues {
    var appDependencies: AppDependencies? {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
