@preconcurrency import AVFoundation
import Accelerate
import Foundation

struct AudioCaptureResult: Sendable {
    let duration: TimeInterval
    let containedSpeech: Bool
    let samples: [Float]
}

final class AudioCapture: @unchecked Sendable {
    typealias SampleHandler = @Sendable (_ samples: [Float], _ level: Float) -> Void

    private let engine = AVAudioEngine()
    private let statsLock = NSLock()
    private var sampleCount = 0
    private var voicedSampleCount = 0
    private var capturedSamples: [Float] = []
    private var running = false
    private let targetRate = 16_000.0
    private let speechRMSFloor: Float = 0.006
    private let minimumVoicedSeconds = 0.06

    func start(handler: @escaping SampleHandler) throws {
        guard !running else { return }
        let input = engine.inputNode
        let sourceFormat = input.inputFormat(forBus: 0)
        guard sourceFormat.channelCount > 0,
              sourceFormat.sampleRate > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetRate,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.unavailableInput
        }

        statsLock.withLock {
            sampleCount = 0
            voicedSampleCount = 0
            capturedSamples.removeAll(keepingCapacity: true)
            running = true
        }

        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = self.targetRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 8
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            let supply = ConverterInputSupply()
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, outputStatus in
                guard supply.take() else {
                    outputStatus.pointee = .noDataNow
                    return nil
                }
                outputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error,
                  conversionError == nil,
                  converted.frameLength > 0,
                  let channel = converted.floatChannelData?.pointee else { return }

            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            var power: Float = 0
            vDSP_svesq(samples, 1, &power, vDSP_Length(samples.count))
            let rms = sqrt(power / Float(max(1, samples.count)))
            self.statsLock.withLock {
                self.sampleCount += samples.count
                self.capturedSamples.append(contentsOf: samples)
                if rms > self.speechRMSFloor { self.voicedSampleCount += samples.count }
                // Queue encoder work before stop() can take the lock and queue
                // the final decode, so the last microphone buffer is not lost.
                handler(samples, min(1, rms * 14))
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> AudioCaptureResult {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        return statsLock.withLock {
            running = false
            let result = AudioCaptureResult(
                duration: Double(sampleCount) / targetRate,
                containedSpeech: Double(voicedSampleCount) / targetRate >= minimumVoicedSeconds,
                samples: capturedSamples
            )
            capturedSamples.removeAll(keepingCapacity: false)
            return result
        }
    }
}

private final class ConverterInputSupply: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true

    func take() -> Bool {
        lock.withLock {
            guard available else { return false }
            available = false
            return true
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case unavailableInput

    var errorDescription: String? { "找不到可用的麦克风输入。" }
}
