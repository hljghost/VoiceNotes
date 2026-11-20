import SwiftUI

struct RecordView: View {
    @Environment(AudioRecorder.self) private var recorder
    @Environment(NotePipeline.self) private var pipeline
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.modelContext) private var modelContext

    @State private var permissionDenied = false
    @State private var errorMessage: String?
    @State private var lastCreatedNoteID: UUID?

    private var asrReady: Bool {
        modelStore.models.first(where: { $0.id == SenseVoiceModelCatalog.modelID })?.isDownloaded == true
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("语音速记")
                .font(.largeTitle.bold())

            Text(recorder.isRecording ? formatDuration(recorder.durationSeconds) : "点按开始，再说一句")
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !asrReady {
                Text("请先到「设置」下载 SenseVoice 模型，再录中文短句。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
                        .frame(width: 160, height: 160)
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: recorder.isRecording ? 72 : 96, height: recorder.isRecording ? 72 : 96)
                        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "停止录音" : "开始录音")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let id = lastCreatedNoteID {
                NavigationLink("查看刚录的笔记") {
                    NoteDetailView(noteID: id)
                }
                .font(.subheadline)
            }

            Spacer()
            Text("全程离线 · 音频仅存本机")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .padding()
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .alert("需要麦克风权限", isPresented: $permissionDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许「语音速记」使用麦克风。")
        }
    }

    private func toggleRecording() async {
        errorMessage = nil
        if recorder.isRecording {
            guard let result = recorder.stop() else { return }
            do {
                let note = try pipeline.createNote(audioURL: result.url, durationMs: result.durationMs)
                lastCreatedNoteID = note.id
                await pipeline.process(noteID: note.id)
                if let err = pipeline.lastError {
                    errorMessage = err
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            let ok = await recorder.requestPermission()
            guard ok else {
                permissionDenied = true
                return
            }
            do {
                try recorder.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
