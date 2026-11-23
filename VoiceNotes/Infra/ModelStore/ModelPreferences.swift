import Foundation

/// Active on-device model selection (Locally-style「使用 / 已选」).
/// MVP catalog is fixed: SenseVoice ASR + Qwen2.5 0.5B enricher.
/// UserDefaults string get/set is safe across threads for this usage.
final class ModelPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    private enum Keys {
        static let asr = "active_asr_model_id"
        static let llm = "active_llm_model_id"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var activeAsrModelId: String {
        get { defaults.string(forKey: Keys.asr) ?? "" }
        set { defaults.set(newValue, forKey: Keys.asr) }
    }

    var activeLlmModelId: String {
        get { defaults.string(forKey: Keys.llm) ?? "" }
        set { defaults.set(newValue, forKey: Keys.llm) }
    }

    func clearAsrIf(_ modelID: String) {
        if activeAsrModelId == modelID {
            activeAsrModelId = ""
        }
    }

    func clearLlmIf(_ modelID: String) {
        if activeLlmModelId == modelID {
            activeLlmModelId = ""
        }
    }

    /// When weights are on disk but nothing is selected, pick the MVP default.
    func healIfNeeded(asrReady: Bool, llmReady: Bool) {
        if asrReady, activeAsrModelId.isEmpty {
            activeAsrModelId = SenseVoiceModelCatalog.modelID
        }
        if llmReady, activeLlmModelId.isEmpty {
            activeLlmModelId = QwenModelCatalog.modelID
        }
    }
}
