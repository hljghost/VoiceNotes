import SwiftUI

struct SettingsView: View {
    @Environment(ModelStore.self) private var modelStore
    @Environment(\.appDependencies) private var dependencies
    @State private var pushManageModels = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                privacySection
                engineSection
                manageModelsSection
                aboutSection
                    .id("settings-about")
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $pushManageModels) {
                ManageModelsView()
            }
            .onAppear {
                modelStore.refresh()
                healSelection()
                openManageModelsIfRequested()
                guard ProcessInfo.processInfo.arguments.contains("-ScrollSettingsFooter") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation {
                        proxy.scrollTo("settings-about", anchor: .bottom)
                    }
                }
            }
        }
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
                    Text("音频、转写与整理结果默认永不上传。")
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
        } header: {
            Text("整理引擎")
        }
    }

    private var manageModelsSection: some View {
        Section {
            NavigationLink {
                ManageModelsView()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("管理模型")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(VNTheme.ink)
                        Text(statusSummary)
                            .font(.caption)
                            .foregroundStyle(VNTheme.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("settings-manage-models")
        } header: {
            Text("模型")
        } footer: {
            Text("转写与整理均从 ModelScope（modelscope.cn）按需下载。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: "0.1.5-mvp")
            LabeledContent("转写", value: "SenseVoice · sherpa-onnx")
            LabeledContent("整理", value: "Qwen 0.5B · MLX")
        }
    }

    // MARK: - Summary

    private var statusSummary: String {
        let asr = modelStore.models.first(where: { $0.kind == .asr })
        let llm = modelStore.models.first(where: { $0.kind == .llm })
        let prefs = dependencies?.modelPreferences
        let asrLine = asrStatusLine(asr, active: prefs?.activeAsrModelId ?? "")
        let llmLine = llmStatusLine(llm, active: prefs?.activeLlmModelId ?? "")
        return "\(asrLine)\n\(llmLine)"
    }

    private func asrStatusLine(_ model: ModelStore.ModelInfo?, active: String) -> String {
        guard let model else { return "SenseVoice · 未知" }
        if model.isDownloaded, active == model.id || active.isEmpty {
            return "SenseVoice · 已就绪"
        }
        if model.isDownloaded {
            return "SenseVoice · 已安装未选用"
        }
        return "SenseVoice · 未安装"
    }

    private func llmStatusLine(_ model: ModelStore.ModelInfo?, active: String) -> String {
        guard let model else { return "Qwen · 未知" }
        if model.isDownloaded, active == model.id || active.isEmpty {
            return "Qwen 0.5B · 已就绪"
        }
        if model.isDownloaded {
            return "Qwen 0.5B · 已安装未选用"
        }
        return "Qwen 0.5B · 未安装（启发式）"
    }

    private func healSelection() {
        guard let prefs = dependencies?.modelPreferences else { return }
        let asrReady = modelStore.models.first(where: { $0.kind == .asr })?.isDownloaded == true
        let llmReady = modelStore.models.first(where: { $0.kind == .llm })?.isDownloaded == true
        prefs.healIfNeeded(asrReady: asrReady, llmReady: llmReady)
    }

    private func openManageModelsIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-OpenManageModels") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pushManageModels = true
        }
    }
}
