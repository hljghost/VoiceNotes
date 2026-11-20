import SwiftData
import SwiftUI

struct NotesListView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var searchText = ""

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
                ContentUnavailableView(
                    searchText.isEmpty ? "还没有速记" : "无匹配结果",
                    systemImage: searchText.isEmpty ? "mic" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "在「录音」页说一句开始" : "换个关键词试试")
                )
            } else {
                List(filtered) { note in
                    NavigationLink {
                        NoteDetailView(noteID: note.id)
                    } label: {
                        NoteRowView(note: note)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("笔记")
        .searchable(text: $searchText, prompt: "搜索标题 / 摘要 / 原文")
    }
}

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(note.status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            if let summary = note.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let raw = note.transcriptRaw, !raw.isEmpty {
                Text(raw)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch note.status {
        case .ready: return .green
        case .failedASR, .failedEnrich: return .red
        case .transcribing, .enriching: return .orange
        default: return .secondary
        }
    }
}

extension Note: Identifiable {}
