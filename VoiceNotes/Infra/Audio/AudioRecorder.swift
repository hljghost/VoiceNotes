import AVFoundation
import Foundation

/// Records 16 kHz mono M4A into Application Support / Audio.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var durationSeconds: TimeInterval = 0
    private(set) var currentFileURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let audioDirectory: URL

    init(audioDirectory: URL) {
        self.audioDirectory = audioDirectory
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let filename = "note-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).m4a"
        let url = audioDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw AudioRecorderError.failedToStart
        }

        self.recorder = recorder
        self.currentFileURL = url
        self.isRecording = true
        self.durationSeconds = 0
        startTimer()
    }

    @discardableResult
    func stop() -> (url: URL, durationMs: Int)? {
        guard isRecording, let recorder else { return nil }
        recorder.stop()
        stopTimer()
        isRecording = false

        let durationMs = Int(recorder.currentTime * 1000)
        durationSeconds = recorder.currentTime
        self.recorder = nil

        guard let url = currentFileURL else { return nil }
        return (url, max(durationMs, 0))
    }

    func cancel() {
        recorder?.stop()
        stopTimer()
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        currentFileURL = nil
        isRecording = false
        durationSeconds = 0
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.durationSeconds = recorder.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

enum AudioRecorderError: Error, LocalizedError {
    case failedToStart
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .failedToStart: return "无法开始录音"
        case .permissionDenied: return "未获得麦克风权限"
        }
    }
}
