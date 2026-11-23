import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// MLX Swift + Qwen 0.5B on-device enricher.
///
/// - No weights: deterministic **heuristic** fallback (never hits network).
/// - Weights present: load MLX model, generate JSON title/summary/bullets, then unload.
/// - Simulator: MLX Metal often unavailable — fall back to heuristic and tag `llmModelID`.
/// - Cloud LLM is intentionally not implemented — keep `Enricher` for a later path.
actor OnDeviceEnricher: Enricher {
    static let defaultModelID = "qwen2.5-0.5b-instruct"
    static let heuristicModelIDSuffix = "-heuristic"
    static let simulatorFallbackSuffix = "-simulator-heuristic"

    let modelID: String
    private let modelDirectory: URL
    /// Optional — when set, enricher only uses MLX if this model is「使用」active.
    private let modelPreferences: ModelPreferences?
    private var container: ModelContainer?

    /// When true, missing weights (or Simulator Metal gaps) use heuristic instead of throwing.
    var allowHeuristicFallback: Bool = true

    init(
        modelDirectory: URL,
        modelID: String = OnDeviceEnricher.defaultModelID,
        modelPreferences: ModelPreferences? = nil
    ) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
        self.modelPreferences = modelPreferences
    }

    private var bundleDirectory: URL {
        modelDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    private var isSelectedActive: Bool {
        guard let prefs = modelPreferences else { return true }
        let active = prefs.activeLlmModelId
        // Empty → treat installed Qwen as active (auto-heal path).
        return active.isEmpty || active == modelID
    }

    var isModelReady: Bool {
        get async {
            QwenModelCatalog.isReady(at: bundleDirectory) && isSelectedActive
        }
    }

    func enrich(transcript: String) async throws -> Enrichment {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EnricherError.emptyTranscript }

        let weightsReady = QwenModelCatalog.isReady(at: bundleDirectory)
        guard weightsReady, isSelectedActive else {
            if allowHeuristicFallback {
                return heuristicEnrichment(from: trimmed, suffix: Self.heuristicModelIDSuffix)
            }
            throw EnricherError.modelNotReady
        }

        #if targetEnvironment(simulator)
        // Avoid initializing MLX Metal on Simulator (known abort in Device()).
        if allowHeuristicFallback {
            return heuristicEnrichment(from: trimmed, suffix: Self.simulatorFallbackSuffix)
        }
        throw EnricherError.generationFailed("Simulator 不支持 MLX Metal，请在真机验证 Qwen 推理")
        #else
        do {
            let text = try await generateJSON(from: trimmed)
            return try parseEnrichment(from: text, fallbackTranscript: trimmed)
        } catch {
            throw EnricherError.generationFailed(error.localizedDescription)
        }
        #endif
    }

    func unload() async {
        let hadModel = container != nil
        container = nil
        // clearCache() constructs a Metal device — skip when never loaded / on Simulator.
        #if !targetEnvironment(simulator)
        if hadModel {
            Memory.clearCache()
        }
        #endif
    }

    // MARK: - MLX (device)

    private func loadContainer() async throws -> ModelContainer {
        if let container { return container }
        Memory.cacheLimit = 20 * 1024 * 1024
        let loaded = try await loadModelContainer(directory: bundleDirectory)
        container = loaded
        return loaded
    }

    private func generateJSON(from transcript: String) async throws -> String {
        let model = try await loadContainer()
        let instructions = """
        你是中文语音速记整理助手。只根据用户给出的转写原文整理，不要编造原文没有的事实。
        只输出一行 JSON 对象，不要 Markdown、不要代码围栏、不要解释。字段：
        {"title":"不超过20字的标题","summary":"一两句摘要","bullets":["要点1","要点2"],"tags":["标签"]}
        """
        let session = ChatSession(
            model,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 256, temperature: 0.2)
        )
        let prompt = "转写原文：\n\(transcript)"
        let response = try await session.respond(to: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseEnrichment(from raw: String, fallbackTranscript: String) throws -> Enrichment {
        let jsonText = Self.extractJSONObject(from: raw) ?? raw
        guard let data = jsonText.data(using: .utf8) else {
            throw EnricherError.invalidJSON
        }

        struct Payload: Decodable {
            var title: String?
            var summary: String?
            var bullets: [String]?
            var tags: [String]?
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw EnricherError.invalidJSON
        }

        let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (payload.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets = (payload.bullets ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let tags = (payload.tags ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        guard !title.isEmpty || !summary.isEmpty || !bullets.isEmpty else {
            throw EnricherError.invalidJSON
        }

        return Enrichment(
            title: title.isEmpty ? String(fallbackTranscript.prefix(24)) : title,
            summary: summary.isEmpty ? String(fallbackTranscript.prefix(120)) : summary,
            bullets: bullets.isEmpty ? [String(fallbackTranscript.prefix(40))] : bullets,
            tags: tags.isEmpty ? ["速记"] : tags,
            transcriptClean: fallbackTranscript,
            modelID: modelID
        )
    }

    private static func extractJSONObject(from text: String) -> String? {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end {
            return String(text[start...end])
        }
        return nil
    }

    private func heuristicEnrichment(from transcript: String, suffix: String) -> Enrichment {
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
            tags: ["速记", "启发式"],
            transcriptClean: transcript,
            modelID: "\(modelID)\(suffix)"
        )
    }
}
