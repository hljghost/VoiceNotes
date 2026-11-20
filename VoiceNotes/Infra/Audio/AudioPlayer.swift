import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        guard player.play() else { return }
        self.player = player
        self.duration = player.duration
        self.isPlaying = true
        startTimer()
    }

    func stop() {
        player?.stop()
        stopTimer()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    func toggle(url: URL) throws {
        if isPlaying {
            stop()
        } else {
            try play(url: url)
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
