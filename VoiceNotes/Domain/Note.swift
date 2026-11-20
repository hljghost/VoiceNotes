import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    /// Path relative to Application Support / Audio
    var audioRelativePath: String?
    var durationMs: Int
    var transcriptRaw: String?
    var transcriptClean: String?
    var title: String?
    var summary: String?
    /// JSON-encoded `[String]`
    var bulletsJSON: String?
    /// JSON-encoded `[String]`
    var tagsJSON: String?
    var asrModelID: String?
    var llmModelID: String?
    var statusRaw: String

    var status: NoteStatus {
        get { NoteStatus(rawValue: statusRaw) ?? .draftAudio }
        set {
            statusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var bullets: [String] {
        get { Self.decodeStringArray(bulletsJSON) }
        set { bulletsJSON = Self.encodeStringArray(newValue) }
    }

    var tags: [String] {
        get { Self.decodeStringArray(tagsJSON) }
        set { tagsJSON = Self.encodeStringArray(newValue) }
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let transcriptRaw, !transcriptRaw.isEmpty {
            return String(transcriptRaw.prefix(40))
        }
        return "未命名速记"
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        audioRelativePath: String? = nil,
        durationMs: Int = 0,
        transcriptRaw: String? = nil,
        transcriptClean: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        bullets: [String] = [],
        tags: [String] = [],
        asrModelID: String? = nil,
        llmModelID: String? = nil,
        status: NoteStatus = .draftAudio
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.audioRelativePath = audioRelativePath
        self.durationMs = durationMs
        self.transcriptRaw = transcriptRaw
        self.transcriptClean = transcriptClean
        self.title = title
        self.summary = summary
        self.bulletsJSON = Self.encodeStringArray(bullets)
        self.tagsJSON = Self.encodeStringArray(tags)
        self.asrModelID = asrModelID
        self.llmModelID = llmModelID
        self.statusRaw = status.rawValue
    }

    private static func encodeStringArray(_ value: [String]) -> String? {
        guard !value.isEmpty,
              let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return value
    }
}
