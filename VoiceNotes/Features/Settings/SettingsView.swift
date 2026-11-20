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
                Text("云端增强为后期扩展点，MVP 不可切换。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("整理引擎")
            }

            Section {
                ForEach(modelStore.models) { model in
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

                        HStack {
                            Button("下载") {
                                Task {
                                    do {
                                        try await modelStore.download(modelID: model.id)
                                    } catch {
                                        downloadError = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(model.isDownloaded)

                            Button("删除", role: .destructive) {
                                try? modelStore.delete(modelID: model.id)
                            }
                            .disabled(!model.isDownloaded)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                LabeledContent("总占用", value: byteString(modelStore.totalBytes))
                Button("刷新占用") { modelStore.refresh() }
            } header: {
                Text("模型")
            } footer: {
                Text("ASR：sherpa-onnx SenseVoice · LLM：MLX Qwen 0.5B/0.6B。下载实现见 README。")
            }

            if let downloadError {
                Section {
                    Text(downloadError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "0.1.0-mvp")
                LabeledContent("工程", value: "VoiceNotes")
            }
        }
        .navigationTitle("设置")
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
