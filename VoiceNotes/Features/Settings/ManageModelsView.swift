import SwiftUI

/// Dedicated on-device model management (Locally / Android「管理模型」IA).
/// MVP: SenseVoice ASR + MLX Qwen only — no cloud catalog.
struct ManageModelsView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.appDependencies) private var dependencies

    @State private var activeAsr = ""
    @State private var activeLlm = ""
    @State private var asrFailed = false
    @State private var llmFailed = false
    @State private var banner: String?
    @State private var bannerIsError = false

    private enum ModelUiStatus {
        case available, downloading, installed, failed
    }

    var body: some View {
        List {
            Section {
                Text("从 ModelScope（内地）下载到本机。首次需联网，之后可离线录音与整理。")
                    .font(.footnote)
                    .foregroundStyle(VNTheme.mist)
                if let banner {
                    Text(banner)
                        .font(.caption)
                        .foregroundStyle(bannerIsError ? VNTheme.danger : VNTheme.pine)
                }
            }

            Section {
                ForEach(modelStore.models, id: \.id) { model in
                    managedModelRow(model)
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
                    syncSelection()
                } label: {
                    Label("刷新占用", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("模型")
            } footer: {
                Text("未安装整理模型时，笔记仍可用启发式标题/摘要（标注 …-heuristic）。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("管理模型")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            modelStore.refresh()
            syncSelection()
        }
        .onChange(of: modelStore.isDownloading) { _, downloading in
            if !downloading {
                modelStore.refresh()
                syncSelection()
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func managedModelRow(_ model: ModelStore.ModelInfo) -> some View {
        let status = uiStatus(for: model)
        let selected = isSelected(model) && model.isDownloaded

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortName(model))
                        .font(.subheadline.weight(.semibold))
                    Text(summary(model))
                        .font(.caption)
                        .foregroundStyle(VNTheme.mist)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(VNTheme.pine)
                        .accessibilityLabel("已选")
                }
            }

            Text(model.id)
                .font(.caption2)
                .foregroundStyle(VNTheme.hush)

            statusBlock(model: model, status: status)

            actionRow(model: model, status: status, selected: selected)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusBlock(model: ModelStore.ModelInfo, status: ModelUiStatus) -> some View {
        switch status {
        case .available:
            Text("未安装 · \(approximateSizeLabel(model))")
                .font(.caption)
                .foregroundStyle(VNTheme.working)
        case .downloading:
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
                    banner = "下载已取消"
                    bannerIsError = false
                }
                .font(.caption)
            }
        case .installed:
            Text("已就绪 · 占用 \(byteString(model.bytesOnDisk))")
                .font(.caption)
                .foregroundStyle(VNTheme.ready)
        case .failed:
            Text("安装失败 — 检查网络/磁盘后重试（仅 ModelScope）。")
                .font(.caption)
                .foregroundStyle(VNTheme.danger)
        }
    }

    @ViewBuilder
    private func actionRow(
        model: ModelStore.ModelInfo,
        status: ModelUiStatus,
        selected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Button(selected ? "已选" : "使用") {
                select(model)
            }
            .buttonStyle(.bordered)
            .disabled(status != .installed)

            if status == .available || status == .failed {
                Button(status == .failed ? "重试安装" : "安装") {
                    Task { await install(model) }
                }
                .buttonStyle(.borderedProminent)
                .tint(VNTheme.pine)
                .disabled(modelStore.isDownloading)
            }

            if status == .installed || model.bytesOnDisk > 0 {
                Button("卸载", role: .destructive) {
                    Task { await uninstall(model) }
                }
                .buttonStyle(.bordered)
                .disabled(modelStore.isDownloading)
            }

            if status == .installed {
                Button("重新下载") {
                    Task { await install(model, force: true) }
                }
                .buttonStyle(.bordered)
                .disabled(modelStore.isDownloading)
            }
        }
    }

    // MARK: - Actions

    private func install(_ model: ModelStore.ModelInfo, force: Bool = false) async {
        banner = nil
        bannerIsError = false
        clearFailed(model)
        do {
            if force, model.isDownloaded {
                try await uninstallWeights(model, clearSelection: false)
            }
            try await modelStore.download(modelID: model.id)
            select(model)
            banner = "\(shortName(model)) 下载完成"
            bannerIsError = false
        } catch {
            markFailed(model)
            banner = friendlyError(error)
            bannerIsError = true
        }
        syncSelection()
    }

    private func uninstall(_ model: ModelStore.ModelInfo) async {
        do {
            try await uninstallWeights(model, clearSelection: true)
            banner = "已卸载 \(shortName(model))"
            bannerIsError = false
        } catch {
            banner = friendlyError(error)
            bannerIsError = true
        }
        syncSelection()
    }

    private func uninstallWeights(_ model: ModelStore.ModelInfo, clearSelection: Bool) async throws {
        guard let deps = dependencies else {
            try modelStore.delete(modelID: model.id)
            return
        }
        switch model.kind {
        case .asr:
            await deps.speechRecognizer.unload()
            try modelStore.delete(modelID: model.id)
            if clearSelection {
                deps.modelPreferences.clearAsrIf(model.id)
            }
        case .llm:
            await deps.enricher.unload()
            try modelStore.delete(modelID: model.id)
            if clearSelection {
                deps.modelPreferences.clearLlmIf(model.id)
            }
        }
    }

    private func select(_ model: ModelStore.ModelInfo) {
        guard let prefs = dependencies?.modelPreferences else { return }
        switch model.kind {
        case .asr:
            prefs.activeAsrModelId = model.id
            activeAsr = model.id
            banner = "已选用 SenseVoice"
        case .llm:
            prefs.activeLlmModelId = model.id
            activeLlm = model.id
            banner = "已选用 Qwen"
        }
        bannerIsError = false
    }

    // MARK: - Status helpers

    private func syncSelection() {
        guard let prefs = dependencies?.modelPreferences else { return }
        let asrReady = modelStore.models.first(where: { $0.kind == .asr })?.isDownloaded == true
        let llmReady = modelStore.models.first(where: { $0.kind == .llm })?.isDownloaded == true
        prefs.healIfNeeded(asrReady: asrReady, llmReady: llmReady)
        activeAsr = prefs.activeAsrModelId
        activeLlm = prefs.activeLlmModelId
    }

    private func isSelected(_ model: ModelStore.ModelInfo) -> Bool {
        switch model.kind {
        case .asr: return activeAsr == model.id
        case .llm: return activeLlm == model.id
        }
    }

    private func uiStatus(for model: ModelStore.ModelInfo) -> ModelUiStatus {
        if modelStore.downloadingModelID == model.id {
            return .downloading
        }
        if failedFlag(for: model), !model.isDownloaded {
            return .failed
        }
        if model.isDownloaded {
            return .installed
        }
        return .available
    }

    private func failedFlag(for model: ModelStore.ModelInfo) -> Bool {
        switch model.kind {
        case .asr: return asrFailed
        case .llm: return llmFailed
        }
    }

    private func markFailed(_ model: ModelStore.ModelInfo) {
        switch model.kind {
        case .asr: asrFailed = true
        case .llm: llmFailed = true
        }
    }

    private func clearFailed(_ model: ModelStore.ModelInfo) {
        switch model.kind {
        case .asr: asrFailed = false
        case .llm: llmFailed = false
        }
    }

    private func shortName(_ model: ModelStore.ModelInfo) -> String {
        switch model.kind {
        case .asr: return "SenseVoice Small int8"
        case .llm: return "Qwen2.5 0.5B Instruct"
        }
    }

    private func summary(_ model: ModelStore.ModelInfo) -> String {
        switch model.kind {
        case .asr: return "sherpa-onnx · 中英粤日韩转写"
        case .llm: return "MLX · 标题 / 摘要 / 要点"
        }
    }

    private func approximateSizeLabel(_ model: ModelStore.ModelInfo) -> String {
        switch model.kind {
        case .asr: return "约 0.23 GB"
        case .llm: return "约 0.29 GB"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func friendlyError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return ModelDownloadSupport.localizedNetworkError(error)
    }
}
