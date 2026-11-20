import Foundation

/// Official SenseVoice Small (int8) assets for sherpa-onnx.
/// 大陆下载：优先 ModelScope（多镜像仓库），不直连 GitHub / HuggingFace。
enum SenseVoiceModelCatalog {
    /// Local folder name under `Models/ASR/`.
    static let modelID = SenseVoiceRecognizer.defaultModelID

    static let mirrorLabel = "ModelScope"

    /// Primary ModelScope repo（实测 tokens/SHA 与上游 int8 一致）。
    static let modelScopeRepo = "pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue"

    /// Extra ModelScope mirrors if primary is slow / unavailable.
    static let modelScopeMirrorRepos: [String] = [
        "pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue",
        "chriscrs/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
        "vqhvqh/SenseVoice_Small_int8_ONNX",
        "burgess123/sherpa-onnx-SenseVoice-Small-onnx",
        "vcbvcx/SenseVoice_Small_Int8",
        "fengge2024/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
    ]

    /// In-app download: individual files from ModelScope.
    static let files: [RemoteFile] = [
        RemoteFile(
            fileName: SenseVoiceRecognizer.modelFileName,
            expectedBytes: SenseVoiceModelLayout.expectedModelBytes,
            sha256: "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
        ),
        RemoteFile(
            fileName: SenseVoiceRecognizer.tokensFileName,
            expectedBytes: SenseVoiceModelLayout.expectedTokensBytes,
            sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
        ),
    ]

    static func remoteURLs(for fileName: String) -> [URL] {
        modelScopeMirrorRepos.compactMap { repo in
            URL(string: "https://www.modelscope.cn/models/\(repo)/resolve/master/\(fileName)")
        }
    }

    struct RemoteFile: Sendable {
        let fileName: String
        let expectedBytes: Int64
        let sha256: String
    }
}
