import SwiftData
import SwiftUI

struct NoteDetailView: View {
    let noteID: UUID

    @Environment(NotePipeline.self) private var pipeline
    @Environment(AudioPlayer.self) private var player
    @Query private var notes: [Note]

    @State private var editedTitle: String = ""
    @State private var didLoadTitle = false

    init(noteID: UUID) {
        self.noteID = noteID
        _notes = Query(
            filter: #Predicate<Note> { $0.id == noteID },
            sort: \Note.createdAt
        )
    }

    private var note: Note? { notes.first }
    private var isBusy: Bool { pipeline.activeNoteID == noteID }

    var body: some View {
        Group {
            if let note {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(note)
                        if note.status.isProcessing || isBusy {
                            processingBanner(note)
                        }
                        if note.status == .failedASR || note.status == .failedEnrich {
                            failureBanner(note)
                        }
                        summaryBlock(note)
                        bulletsBlock(note)
                        transcriptBlock(note)
                        audioBlock(note)
                        metaBlock(note)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(.systemBackground))
            } else {
                ContentUnavailableView("笔记不存在", systemImage: "trash")
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let note, note.status.canRetryASR || note.status.canRetryEnrich {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if note.status.canRetryASR {
                            Button("重试转写") {
                                Task { await pipeline.retryASR(noteID: note.id) }
                            }
                        }
                        if note.status.canRetryEnrich {
                            Button("重试整理") {
                                Task { await pipeline.retryEnrich(noteID: note.id) }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isBusy)
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(status: note.status)
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(VNTheme.hush)
            }

            TextField("标题", text: $editedTitle, axis: .vertical)
                .font(.title2.weight(.bold))
                .textFieldStyle(.plain)
                .onAppear {
                    guard !didLoadTitle else { return }
                    editedTitle = note.title ?? note.displayTitle
                    didLoadTitle = true
                }
                .onChange(of: editedTitle) { _, newValue in
                    note.title = newValue
                    note.updatedAt = Date()
                }

            if note.durationMs > 0 {
                Text(durationString(note.durationMs))
                    .font(.subheadline)
                    .foregroundStyle(VNTheme.mist)
            }
        }
    }

    private func processingBanner(_ note: Note) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(note.status == .enriching ? "正在离线整理…" : "正在离线转写…")
                .font(.subheadline)
                .foregroundStyle(VNTheme.mist)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(VNTheme.working.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func failureBanner(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VNInlineBanner(
                kind: .error,
                text: note.status == .failedASR
                    ? "转写失败。音频仍在，可重试；不会丢失录音。"
                    : "整理失败。原文转写已保留，可单独重试整理。"
            )
            HStack(spacing: 10) {
                if note.status.canRetryASR {
                    Button("重试转写") {
                        Task { await pipeline.retryASR(noteID: note.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VNTheme.pine)
                }
                if note.status.canRetryEnrich {
                    Button("重试整理") {
                        Task { await pipeline.retryEnrich(noteID: note.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VNTheme.pine)
                }
            }
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private func summaryBlock(_ note: Note) -> some View {
        if let summary = note.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                VNSectionLabel(title: "摘要")
                Text(summary)
                    .font(.body)
                    .foregroundStyle(VNTheme.ink)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func bulletsBlock(_ note: Note) -> some View {
        if !note.bullets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VNSectionLabel(title: "要点")
                ForEach(Array(note.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(VNTheme.pine)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(bullet)
                            .font(.body)
                            .foregroundStyle(VNTheme.ink)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptBlock(_ note: Note) -> some View {
        if let raw = note.transcriptRaw, !raw.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                VNSectionLabel(title: "原文转写")
                Text(raw)
                    .font(.body)
                    .foregroundStyle(VNTheme.mist)
                    .textSelection(.enabled)
            }
        } else if !note.status.isProcessing && note.status != .failedASR {
            VStack(alignment: .leading, spacing: 8) {
                VNSectionLabel(title: "原文转写")
                Text("暂无转写文本")
                    .font(.body)
                    .foregroundStyle(VNTheme.hush)
            }
        }
    }

    private func audioBlock(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VNSectionLabel(title: "音频")
            if let relative = note.audioRelativePath {
                Button {
                    try? player.toggle(url: AppPaths.audioURL(relativePath: relative))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                            .frame(width: 18)
                        Text(player.isPlaying ? "停止回放" : "回放录音")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(durationString(note.durationMs))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(VNTheme.hush)
                    }
                    .foregroundStyle(VNTheme.pine)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(VNTheme.pine.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("无音频文件")
                    .font(.subheadline)
                    .foregroundStyle(VNTheme.hush)
            }
        }
    }

    private func metaBlock(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VNSectionLabel(title: "模型")
            metaRow("转写", note.asrModelID ?? "—")
            metaRow("整理", note.llmModelID ?? "—")
        }
        .padding(.bottom, 24)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(VNTheme.mist)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(VNTheme.hush)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func durationString(_ ms: Int) -> String {
        let seconds = max(ms / 1000, 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
