import Foundation

/// Offline ASR contract. MVP implementation: sherpa-onnx SenseVoice.
protocol SpeechRecognizer: Sendable {
    /// Stable model identifier written to `Note.asrModelID`.
    var modelID: String { get }

    /// Whether weights are present on disk and ready to load.
    var isModelReady: Bool { get async }

    /// Transcribe a local audio file (prefer 16 kHz mono WAV/M4A).
    func transcribe(url: URL) async throws -> String

    /// Unload weights so LLM can load without OOM. Safe if already unloaded.
    func unload() async
}

enum SpeechRecognizerError: Error, LocalizedError, Sendable {
    case modelNotReady
    case unsupportedAudio
    case engineFailure(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "ASR 模型尚未下载或不可用"
        case .unsupportedAudio:
            return "不支持的音频格式"
        case .engineFailure(let message):
            return "ASR 失败：\(message)"
        case .cancelled:
            return "转写已取消"
        }
    }
}
