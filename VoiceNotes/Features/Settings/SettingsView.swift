import SwiftUI

struct SettingsView: View {
    @Environment(ModelStore.self) private var modelStore
    @State private var downloadError: String?

    var body: some View {
        List {
            Section {
                Text("数据仅存本机。MVP 禁止云端 LLM；音频与转写默认永不上传。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("隐私")
            }

            Section {
                LabeledContent("增强引擎", value: "本机（MLX Qwen）")
                if modelStore.qwenReady {
                    Text("已下载 Qwen：真机端侧 MLX 推理；Simulator 因 Metal 限制自动启发式降级（llmModelID 带 -simulator-heuristic）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未下载 Qwen：整理自动启发式降级（规则摘要，非 LLM）。云端增强为后期扩展点，MVP 不可切换。")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            } header: {
                Text("整理引擎")
            }

            Section {
                let models = modelStore.models
                ForEach(models, id: \.id) { model in
                    modelRow(model)
                }

                LabeledContent("总占用", value: byteString(modelStore.totalBytes))
                Button("刷新占用") { modelStore.refresh() }
            } header: {
                Text("模型")
            } footer: {
                Text(
                    """
                    ASR：SenseVoice Small int8 → Models/ASR/sensevoice-small/
                    LLM：mlx-community/Qwen2.5-0.5B-Instruct-4bit → Models/LLM/qwen2.5-0.5b-instruct/
                    手动：scripts/download-sensevoice.sh · scripts/download-qwen.sh
                    ASR 与 LLM 串行加载，不同时常驻。
                    """
                )
            }

            if let downloadError {
                Section {
                    Text(downloadError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "0.1.1-mvp")
                LabeledContent("ASR", value: "sherpa-onnx SenseVoice")
                LabeledContent("LLM", value: "MLX Qwen 0.5B")
                LabeledContent("工程", value: "VoiceNotes")
            }
        }
        .navigationTitle("设置")
    }

    @ViewBuilder
    private func modelRow(_ model: ModelStore.ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.displayName)
                Spacer()
                Text(model.isDownloaded ? "已下载" : "未下载")
                    .font(.caption)
                    .foregroundStyle(model.isDownloaded ? .green : .secondary)
            }
            Text(byteString(model.bytesOnDisk))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let detail = model.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(model.isDownloaded ? Color.secondary : Color.orange)
            }

            if modelStore.downloadingModelID == model.id {
                ProgressView(value: modelStore.downloadProgress)
                if let status = modelStore.downloadStatusText {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("下载") {
                    Task {
                        downloadError = nil
                        do {
                            try await modelStore.download(modelID: model.id)
                        } catch {
                            downloadError = error.localizedDescription
                        }
                    }
                }
                .disabled(model.isDownloaded || modelStore.isDownloading)

                Button("删除", role: .destructive) {
                    try? modelStore.delete(modelID: model.id)
                }
                .disabled(!model.isDownloaded || modelStore.isDownloading)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
