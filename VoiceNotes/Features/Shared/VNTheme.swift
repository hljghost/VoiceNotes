import SwiftUI

/// Quiet ink / pine — offline privacy tone. No purple, no cream-terracotta.
enum VNTheme {
    static let pine = Color("AccentColor")
    static let ink = Color.primary
    static let mist = Color.secondary
    static let hush = Color.secondary.opacity(0.55)

    static let ready = Color(red: 0.18, green: 0.55, blue: 0.38)
    static let working = Color(red: 0.78, green: 0.48, blue: 0.12)
    static let danger = Color(red: 0.72, green: 0.22, blue: 0.20)
    static let draft = Color.secondary

    static func statusColor(_ status: NoteStatus) -> Color {
        switch status {
        case .ready: return ready
        case .failedASR, .failedEnrich: return danger
        case .transcribing, .enriching: return working
        case .draftAudio, .transcribed: return draft
        }
    }
}

struct StatusBadge: View {
    let status: NoteStatus

    var body: some View {
        HStack(spacing: 5) {
            if status.isProcessing {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(VNTheme.statusColor(status))
        .background(VNTheme.statusColor(status).opacity(0.14), in: Capsule())
        .accessibilityLabel("状态：\(status.displayName)")
    }
}

struct VNSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(VNTheme.hush)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

struct VNInlineBanner: View {
    enum Kind { case info, warn, error }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tint: Color {
        switch kind {
        case .info: return VNTheme.pine
        case .warn: return VNTheme.working
        case .error: return VNTheme.danger
        }
    }

    private var icon: String {
        switch kind {
        case .info: return "lock.shield"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
