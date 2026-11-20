import Foundation

/// MLX Swift + Qwen 0.5B/0.6B on-device enricher.
///
/// **Status**: stub — compiles without linking mlx-swift / mlx-swift-lm.
/// Next step: enable packages in `project.yml`, import `MLXLLM` / `MLXLMCommon`,
/// load Qwen weights from ModelStore, generate JSON {title, summary, bullets}.
///
/// Cloud LLM must NOT be implemented in MVP. Keep `Enricher` as the only
/// extension point for a future `CloudEnricher`.
actor OnDeviceEnricher: Enricher {
    static let defaultModelID = "qwen2.5-0.5b-instruct"

    let modelID: String
    private let modelDirectory: URL
    private var loaded = false

    init(modelDirectory: URL, modelID: String = OnDeviceEnricher.defaultModelID) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
    }

    var isModelReady: Bool {
        get async {
            let modelPath = modelDirectory.appendingPathComponent(modelID)
            return FileManager.default.fileExists(atPath: modelPath.path)
        }
    }

    func enrich(transcript: String) async throws -> Enrichment {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnricherError.emptyTranscript }

        guard await isModelReady else {
            // Deterministic local stub so the pipeline / UI can be exercised offline
            // without downloading weights. Replace with MLX generation when wired.
            return heuristicEnrichment(from: trimmed)
        }

        // TODO(mlx-swift-lm):
        // 1. Load ModelContainer for Qwen 0.5B/0.6B from `modelDirectory`
        // 2. Prompt: 去口语 → 标题 → 摘要 → 要点（可分次调用）
        // 3. Parse/validate JSON into Enrichment
        // 4. Unload after pipeline step (serial with ASR)
        loaded = true
        throw EnricherError.generationFailed(
            "MLX Qwen 适配层已就位，请接入 mlx-swift-lm（见 README）"
        )
    }

    func unload() async {
        // TODO: release ModelContainer / GPU buffers
        loaded = false
        _ = loaded
    }

    /// Offline fallback used when weights are absent — never calls the network.
    private func heuristicEnrichment(from transcript: String) -> Enrichment {
        let title: String
        if let period = transcript.firstIndex(of: "。") {
            title = String(transcript[..<period])
        } else {
            title = String(transcript.prefix(24))
        }

        let summary = String(transcript.prefix(120))
        let bullets = transcript
            .split(whereSeparator: { "。！？\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { String($0) }

        return Enrichment(
            title: title.isEmpty ? "速记" : title,
            summary: summary,
            bullets: Array(bullets),
            tags: ["速记"],
            transcriptClean: transcript,
            modelID: "\(modelID)-stub"
        )
    }
}
