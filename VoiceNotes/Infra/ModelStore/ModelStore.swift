import Foundation

/// Tracks on-device model download / presence / disk usage.
/// MVP: local filesystem only — no cloud inference endpoints.
@MainActor
@Observable
final class ModelStore {
    struct ModelInfo: Identifiable, Sendable {
        let id: String
        let kind: Kind
        let displayName: String
        let expectedRelativePath: String
        var isDownloaded: Bool
        var bytesOnDisk: Int64

        enum Kind: String, Sendable {
            case asr
            case llm
        }
    }

    private(set) var models: [ModelInfo] = []

    private let asrDirectory: URL
    private let llmDirectory: URL

    init(asrDirectory: URL = AppPaths.asrModelsDirectory, llmDirectory: URL = AppPaths.llmModelsDirectory) {
        self.asrDirectory = asrDirectory
        self.llmDirectory = llmDirectory
        refresh()
    }

    var totalBytes: Int64 {
        models.reduce(0) { $0 + $1.bytesOnDisk }
    }

    func refresh() {
        models = [
            makeInfo(
                id: SenseVoiceRecognizer.defaultModelID,
                kind: .asr,
                displayName: "SenseVoice Small（sherpa-onnx）",
                directory: asrDirectory
            ),
            makeInfo(
                id: OnDeviceEnricher.defaultModelID,
                kind: .llm,
                displayName: "Qwen 0.5B（MLX）",
                directory: llmDirectory
            ),
        ]
    }

    /// Placeholder for Wi-Fi download. Does not hit any LLM API.
    func download(modelID: String) async throws {
        // TODO: download SenseVoice / Qwen weights into ModelStore directories with hash verify.
        throw ModelStoreError.notImplemented(modelID)
    }

    func delete(modelID: String) throws {
        guard let info = models.first(where: { $0.id == modelID }) else { return }
        let root = info.kind == .asr ? asrDirectory : llmDirectory
        let path = root.appendingPathComponent(info.id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        refresh()
    }

    private func makeInfo(id: String, kind: ModelInfo.Kind, displayName: String, directory: URL) -> ModelInfo {
        let path = directory.appendingPathComponent(id)
        let exists = FileManager.default.fileExists(atPath: path.path)
        let bytes = exists ? (directorySize(path) ?? 0) : 0
        return ModelInfo(
            id: id,
            kind: kind,
            displayName: displayName,
            expectedRelativePath: id,
            isDownloaded: exists,
            bytesOnDisk: bytes
        )
    }

    private func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}

enum ModelStoreError: Error, LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let id):
            return "模型下载尚未实现：\(id)。请按 README 手动放入 Models 目录。"
        }
    }
}
