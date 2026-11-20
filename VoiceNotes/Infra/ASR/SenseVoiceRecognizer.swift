import Foundation
import SherpaOnnx

/// sherpa-onnx SenseVoice Small offline ASR adapter.
///
/// Model layout (under Application Support):
/// `Models/ASR/sensevoice-small/model.int8.onnx` + `tokens.txt`
///
/// Source package:
/// `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`
/// from https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
actor SenseVoiceRecognizer: SpeechRecognizer {
    static let defaultModelID = "sensevoice-small"
    static let modelFileName = "model.int8.onnx"
    static let tokensFileName = "tokens.txt"

    let modelID: String
    private let modelDirectory: URL
    private var recognizer: SherpaOnnxOfflineRecognizer?

    init(modelDirectory: URL, modelID: String = SenseVoiceRecognizer.defaultModelID) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
    }

    private var bundleDirectory: URL {
        modelDirectory.appendingPathComponent(modelID, isDirectory: true)
    }

    private var modelURL: URL {
        bundleDirectory.appendingPathComponent(Self.modelFileName)
    }

    private var tokensURL: URL {
        bundleDirectory.appendingPathComponent(Self.tokensFileName)
    }

    var isModelReady: Bool {
        get async { SenseVoiceModelLayout.isReady(at: bundleDirectory) }
    }

    func transcribe(url: URL) async throws -> String {
        guard await isModelReady else {
            throw SpeechRecognizerError.modelNotReady
        }

        let samples = try AudioSampleLoader.loadMonoFloat32(url: url, targetSampleRate: 16_000)
        guard !samples.floats.isEmpty else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        let engine = try loadRecognizer()
        let result = engine.decode(samples: samples.floats, sampleRate: samples.sampleRate)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw SpeechRecognizerError.engineFailure("空转写结果（可能太短或无语音）")
        }
        return text
    }

    func unload() async {
        recognizer = nil
    }

    private func loadRecognizer() throws -> SherpaOnnxOfflineRecognizer {
        if let recognizer {
            return recognizer
        }

        let modelPath = modelURL.path
        let tokensPath = tokensURL.path
        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath)
        else {
            throw SpeechRecognizerError.modelNotReady
        }

        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: modelPath,
            language: "zh",
            useInverseTextNormalization: true
        )
        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            senseVoice: senseVoice
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            decodingMethod: "greedy_search"
        )

        // Sherpa Swift wrapper fatalErrors if create fails; validate files above first.
        let engine = SherpaOnnxOfflineRecognizer(config: &config)
        recognizer = engine
        return engine
    }
}

enum SenseVoiceModelLayout {
    static let expectedModelBytes: Int64 = 239_233_841
    static let expectedTokensBytes: Int64 = 315_894

    static func isReady(at directory: URL) -> Bool {
        let model = directory.appendingPathComponent(SenseVoiceRecognizer.modelFileName)
        let tokens = directory.appendingPathComponent(SenseVoiceRecognizer.tokensFileName)
        guard let modelSize = fileSize(model), let tokensSize = fileSize(tokens) else {
            return false
        }
        // Allow small tolerance for alternate mirrors; both files must exist and be non-trivial.
        return modelSize > 200_000_000 && tokensSize > 100_000
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true
        else { return nil }
        return Int64(values.fileSize ?? 0)
    }
}
