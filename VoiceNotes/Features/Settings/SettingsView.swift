import SwiftUI

struct SettingsView: View {
    @Environment(ModelStore.self) private var modelStore
    @State private var downloadError: String?

    var body: some View {
        List {
            privacySection
            engineSection
            modelsSection
            if let downloadError {
                Section {
                    Text(downloadError)
                        .foregroundStyle(VNTheme.danger)
                        .font(.footnote)
                }
            }
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sections

    private var privacySection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(VNTheme.pine)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据只留在这台手机")
                        .font(.subheadline.weight(.semibold))
                    Text("MVP 禁止云端 LLM。音频、转写与整理结果默认永不上传。")
                        .font(.footnote)
                        .foregroundStyle(VNTheme.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("隐私")
        }
    }

    private var engineSection: some View {
        Section {
            LabeledContent("整理引擎") {
                Text("本机 MLX Qwen")
                    .foregroundStyle(VNTheme.ink)
            }
            if modelStore.qwenReady {
                Text("Qwen 已就绪：真机走端侧 MLX；Simulator 因 Metal 限制会降级为启发式（模型 ID 带 -simulator-heuristic）。")
                    .font(.caption)
                    .foregroundStyle(VNTheme.mist)
            } else {
                Text("尚未下载 Qwen。整理会使用规则摘要（非 LLM），下载后即可端侧推理。")
                    .font(.caption)
                    .foregroundStyle(VNTheme.working)
            }
        } header: {
            Text("整理引擎")
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(modelStore.models, id: \.id) { model in
                modelRow(model)
            }

            HStack {
                Text("总占用")
                Spacer()
                Text(byteString(modelStore.totalBytes))
                    .foregroundStyle(VNTheme.mist)
                    .monospacedDigit()
            }

            Button {
                modelStore.refresh()
            } label: {
                Label("刷新占用", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("模型")
        } footer: {
            Text("转写与整理均从 ModelScope（modelscope.cn）下载。失败可点「下载」重试；也可用 scripts/download-*.sh 侧载。已下载模型可在飞行模式下使用。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: "0.1.4-mvp")
            LabeledContent("转写", value: "SenseVoice · sherpa-onnx")
            LabeledContent("整理", value: "Qwen 0.5B · MLX")
        }
    }

    // MARK: - Model row

    @ViewBuilder
    private func modelRow(_ model: ModelStore.ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kindLabel(model.kind))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VNTheme.hush)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(shortName(model))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(model.isDownloaded ? "已下载" : "未下载")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.isDownloaded ? VNTheme.ready : VNTheme.mist)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (model.isDownloaded ? VNTheme.ready : VNTheme.mist).opacity(0.12),
                        in: Capsule()
                    )
            }

            Text(byteString(model.bytesOnDisk))
                .font(.caption)
                .foregroundStyle(VNTheme.hush)
                .monospacedDigit()

            if let detail = model.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(model.isDownloaded ? VNTheme.mist : VNTheme.working)
            }

            if modelStore.downloadingModelID == model.id {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: modelStore.downloadProgress)
                        .tint(VNTheme.pine)
                    HStack {
                        Text(modelStore.downloadStatusText ?? "下载中…")
                            .font(.caption)
                            .foregroundStyle(VNTheme.mist)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((modelStore.downloadProgress * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(VNTheme.pine)
                    }
                    Button("取消下载", role: .destructive) {
                        modelStore.cancelDownload()
                    }
                    .font(.caption)
                }
                .padding(.top, 2)
            }

            if modelStore.downloadingModelID != model.id {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            downloadError = nil
                            do {
                                try await modelStore.download(modelID: model.id)
                            } catch {
                                downloadError = friendlyDownloadError(error)
                            }
                        }
                    } label: {
                        Text(model.isDownloaded ? "重新下载" : "下载")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VNTheme.pine)
                    .disabled(model.isDownloaded || modelStore.isDownloading)

                    Button("删除", role: .destructive) {
                        try? modelStore.delete(modelID: model.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.isDownloaded || modelStore.isDownloading)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func kindLabel(_ kind: ModelStore.ModelInfo.Kind) -> String {
        switch kind {
        case .asr: return "转写"
        case .llm: return "整理"
        }
    }

    private func shortName(_ model: ModelStore.ModelInfo) -> String {
        switch model.kind {
        case .asr: return "SenseVoice Small int8"
        case .llm: return "Qwen2.5 0.5B Instruct"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func friendlyDownloadError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return ModelDownloadSupport.localizedNetworkError(error)
    }
}
