import SwiftData
import SwiftUI

struct NoteDetailView: View {
    let noteID: UUID

    @Environment(NotePipeline.self) private var pipeline
    @Environment(AudioPlayer.self) private var player
    @Query private var notes: [Note]

    @State private var editedTitle: String = ""

    init(noteID: UUID) {
        self.noteID = noteID
        _notes = Query(
            filter: #Predicate<Note> { $0.id == noteID },
            sort: \Note.createdAt
        )
    }

    private var note: Note? { notes.first }

    var body: some View {
        Group {
            if let note {
                Form {
                    Section("标题") {
                        TextField("标题", text: $editedTitle)
                            .onAppear { editedTitle = note.title ?? note.displayTitle }
                            .onChange(of: editedTitle) { _, newValue in
                                note.title = newValue
                                note.updatedAt = Date()
                            }
                    }

                    Section("状态") {
                        LabeledContent("当前", value: note.status.displayName)
                        if note.status.isProcessing {
                            ProgressView("处理中…")
                        }
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
                    }

                    if let summary = note.summary, !summary.isEmpty {
                        Section("摘要") {
                            Text(summary)
                        }
                    }

                    if !note.bullets.isEmpty {
                        Section("要点") {
                            ForEach(note.bullets, id: \.self) { bullet in
                                Text("• \(bullet)")
                            }
                        }
                    }

                    if let raw = note.transcriptRaw, !raw.isEmpty {
                        Section("原文转写") {
                            Text(raw)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    Section("音频") {
                        if let relative = note.audioRelativePath {
                            Button {
                                try? player.toggle(url: AppPaths.audioURL(relativePath: relative))
                            } label: {
                                Label(
                                    player.isPlaying ? "停止回放" : "回放",
                                    systemImage: player.isPlaying ? "stop.fill" : "play.fill"
                                )
                            }
                            LabeledContent("时长", value: "\(note.durationMs) ms")
                        } else {
                            Text("无音频文件")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("模型") {
                        LabeledContent("ASR", value: note.asrModelID ?? "—")
                        LabeledContent("LLM", value: note.llmModelID ?? "—")
                    }
                }
            } else {
                ContentUnavailableView("笔记不存在", systemImage: "trash")
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
