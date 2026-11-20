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
    private(set) var lastDownloadError: String?

    private let asrDirectory: URL
    private let llmDirectory: URL
    private var downloadTask: Task<Void, Never>?
    private var activeSession: URLSession?

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
                    ? "整理：MLX 端侧推理 · 源 \(QwenModelCatalog.mirrorLabel)"
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
                    DownloadFileSpec(
                        fileName: $0.fileName,
                        candidateURLs: SenseVoiceModelCatalog.remoteURLs(for: $0.fileName),
                        expectedBytes: $0.expectedBytes,
                        sha256: $0.sha256
                    )
                }
            )
            return
        }

        if modelID == QwenModelCatalog.modelID {
            try await downloadBundle(
                modelID: modelID,
                root: llmDirectory,
                files: QwenModelCatalog.files.map {
                    DownloadFileSpec(
                        fileName: $0.fileName,
                        candidateURLs: ModelDownloadSupport.candidateURLs(
                            from: QwenModelCatalog.remoteURL(for: $0.fileName)
                        ),
                        expectedBytes: $0.expectedBytes,
                        sha256: $0.sha256
                    )
                },
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
        activeSession?.invalidateAndCancel()
        activeSession = nil
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

    // MARK: - Generic multi-file bundle (SenseVoice / Qwen)

    private struct DownloadFileSpec {
        let fileName: String
        let candidateURLs: [URL]
        let expectedBytes: Int64
        let sha256: String?
    }

    private func downloadBundle(
        modelID: String,
        root: URL,
        files: [DownloadFileSpec],
        sizeTolerance: (String) -> Int64 = { _ in 256 * 1024 }
    ) async throws {
        downloadingModelID = modelID
        downloadProgress = 0
        downloadStatusText = "准备下载…"
        lastDownloadError = nil
        defer {
            downloadingModelID = nil
            downloadStatusText = nil
            downloadProgress = 0
            activeSession = nil
            refresh()
        }

        let destination = root.appendingPathComponent(modelID, isDirectory: true)
        let tempRoot = root.appendingPathComponent(".download-\(modelID)", isDirectory: true)
        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        do {
            let totalExpected = files.reduce(Int64(0)) { $0 + $1.expectedBytes }
            var completedBytes: Int64 = 0

            for file in files {
                downloadStatusText = "下载 \(file.fileName)…"
                let dest = tempRoot.appendingPathComponent(file.fileName)
                try await downloadFileWithMirrors(
                    candidates: file.candidateURLs,
                    to: dest,
                    expectedBytes: file.expectedBytes,
                    fileName: file.fileName
                ) { fileReceived in
                    let overall = Double(completedBytes + fileReceived) / Double(max(totalExpected, 1))
                    Task { @MainActor in
                        self.downloadProgress = min(max(overall, 0), 1)
                    }
                }
                let size = SenseVoiceModelLayout.fileSize(dest) ?? 0
                let tolerance = sizeTolerance(file.fileName)
                guard abs(size - file.expectedBytes) <= tolerance else {
                    throw ModelStoreError.checksumFailed(
                        "\(file.fileName) size=\(size) expected≈\(file.expectedBytes)。请重试下载。"
                    )
                }
                if let expectedSHA = file.sha256 {
                    downloadStatusText = "校验 \(file.fileName)…"
                    let ok = try FileChecksum.matches(dest, expectedHex: expectedSHA)
                    guard ok else {
                        throw ModelStoreError.checksumFailed(
                            "\(file.fileName) SHA-256 校验失败。请重试；仍失败请换网络或脚本侧载。"
                        )
                    }
                }
                completedBytes += file.expectedBytes
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
            let message = (error as? LocalizedError)?.errorDescription
                ?? ModelDownloadSupport.localizedNetworkError(error)
            lastDownloadError = message
            throw error
        }
    }

    private func downloadFileWithMirrors(
        candidates: [URL],
        to localURL: URL,
        expectedBytes: Int64,
        fileName: String,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let urls = candidates.isEmpty ? [] : candidates
        guard !urls.isEmpty else {
            throw ModelStoreError.network("无可用下载地址。请更新应用或使用 scripts 侧载。")
        }
        var lastError: Error = ModelStoreError.httpError(0)
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { throw ModelStoreError.cancelled }
            downloadStatusText = urls.count > 1
                ? "下载 \(fileName)（源 \(index + 1)/\(urls.count)）…"
                : "下载 \(fileName)…"
            do {
                try await downloadFile(from: url, to: localURL, expectedBytes: expectedBytes, onProgress: onProgress)
                return
            } catch {
                lastError = error
                print("[ModelStore] download failed \(url.absoluteString): \(error)")
                try? FileManager.default.removeItem(at: localURL)
            }
        }
        if let modelError = lastError as? ModelStoreError {
            throw modelError
        }
        throw ModelStoreError.network(ModelDownloadSupport.localizedNetworkError(lastError))
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
            let delegate = DownloadProgressDelegate(
                expectedFallback: expectedBytes,
                onProgress: onProgress,
                continuation: continuation,
                destination: localURL
            )
            let session = ModelDownloadSupport.makeSession(delegate: delegate)
            self.activeSession = session
            var request = URLRequest(url: remoteURL)
            request.setValue("VoiceNotes/0.1 (iOS; ModelStore)", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            let task = session.downloadTask(with: request)
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
    private let lock = NSLock()
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
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = attrs[.size] as? NSNumber ?? 0
            if expectedFallback > 1_000_000, size.int64Value < 10_000 {
                finish(.failure(ModelStoreError.httpError(-1)))
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
        lock.lock()
        defer { lock.unlock() }
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
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let id):
            return "该模型下载尚未实现：\(id)"
        case .alreadyDownloading:
            return "已有下载任务进行中"
        case .checksumFailed(let name):
            return "文件校验失败：\(name)"
        case .httpError(let code):
            if code == -1 {
                return "下载内容异常（可能返回了网页）。请换网络后重试，或用 Mac scripts 侧载。"
            }
            return "下载失败（HTTP \(code)）。请换网络后重试；SenseVoice / Qwen 均走 ModelScope 内地源。"
        case .cancelled:
            return "下载已取消"
        case .network(let message):
            return message
        }
    }
}
