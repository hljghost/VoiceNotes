import Foundation

/// MLX-quantized Qwen2.5 0.5B Instruct (4-bit) for on-device enrichment.
/// Downloads from ModelScope（大陆可达），不直连 HuggingFace。
enum QwenModelCatalog {
    static let modelID = OnDeviceEnricher.defaultModelID
    static let hubRepo = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    static let displayName = "Qwen2.5 0.5B Instruct 4bit（MLX）"
    static let mirrorLabel = "ModelScope"

    /// Files required under `Models/LLM/qwen2.5-0.5b-instruct/`.
    static let files: [RemoteFile] = [
        RemoteFile(
            fileName: "config.json",
            expectedBytes: 783,
            sha256: "b045e57ea90b8f1b35f89f954b176a5c1faa02bd0af2c89bcec191239d66cef4"
        ),
        RemoteFile(
            fileName: "model.safetensors",
            expectedBytes: 278_064_920,
            sha256: "ddffab9cbc7bf6dde941c6724841eeca8981fcfa81ca20ff8efff1396326d153"
        ),
        RemoteFile(
            fileName: "tokenizer.json",
            expectedBytes: 7_031_673,
            sha256: "a8506e7111b80c6d8635951a02eab0f4e1a8e4e5772da83846579e97b16f61bf"
        ),
        RemoteFile(
            fileName: "tokenizer_config.json",
            expectedBytes: 7_308,
            sha256: "f7c61e32b7a17d19bf8e7037dcb74079a833e53ea9801f24008cac68458f03b7"
        ),
        RemoteFile(
            fileName: "special_tokens_map.json",
            expectedBytes: 613,
            sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"
        ),
        RemoteFile(
            fileName: "vocab.json",
            expectedBytes: 2_776_833,
            sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
        ),
        RemoteFile(
            fileName: "merges.txt",
            expectedBytes: 1_671_853,
            sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
        ),
        RemoteFile(
            fileName: "added_tokens.json",
            expectedBytes: 605,
            sha256: "58b54bbe36fc752f79a24a271ef66a0a0830054b4dfad94bde757d851968060b"
        ),
    ]

    static var totalExpectedBytes: Int64 {
        files.reduce(0) { $0 + $1.expectedBytes }
    }

    /// ModelScope resolve URL（实测与 HF 权重 SHA 一致）。
    static func remoteURL(for fileName: String) -> URL {
        URL(string: "https://www.modelscope.cn/models/\(hubRepo)/resolve/master/\(fileName)")!
    }

    /// Fallback API path used by some ModelScope clients.
    static func apiURL(for fileName: String) -> URL {
        var comps = URLComponents(
            string: "https://www.modelscope.cn/api/v1/models/\(hubRepo)/repo"
        )!
        comps.queryItems = [
            URLQueryItem(name: "Revision", value: "master"),
            URLQueryItem(name: "FilePath", value: fileName),
        ]
        return comps.url!
    }

    struct RemoteFile: Sendable {
        let fileName: String
        let expectedBytes: Int64
        let sha256: String
    }

    static func isReady(at directory: URL) -> Bool {
        let model = directory.appendingPathComponent("model.safetensors")
        let config = directory.appendingPathComponent("config.json")
        let tokenizer = directory.appendingPathComponent("tokenizer.json")
        guard let modelSize = fileSize(model),
              fileSize(config) != nil,
              fileSize(tokenizer) != nil
        else { return false }
        return modelSize > 200_000_000
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true
        else { return nil }
        return Int64(values.fileSize ?? 0)
    }
}
