import AVFoundation
import Foundation

/// Loads local audio (WAV/M4A/…) into mono float32 PCM at a target sample rate.
enum AudioSampleLoader {
    struct Samples: Sendable {
        let floats: [Float]
        let sampleRate: Int
    }

    static func loadMonoFloat32(url: URL, targetSampleRate: Int = 16_000) throws -> Samples {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpeechRecognizerError.unsupportedAudio
        }
        try file.read(into: inputBuffer)

        let monoInput = try monoFloat32(from: inputBuffer)
        if Int(format.sampleRate) == targetSampleRate {
            return Samples(floats: monoInput, sampleRate: targetSampleRate)
        }

        let resampled = try resample(
            samples: monoInput,
            fromRate: format.sampleRate,
            toRate: Double(targetSampleRate)
        )
        return Samples(floats: resampled, sampleRate: targetSampleRate)
    }

    private static func monoFloat32(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }

        if buffer.format.commonFormat == .pcmFormatFloat32, let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channels[0], count: frames))
            }
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channelCount {
                    sum += channels[c][i]
                }
                mono[i] = sum / Float(channelCount)
            }
            return mono
        }

        // Fallback via converter to float32 mono
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ),
            let converter = AVAudioConverter(from: buffer.format, to: monoFormat),
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: buffer.frameCapacity
            )
        else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }
        guard let data = outBuffer.floatChannelData else {
            throw SpeechRecognizerError.unsupportedAudio
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength)))
    }

    private static func resample(samples: [Float], fromRate: Double, toRate: Double) throws -> [Float] {
        guard let inFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: fromRate,
            channels: 1,
            interleaved: false
        ),
            let outFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: toRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        let ratio = toRate / fromRate
        let outCapacity = AVAudioFrameCount(Double(samples.count) * ratio) + 32
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity)
        else {
            throw SpeechRecognizerError.unsupportedAudio
        }

        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            inBuffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }
        guard let data = outBuffer.floatChannelData else {
            throw SpeechRecognizerError.unsupportedAudio
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(outBuffer.frameLength)))
    }
}
