import Foundation
import SwiftUI
import UIKit

/// Formats a note for Apple Notes / system share sheet.
/// iOS has no public API to silently create a Notes entry without user confirmation.
enum NoteExporter {
    static func plainText(for note: Note) -> String {
        var lines: [String] = []
        lines.append(note.displayTitle)
        lines.append("")
        lines.append("创建于 \(note.createdAt.formatted(date: .long, time: .shortened))")
        if note.durationMs > 0 {
            let seconds = max(note.durationMs / 1000, 0)
            lines.append("时长 \(String(format: "%d:%02d", seconds / 60, seconds % 60))")
        }
        lines.append("")

        if let summary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            lines.append("摘要")
            lines.append(summary)
            lines.append("")
        }

        if !note.bullets.isEmpty {
            lines.append("要点")
            for bullet in note.bullets {
                lines.append("• \(bullet)")
            }
            lines.append("")
        }

        if let raw = note.transcriptRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            lines.append("原文转写")
            lines.append(raw)
            lines.append("")
        }

        lines.append("—")
        lines.append("由「语音速记」导出 · 内容仅来自本机离线整理")
        return lines.joined(separator: "\n")
    }

    /// Writes a temporary UTF-8 `.txt` so Share Sheet / Notes get a document title.
    static func temporaryTextFile(for note: Note) throws -> URL {
        let text = plainText(for: note)
        let safe = sanitizeFilename(note.displayTitle)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("语音速记-\(safe)-\(note.id.uuidString.prefix(8)).txt")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(trimmed.prefix(24))
        let cleaned = clipped
            .replacingOccurrences(of: "/", with: "、")
            .replacingOccurrences(of: ":", with: "：")
        return cleaned.isEmpty ? "未命名速记" : cleaned
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct NoteExportPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
