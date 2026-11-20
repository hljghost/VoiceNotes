import Foundation

/// sherpa-onnx SenseVoice adapter (MVP ASR).
///
/// **Status**: stub — compiles without linking sherpa-onnx.
/// Next step: enable SPM package `sherpa-onnx` in `project.yml`, then replace
/// `transcribe` body with `OfflineRecognizer` + SenseVoice model config.
///
/// Reference: https://github.com/k2-fsa/sherpa-onnx (SenseVoice Small, offline)
actor SenseVoiceRecognizer: SpeechRecognizer {
    static let defaultModelID = "sensevoice-small"

    let modelID: String
    private let modelDirectory: URL
    private var loaded = false

    init(modelDirectory: URL, modelID: String = SenseVoiceRecognizer.defaultModelID) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
    }

    var isModelReady: Bool {
        get async {
            let modelPath = modelDirectory.appendingPathComponent(modelID)
            return FileManager.default.fileExists(atPath: modelPath.path)
        }
    }

    func transcribe(url: URL) async throws -> String {
        guard await isModelReady else {
            // Stub path: allow UI pipeline to run in Simulator without weights.
            #if targetEnvironment(simulator)
            return stubTranscript(for: url)
            #else
            throw SpeechRecognizerError.modelNotReady
            #endif
        }

        // TODO(sherpa-onnx):
        // 1. Load OfflineModelConfig for SenseVoice from `modelDirectory`
        // 2. Create OfflineRecognizer
        // 3. Read WAV / decode M4A → samples @ 16 kHz
        // 4. Return recognizer.decode result text
        // 5. Prefer Chinese (`language: "zh"`) for short notes
        loaded = true
        throw SpeechRecognizerError.engineFailure(
            "SenseVoice 适配层已就位，请接入 sherpa-onnx Offline API（见 README）"
        )
    }

    func unload() async {
        // TODO: release OfflineRecognizer / OrtEnv when real engine is wired
        loaded = false
        _ = loaded
    }

    private func stubTranscript(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return "【模拟转写】\(name)。请在真机下载 SenseVoice 模型后替换为真实 ASR。"
    }
}
