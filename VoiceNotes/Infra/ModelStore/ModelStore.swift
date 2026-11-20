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

    func refresh() {
        models = [
            makeInfo(
                id: SenseVoiceModelCatalog.modelID,
                kind: .asr,
                displayName: "SenseVoice Small int8（sherpa-onnx）",
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

    func download(modelID: String) async throws {
        guard modelID == SenseVoiceModelCatalog.modelID else {
            throw ModelStoreError.notImplemented(modelID)
        }
        guard !isDownloading else {
            throw ModelStoreError.alreadyDownloading
        }

        downloadingModelID = modelID
        downloadProgress = 0
        downloadStatusText = "准备下载…"
        defer {
            downloadingModelID = nil
            downloadStatusText = nil
            downloadProgress = 0
            refresh()
        }

        let destination = asrDirectory.appendingPathComponent(modelID, isDirectory: true)
        let tempRoot = asrDirectory.appendingPathComponent(".download-\(modelID)", isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        do {
            let totalExpected = SenseVoiceModelCatalog.files.reduce(Int64(0)) { $0 + $1.expectedBytes }
            var completedBytes: Int64 = 0

            for file in SenseVoiceModelCatalog.files {
                downloadStatusText = "下载 \(file.fileName)…"
                let dest = tempRoot.appendingPathComponent(file.fileName)
                try await downloadFile(
                    from: file.remoteURL,
                    to: dest,
                    expectedBytes: file.expectedBytes
                ) { fileReceived in
                    let overall = Double(completedBytes + fileReceived) / Double(totalExpected)
                    Task { @MainActor in
                        self.downloadProgress = min(max(overall, 0), 1)
                    }
                }
                let size = SenseVoiceModelLayout.fileSize(dest) ?? 0
                // Exact-size check with small tolerance (mirrors / CDN variance).
                let tolerance: Int64 = 256 * 1024
                guard abs(size - file.expectedBytes) <= tolerance else {
                    throw ModelStoreError.checksumFailed(
                        "\(file.fileName) size=\(size) expected≈\(file.expectedBytes)"
                    )
                }
                completedBytes += file.expectedBytes
                downloadProgress = Double(completedBytes) / Double(totalExpected)
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

    private func makeInfo(id: String, kind: ModelInfo.Kind, displayName: String, directory: URL) -> ModelInfo {
        let path = directory.appendingPathComponent(id)
        let exists: Bool
        if kind == .asr, id == SenseVoiceModelCatalog.modelID {
            exists = SenseVoiceModelLayout.isReady(at: path)
        } else {
            exists = FileManager.default.fileExists(atPath: path.path)
        }
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
