import Foundation

/// Official SenseVoice Small (int8) assets for sherpa-onnx.
enum SenseVoiceModelCatalog {
    /// Local folder name under `Models/ASR/`.
    static let modelID = SenseVoiceRecognizer.defaultModelID

    /// Human-readable release folder / archive stem.
    static let releaseFolderName = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"

    /// Full archive (manual Mac install).
    static let archiveURL = URL(
        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
    )!

    /// Archive SHA-256 (GitHub release digest).
    static let archiveSHA256 = "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"

    /// In-app download: individual files (avoids tar.bz2 on iOS).
    static let files: [RemoteFile] = [
        RemoteFile(
            fileName: SenseVoiceRecognizer.modelFileName,
            // HuggingFace mirror of the same int8 weights shipped in the GitHub archive.
            remoteURL: URL(
                string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx"
            )!,
            expectedBytes: SenseVoiceModelLayout.expectedModelBytes
        ),
        RemoteFile(
            fileName: SenseVoiceRecognizer.tokensFileName,
            remoteURL: URL(
                string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt"
            )!,
            expectedBytes: SenseVoiceModelLayout.expectedTokensBytes
        ),
    ]

    struct RemoteFile: Sendable {
        let fileName: String
        let remoteURL: URL
        let expectedBytes: Int64
    }
}
