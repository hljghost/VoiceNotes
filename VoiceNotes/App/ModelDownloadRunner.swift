import Foundation

/// DEBUG: `-AutoDownloadModel <modelID>` downloads a model and writes JSON result.
@MainActor
enum ModelDownloadRunner {
    static let resultFileName = "model-download-result.json"

    static func runIfRequested(dependencies: AppDependencies) async {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-AutoDownloadModel"),
              args.indices.contains(idx + 1)
        else { return }

        let modelID = args[idx + 1]
        let resultURL = AppPaths.applicationSupport.appendingPathComponent(resultFileName)

        struct Payload: Codable {
            var ok: Bool
            var modelID: String
            var asrReady: Bool
            var qwenReady: Bool
            var error: String?
            var bytesOnDisk: Int64?
        }

        do {
            // Fresh download path for reproduction: optional wipe
            if args.contains("-ForceRedownload") {
                try? dependencies.modelStore.delete(modelID: modelID)
            }
            try await dependencies.modelStore.download(modelID: modelID)
            dependencies.modelStore.refresh()
            let info = dependencies.modelStore.models.first(where: { $0.id == modelID })
            let payload = Payload(
                ok: info?.isDownloaded == true,
                modelID: modelID,
                asrReady: dependencies.modelStore.models.first(where: { $0.kind == .asr })?.isDownloaded == true,
                qwenReady: dependencies.modelStore.qwenReady,
                error: nil,
                bytesOnDisk: info?.bytesOnDisk
            )
            write(payload, to: resultURL)
            print("[ModelDownloadRunner] \(String(data: try! JSONEncoder().encode(payload), encoding: .utf8) ?? "")")
        } catch {
            let payload = Payload(
                ok: false,
                modelID: modelID,
                asrReady: dependencies.modelStore.models.first(where: { $0.kind == .asr })?.isDownloaded == true,
                qwenReady: dependencies.modelStore.qwenReady,
                error: (error as? LocalizedError)?.errorDescription
                    ?? ModelDownloadSupport.localizedNetworkError(error),
                bytesOnDisk: nil
            )
            write(payload, to: resultURL)
            print("[ModelDownloadRunner] FAILED \(payload.error ?? "")")
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("[ModelDownloadRunner] write failed: \(error)")
        }
    }
}
