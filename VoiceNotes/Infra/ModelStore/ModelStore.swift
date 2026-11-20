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
        /// Extra status line for Settings (e.g. heuristic fallback note).
        var detail: String?

        enum Kind: String, Sendable {
            case asr
            case llm
        }
    }

    private(set) var models: [ModelInfo] = []
    private(set) var downloadProgress: Double = 0
    private(set) var downloadingModelID: String?
    private(set) var downloadStatusText: String?

    private let asrDirectory: URL
    private let llmDirectory: URL
    private var downloadTask: Task<Void, Never>?

    init(asrDirectory: URL = AppPaths.asrModelsDirectory, llmDirectory: URL = AppPaths.llmModelsDirectory) {
        self.asrDirectory = asrDirectory
        self.llmDirectory = llmDirectory
        refresh()
    }

    var totalBytes: Int64 {
        models.reduce(0) { $0 + $1.bytesOnDisk }
    }

    var isDownloading: Bool { downloadingModelID != nil }

    var qwenReady: Bool {
        QwenModelCatalog.isReady(
            at: llmDirectory.appendingPathComponent(QwenModelCatalog.modelID)
        )
    }

    func refresh() {
        let qwenPath = llmDirectory.appendingPathComponent(QwenModelCatalog.modelID)
        let qwenReady = QwenModelCatalog.isReady(at: qwenPath)
        models = [
            makeInfo(
                id: SenseVoiceModelCatalog.modelID,
                kind: .asr,
                displayName: "SenseVoice Small int8（sherpa-onnx）",
                directory: asrDirectory,
                readyCheck: { SenseVoiceModelLayout.isReady(at: $0) },
                detail: nil
            ),
            makeInfo(
                id: QwenModelCatalog.modelID,
                kind: .llm,
                displayName: QwenModelCatalog.displayName,
                directory: llmDirectory,
                readyCheck: { QwenModelCatalog.isReady(at: $0) },
                detail: qwenReady
                    ? "整理：MLX 端侧推理"
                    : "未下载时整理走启发式降级（非 LLM）"
            ),
        ]
    }

    func download(modelID: String) async throws {
        guard !isDownloading else { throw ModelStoreError.alreadyDownloading }

        if modelID == SenseVoiceModelCatalog.modelID {
            try await downloadBundle(
                modelID: modelID,
                root: asrDirectory,
                files: SenseVoiceModelCatalog.files.map {
                    ($0.fileName, $0.remoteURL, $0.expectedBytes)
                }
            )
            return
        }

        if modelID == QwenModelCatalog.modelID {
            try await downloadBundle(
                modelID: modelID,
                root: llmDirectory,
                files: QwenModelCatalog.files.map {
                    ($0.fileName, QwenModelCatalog.remoteURL(for: $0.fileName), $0.expectedBytes)
                },
                // Tokenizer text files can vary slightly by mirror; weights stay strict.
                sizeTolerance: { name in
                    name.hasSuffix(".safetensors") ? 512 * 1024 : 2 * 1024 * 1024
                }
            )
            return
        }

        throw ModelStoreError.notImplemented(modelID)
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModelID = nil
        downloadStatusText = "已取消"
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

    // MARK: - Private

    private func downloadBundle(
        modelID: String,
        root: URL,
        files: [(String, URL, Int64)],
        sizeTolerance: (String) -> Int64 = { _ in 256 * 1024 }
    ) async throws {
        downloadingModelID = modelID
        downloadProgress = 0
        downloadStatusText = "准备下载…"
        defer {
            downloadingModelID = nil
            downloadStatusText = nil
            downloadProgress = 0
            refresh()
        }

        let destination = root.appendingPathComponent(modelID, isDirectory: true)
        let tempRoot = root.appendingPathComponent(".download-\(modelID)", isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        do {
            let totalExpected = files.reduce(Int64(0)) { $0 + $1.2 }
            var completedBytes: Int64 = 0

            for (fileName, remoteURL, expectedBytes) in files {
                downloadStatusText = "下载 \(fileName)…"
                let dest = tempRoot.appendingPathComponent(fileName)
                try await downloadFile(
                    from: remoteURL,
                    to: dest,
                    expectedBytes: expectedBytes
                ) { fileReceived in
                    let overall = Double(completedBytes + fileReceived) / Double(max(totalExpected, 1))
                    Task { @MainActor in
                        self.downloadProgress = min(max(overall, 0), 1)
                    }
                }
                let size = SenseVoiceModelLayout.fileSize(dest) ?? 0
                let tolerance = sizeTolerance(fileName)
                guard abs(size - expectedBytes) <= tolerance else {
                    throw ModelStoreError.checksumFailed(
                        "\(fileName) size=\(size) expected≈\(expectedBytes)"
                    )
                }
                completedBytes += expectedBytes
                downloadProgress = Double(completedBytes) / Double(max(totalExpected, 1))
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempRoot, to: destination)
            downloadStatusText = "完成"
            downloadProgress = 1
        } catch {
            try? FileManager.default.removeItem(at: tempRoot)
            throw error
        }
    }

    private func makeInfo(
        id: String,
        kind: ModelInfo.Kind,
        displayName: String,
        directory: URL,
        readyCheck: (URL) -> Bool,
        detail: String?
    ) -> ModelInfo {
        let path = directory.appendingPathComponent(id)
        let exists = readyCheck(path)
        let bytes = exists ? (directorySize(path) ?? 0) : 0
        return ModelInfo(
            id: id,
            kind: kind,
            displayName: displayName,
            expectedRelativePath: id,
            isDownloaded: exists,
            bytesOnDisk: bytes,
            detail: detail
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

    private func downloadFile(
        from remoteURL: URL,
        to localURL: URL,
        expectedBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = URLSession(
                configuration: .default,
                delegate: DownloadProgressDelegate(
                    expectedFallback: expectedBytes,
                    onProgress: onProgress,
                    continuation: continuation,
                    destination: localURL
                ),
                delegateQueue: nil
            )
            let task = session.downloadTask(with: remoteURL)
            task.resume()
        }
    }
}

/// URLSession download delegate bridging progress + move into place.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedFallback: Int64
    private let onProgress: @Sendable (Int64) -> Void
    private let continuation: CheckedContinuation<Void, Error>
    private let destination: URL
    private var finished = false

    init(
        expectedFallback: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void,
        continuation: CheckedContinuation<Void, Error>,
        destination: URL
    ) {
        self.expectedFallback = expectedFallback
        self.onProgress = onProgress
        self.continuation = continuation
        self.destination = destination
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
        _ = bytesWritten
        _ = totalBytesExpectedToWrite
        _ = expectedFallback
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                finish(.failure(ModelStoreError.httpError(http.statusCode)))
                return
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            if let size = SenseVoiceModelLayout.fileSize(destination) {
                onProgress(size)
            }
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        continuation.resume(with: result)
    }
}

enum ModelStoreError: Error, LocalizedError {
    case notImplemented(String)
    case alreadyDownloading
    case checksumFailed(String)
    case httpError(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notImplemented(let id):
            return "该模型下载尚未实现：\(id)"
        case .alreadyDownloading:
            return "已有下载任务进行中"
        case .checksumFailed(let name):
            return "文件校验失败：\(name)"
        case .httpError(let code):
            return "下载失败（HTTP \(code)）"
        case .cancelled:
            return "下载已取消"
        }
    }
}
