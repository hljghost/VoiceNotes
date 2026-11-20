import Foundation

/// MLX-quantized Qwen2.5 0.5B Instruct (4-bit) for on-device enrichment.
enum QwenModelCatalog {
    static let modelID = OnDeviceEnricher.defaultModelID
    static let hubRepo = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    static let displayName = "Qwen2.5 0.5B Instruct 4bit（MLX）"

    /// Files required under `Models/LLM/qwen2.5-0.5b-instruct/`.
    static let files: [RemoteFile] = [
        RemoteFile(fileName: "config.json", expectedBytes: 783),
        RemoteFile(fileName: "model.safetensors", expectedBytes: 278_064_920),
        RemoteFile(fileName: "tokenizer.json", expectedBytes: 7_031_673),
        RemoteFile(fileName: "tokenizer_config.json", expectedBytes: 7_308),
        RemoteFile(fileName: "special_tokens_map.json", expectedBytes: 613),
        RemoteFile(fileName: "vocab.json", expectedBytes: 2_776_833),
        RemoteFile(fileName: "merges.txt", expectedBytes: 1_671_853),
        RemoteFile(fileName: "added_tokens.json", expectedBytes: 605),
    ]

    static var totalExpectedBytes: Int64 {
        files.reduce(0) { $0 + $1.expectedBytes }
    }

    static func remoteURL(for fileName: String) -> URL {
        URL(string: "https://huggingface.co/\(hubRepo)/resolve/main/\(fileName)")!
    }

    struct RemoteFile: Sendable {
        let fileName: String
        let expectedBytes: Int64
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
