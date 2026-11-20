import SwiftUI

struct RecordView: View {
    @Environment(AudioRecorder.self) private var recorder
    @Environment(NotePipeline.self) private var pipeline
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.modelContext) private var modelContext

    @State private var permissionDenied = false
    @State private var errorMessage: String?
    @State private var lastCreatedNoteID: UUID?
    @State private var pulse = false

    private var asrReady: Bool {
        modelStore.models.first(where: { $0.id == SenseVoiceModelCatalog.modelID })?.isDownloaded == true
    }

    private var isProcessingLast: Bool {
        guard let id = lastCreatedNoteID else { return false }
        return pipeline.activeNoteID == id
    }

    var body: some View {
        ZStack {
            atmosphere
            VStack(spacing: 0) {
                header
                    .padding(.top, 12)

                Spacer(minLength: 24)

                durationBlock

                recordButton
                    .padding(.vertical, 28)

                statusBlock

                Spacer(minLength: 16)

                footer
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert("需要麦克风权限", isPresented: $permissionDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许「语音速记」使用麦克风。")
        }
        .onChange(of: recorder.isRecording) { _, recording in
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = recording
            }
            if !recording { pulse = false }
        }
    }

    // MARK: - Pieces

    private var atmosphere: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [
                    VNTheme.pine.opacity(recorder.isRecording ? 0.18 : 0.08),
                    Color.clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 320
            )
            .animation(.easeInOut(duration: 0.35), value: recorder.isRecording)
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("语音速记")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(VNTheme.ink)
            Text("说完即记 · 本机离线整理")
                .font(.subheadline)
                .foregroundStyle(VNTheme.mist)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var durationBlock: some View {
        VStack(spacing: 6) {
            Text(recorder.isRecording ? formatDuration(recorder.durationSeconds) : "00:00")
                .font(.system(size: 48, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(recorder.isRecording ? VNTheme.danger : VNTheme.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: recorder.durationSeconds)

            Text(hintText)
                .font(.subheadline)
                .foregroundStyle(VNTheme.mist)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        }
    }

    private var hintText: String {
        if recorder.isRecording { return "录音中，点下方结束" }
        if isProcessingLast { return "正在转写并整理…" }
        if !asrReady { return "先到「设置」下载转写模型" }
        return "点按开始，说一句短记"
    }

    private var recordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            ZStack {
                Circle()
                    .stroke(VNTheme.pine.opacity(0.25), lineWidth: 2)
                    .frame(width: 168, height: 168)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .opacity(recorder.isRecording ? 1 : 0.55)

                Circle()
                    .fill(recorder.isRecording ? VNTheme.danger.opacity(0.14) : VNTheme.pine.opacity(0.12))
                    .frame(width: 148, height: 148)

                Group {
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(VNTheme.danger)
                            .frame(width: 44, height: 44)
                    } else {
                        Circle()
                            .fill(asrReady ? VNTheme.pine : Color.secondary.opacity(0.45))
                            .frame(width: 88, height: 88)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: recorder.isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessingLast)
        .opacity(isProcessingLast ? 0.55 : 1)
        .accessibilityLabel(recorder.isRecording ? "停止录音" : "开始录音")
    }

    @ViewBuilder
    private var statusBlock: some View {
        VStack(spacing: 12) {
            if !asrReady {
                VNInlineBanner(
                    kind: .warn,
                    text: "尚未下载 SenseVoice。打开「设置」下载后即可离线转写中文短句。"
                )
            }

            if isProcessingLast {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("离线处理中：转写 → 整理")
                        .font(.subheadline)
                        .foregroundStyle(VNTheme.mist)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            if let errorMessage {
                VNInlineBanner(kind: .error, text: errorMessage)
            }

            if let id = lastCreatedNoteID, !isProcessingLast {
                NavigationLink {
                    NoteDetailView(noteID: id)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("查看刚录的笔记")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(VNTheme.hush)
                    }
                    .font(.subheadline)
                    .foregroundStyle(VNTheme.pine)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(VNTheme.pine.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("全程离线 · 音频与转写仅存本机")
                .font(.caption)
        }
        .foregroundStyle(VNTheme.hush)
    }

    // MARK: - Actions

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
            guard asrReady else {
                errorMessage = "请先下载 SenseVoice 模型后再录音。"
                return
            }
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
