import Foundation

/// Shared download helpers: ModelScope-first mirrors, friendlier network errors.
/// 大陆策略：只走 modelscope.cn；不把 HuggingFace / GitHub / hf-mirror 当作下载源。
enum ModelDownloadSupport {
    /// Build candidate URL list. Catalogs should already point at ModelScope.
    static func candidateURLs(from primary: URL) -> [URL] {
        var urls: [URL] = []
        let host = primary.host?.lowercased() ?? ""

        if host.contains("modelscope.cn") {
            urls.append(primary)
            if let api = modelscopeAPIFallback(from: primary) {
                urls.append(api)
            }
        } else if host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host == "hf-mirror.com" {
            // Rewrite to ModelScope when path looks like /{org}/{repo}/resolve/...
            // Do not keep HF / hf-mirror as candidates (hf-mirror 本机实测 308→HF).
            if let ms = huggingfaceToModelScope(primary) {
                urls.append(ms)
                if let api = modelscopeAPIFallback(from: ms) {
                    urls.append(api)
                }
            }
        } else if host.contains("github.com") || host.contains("githubusercontent.com") {
            // No GitHub direct / gh-proxy: SenseVoice already hosted on ModelScope.
            // Leave empty so caller surfaces a clear Chinese error.
        } else {
            urls.append(primary)
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func modelscopeAPIFallback(from url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 6,
              parts[0] == "models",
              parts[3] == "resolve"
        else { return nil }
        let repo = "\(parts[1])/\(parts[2])"
        let revision = parts[4]
        let filePath = parts.dropFirst(5).joined(separator: "/")
        var comps = URLComponents(string: "https://www.modelscope.cn/api/v1/models/\(repo)/repo")
        comps?.queryItems = [
            URLQueryItem(name: "Revision", value: revision),
            URLQueryItem(name: "FilePath", value: filePath),
        ]
        return comps?.url
    }

    private static func huggingfaceToModelScope(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[2] == "resolve" else { return nil }
        let repo = "\(parts[0])/\(parts[1])"
        let filePath = parts.dropFirst(4).joined(separator: "/")
        return URL(string: "https://www.modelscope.cn/models/\(repo)/resolve/master/\(filePath)")
    }

    static func makeSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 30
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.httpAdditionalHeaders = [
            "User-Agent": "VoiceNotes/0.1 (iOS; ModelStore)",
            "Accept": "*/*",
        ]
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static func localizedNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "无网络连接。请关闭飞行模式并连上 Wi‑Fi 后重试。"
            case .timedOut:
                return "下载超时。请换网络后点「下载」重试，或用 Mac 脚本 scripts/download-*.sh 侧载。"
            case .cannotFindHost, .dnsLookupFailed:
                return "无法解析 ModelScope（modelscope.cn）。请换 Wi‑Fi / 蜂窝后重试；仍失败可用脚本侧载。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "安全连接失败（证书/ATS）。请确认系统时间正确后重试。"
            case .cancelled:
                return "下载已取消"
            default:
                break
            }
        }
        if ns.domain == NSURLErrorDomain {
            return "网络错误（\(ns.code)）：\(ns.localizedDescription)。可重试或侧载。"
        }
        return error.localizedDescription
    }
}
