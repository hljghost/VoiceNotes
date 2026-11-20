import Foundation

/// Structured enrichment produced from a transcript.
struct Enrichment: Sendable, Equatable, Codable {
    var title: String
    var summary: String
    var bullets: [String]
    var tags: [String]
    var transcriptClean: String?
    var modelID: String

    static let empty = Enrichment(
        title: "",
        summary: "",
        bullets: [],
        tags: [],
        transcriptClean: nil,
        modelID: ""
    )
}

/// Post-ASR enrichment. MVP: `OnDeviceEnricher` (MLX Qwen).
/// Later (non-MVP): a cloud implementation may share this protocol — do not wire in MVP.
protocol Enricher: Sendable {
    var modelID: String { get }
    var isModelReady: Bool { get async }

    func enrich(transcript: String) async throws -> Enrichment

    /// Unload weights after use (serial pipeline with ASR).
    func unload() async
}

enum EnricherError: Error, LocalizedError, Sendable {
    case modelNotReady
    case emptyTranscript
    case generationFailed(String)
    case invalidJSON
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "整理模型尚未下载或不可用"
        case .emptyTranscript:
            return "没有可整理的转写文本"
        case .generationFailed(let message):
            return "整理失败：\(message)"
        case .invalidJSON:
            return "模型输出无法解析为结构化结果"
        case .cancelled:
            return "整理已取消"
        }
    }
}
