import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(NotePipeline.self) private var pipeline
    @Environment(AudioPlayer.self) private var player
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var searchText = ""
    @State private var pendingDelete: Note?
    @State private var deleteError: String?

    private var filtered: [Note] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter { note in
            [note.title, note.summary, note.transcriptRaw, note.transcriptClean]
                .compactMap { $0 }
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { note in
                        NavigationLink {
                            NoteDetailView(noteID: note.id)
                        } label: {
                            NoteRowView(note: note)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparatorTint(Color.primary.opacity(0.08))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = note
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("笔记")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜索标题、摘要或原文")
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ConfirmDeleteFirstNote"),
               pendingDelete == nil,
               let first = filtered.first {
                pendingDelete = first
            }
            if let id = NoteDeleteDebugHook.pendingDeleteID {
                player.stop()
                try? pipeline.deleteNote(noteID: id)
            }
            #endif
        }
        .confirmationDialog(
            "删除这条速记？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除笔记与音频", role: .destructive) {
                confirmDelete()
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("将同时删除本机录音文件，此操作不可撤销。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "还没有速记" : "没有匹配结果",
                systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass"
            )
        } description: {
            Text(searchText.isEmpty ? "到「录音」说一句，转写与整理会自动完成。" : "换个关键词，或清空搜索看看全部笔记。")
        }
        .foregroundStyle(VNTheme.mist)
    }

    private func confirmDelete() {
        guard let note = pendingDelete else { return }
        pendingDelete = nil
        player.stop()
        do {
            try pipeline.deleteNote(noteID: note.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(note.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VNTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(status: note.status)
            }

            if let preview = previewText {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(VNTheme.mist)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                if note.durationMs > 0 {
                    Text("·")
                    Text(durationLabel)
                }
            }
            .font(.caption)
            .foregroundStyle(VNTheme.hush)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var previewText: String? {
        if let summary = note.summary, !summary.isEmpty, summary != note.displayTitle {
            return summary
        }
        if let raw = note.transcriptRaw, !raw.isEmpty {
            return raw
        }
        if note.status.isProcessing {
            return "正在处理这段录音…"
        }
        if note.status == .failedASR {
            return "转写失败，可打开详情重试"
        }
        if note.status == .failedEnrich {
            return "整理失败，原文仍保留"
        }
        return nil
    }

    private var durationLabel: String {
        let seconds = max(note.durationMs / 1000, 1)
        if seconds < 60 { return "\(seconds) 秒" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension Note: Identifiable {}
