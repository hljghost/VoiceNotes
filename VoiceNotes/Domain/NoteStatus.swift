import Foundation

/// Pipeline status for a voice note. Failures never discard prior artifacts.
enum NoteStatus: String, Codable, CaseIterable, Sendable {
    case draftAudio
    case transcribing
    case transcribed
    case enriching
    case ready
    case failedASR
    case failedEnrich

    var displayName: String {
        switch self {
        case .draftAudio: return "待转写"
        case .transcribing: return "转写中"
        case .transcribed: return "已转写"
        case .enriching: return "整理中"
        case .ready: return "已完成"
        case .failedASR: return "转写失败"
        case .failedEnrich: return "整理失败"
        }
    }

    var isProcessing: Bool {
        self == .transcribing || self == .enriching
    }

    var canRetryASR: Bool {
        self == .failedASR || self == .draftAudio
    }

    var canRetryEnrich: Bool {
        self == .failedEnrich || self == .transcribed
    }
}
