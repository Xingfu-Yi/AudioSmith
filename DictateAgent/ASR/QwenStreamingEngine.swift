import Foundation
import MLX
import MLXAudioSTT

struct LongContextTranscription: Sendable {
    let text: String
    let audioSeconds: Double
    let decodeSeconds: Double
    let finalDecodeSeconds: Double
    let tokensPerSecond: Double
    let peakMemoryGB: Double
    let encodedWindowCount: Int
    let checkpointCount: Int

    var realTimeFactor: Double {
        audioSeconds > 0 ? decodeSeconds / audioSeconds : 0
    }
}

/// The model's native encoder block and the app-level refinement window are the
/// only independent timing parameters. Overlap is always 25% of the refinement
/// window, so a 32-second window advances by 24 seconds.
struct RollingInferenceConfiguration: Equatable, Sendable {
    static let overlapFraction = 0.25
    static let standard = RollingInferenceConfiguration(
        baseEncoderWindowSeconds: 8,
        refinementWindowSeconds: 32
    )

    let baseEncoderWindowSeconds: Double
    let refinementWindowSeconds: Double

    init(baseEncoderWindowSeconds: Double, refinementWindowSeconds: Double) {
        precondition(baseEncoderWindowSeconds > 0)
        precondition(refinementWindowSeconds >= baseEncoderWindowSeconds)
        self.baseEncoderWindowSeconds = baseEncoderWindowSeconds
        self.refinementWindowSeconds = refinementWindowSeconds
    }

    var overlapSeconds: Double {
        refinementWindowSeconds * Self.overlapFraction
    }

    var strideSeconds: Double {
        refinementWindowSeconds - overlapSeconds
    }
}

struct RollingTranscriptWindow: Equatable, Sendable {
    let startSample: Int
    let endSample: Int
    let text: String
}

struct RollingTranscriptAssembly: Equatable, Sendable {
    let text: String
    let matchedEverySeam: Bool
}

enum RollingTranscriptAssembler {
    static func assemble(_ windows: [RollingTranscriptWindow]) -> RollingTranscriptAssembly {
        let ordered = windows
            .filter { $0.endSample > $0.startSample && !$0.text.isEmpty }
            .sorted {
                if $0.endSample == $1.endSample { return $0.startSample < $1.startSample }
                return $0.endSample < $1.endSample
            }

        guard var previous = ordered.first else {
            return .init(text: "", matchedEverySeam: true)
        }
        var text = previous.text
        var matchedEverySeam = true

        for window in ordered.dropFirst() {
            // A newer hypothesis covering the same prefix supersedes the older
            // one before any part of that prefix has been committed.
            if window.startSample <= previous.startSample,
               window.endSample >= previous.endSample {
                text = window.text
                previous = window
                continue
            }

            if window.startSample < previous.endSample {
                let merged = mergeOverlappingText(text, window.text)
                text = merged.text
                matchedEverySeam = matchedEverySeam && merged.matched
            } else {
                text = join(text, window.text)
            }
            previous = window
        }

        return .init(text: text, matchedEverySeam: matchedEverySeam)
    }

    private static func mergeOverlappingText(
        _ committed: String,
        _ incoming: String
    ) -> (text: String, matched: Bool) {
        let left = lexicalUnits(in: committed)
        let right = lexicalUnits(in: incoming)
        let maximum = min(96, min(left.count, right.count))

        if maximum >= 2 {
            for count in stride(from: maximum, through: 2, by: -1) {
                let suffix = left.suffix(count).map(\.normalized)
                let prefix = right.prefix(count).map(\.normalized)
                if suffix == prefix, let last = right.dropFirst(count - 1).first {
                    let remainder = String(incoming[last.range.upperBound...])
                    return (join(committed, remainder), true)
                }
            }
        }

        // Punctuation and spacing are deliberately absent from lexical units.
        // If an overlap was reworded enough to have no stable two-unit anchor,
        // report a low-confidence seam so the caller can run the safe full pass.
        return (join(committed, incoming), false)
    }

    private struct LexicalUnit {
        let normalized: String
        let range: Range<String.Index>
    }

    private static func lexicalUnits(in text: String) -> [LexicalUnit] {
        var units: [LexicalUnit] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.isASCIIWordCharacter {
                let start = index
                repeat {
                    index = text.index(after: index)
                } while index < text.endIndex && text[index].isASCIIWordCharacter
                let value = String(text[start..<index]).lowercased()
                units.append(.init(normalized: value, range: start..<index))
                continue
            }

            let next = text.index(after: index)
            if character.isCJKLexicalUnit {
                units.append(.init(
                    normalized: String(character),
                    range: index..<next
                ))
            }
            index = next
        }
        return units
    }

    private static func join(_ left: String, _ right: String) -> String {
        let left = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        return left + " " + right
    }
}

private extension Character {
    var isASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy {
            $0.isASCII && (
                CharacterSet.alphanumerics.contains($0) || $0.value == 45 || $0.value == 39
            )
        }
    }

    var isCJKLexicalUnit: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }
}

/// Owns Qwen's waveform-only rolling inference path. The audio tower still uses
/// its native ~8-second blocks internally. The app decodes a 32-second window,
/// advances it by 75%, and retains the 25% overlap for deterministic stitching.
@MainActor
final class QwenStreamingEngine {
    private var model: Qwen3ASRModel?
    private nonisolated let feeder = RollingSessionFeeder()
    private let configuration = RollingInferenceConfiguration.standard

    func load(from directory: URL) async throws {
        model = try await Qwen3ASRModel.fromModelDirectory(directory)
    }

    func prewarm() async {
        guard let model else { return }
        let modelBox = UnsafeSendableBox(model)
        _ = await Task.detached(priority: .userInitiated) {
            let silence = MLXArray(Array(repeating: Float(0), count: 8_000))
            _ = modelBox.value.generate(
                audio: silence,
                maxTokens: 8,
                temperature: 0,
                context: "",
                language: nil,
                chunkDuration: 32,
                minChunkDuration: 0.5
            )
            Memory.clearCache()
        }.value
    }

    func begin(skill: DomainSkill) {
        guard let model else { return }
        feeder.begin(RollingInferenceSession(
            model: model,
            context: skill.promptContext,
            configuration: configuration
        ))
    }

    nonisolated func makeAudioSink() -> @Sendable ([Float]) -> Void {
        let feeder = feeder
        return { samples in feeder.feed(samples) }
    }

    func finish() async -> LongContextTranscription? {
        guard let result = await feeder.finish() else { return nil }
        let assembly = RollingTranscriptAssembler.assemble(
            result.windows.map {
                .init(startSample: $0.startSample, endSample: $0.endSample, text: $0.text)
            }
        )
        guard assembly.matchedEverySeam else { return nil }

        return LongContextTranscription(
            text: assembly.text,
            audioSeconds: result.audioSeconds,
            decodeSeconds: result.totalDecodeSeconds,
            finalDecodeSeconds: result.finalDecodeSeconds,
            tokensPerSecond: result.totalDecodeSeconds > 0
                ? Double(result.generatedTokens) / result.totalDecodeSeconds
                : 0,
            peakMemoryGB: result.peakMemoryGB,
            encodedWindowCount: Int(ceil(
                result.audioSeconds / configuration.baseEncoderWindowSeconds
            )),
            checkpointCount: result.checkpointCount
        )
    }

    /// Safe fallback for a low-confidence overlap seam. It restores the former
    /// whole-utterance behavior so a stitching failure never silently duplicates
    /// or drops words in the pasted transcript.
    func transcribe(samples: [Float], skill: DomainSkill) async -> LongContextTranscription? {
        guard let model, !samples.isEmpty else { return nil }
        let modelBox = UnsafeSendableBox(model)
        let audioSeconds = Double(samples.count) / 16_000.0
        let maxTokens = min(8_192, max(128, Int(ceil(audioSeconds * 16)) + 64))
        let context = skill.promptContext
        let baseWindowSeconds = configuration.baseEncoderWindowSeconds

        return await Task.detached(priority: .userInitiated) {
            let output = modelBox.value.generate(
                audio: MLXArray(samples),
                maxTokens: maxTokens,
                temperature: 0,
                context: context,
                language: nil,
                chunkDuration: 360,
                minChunkDuration: 0.5,
                repetitionPenalty: 1,
                repetitionContextSize: 32
            )
            Memory.clearCache()
            return LongContextTranscription(
                text: output.text,
                audioSeconds: audioSeconds,
                decodeSeconds: output.totalTime,
                finalDecodeSeconds: output.totalTime,
                tokensPerSecond: output.totalTime > 0
                    ? Double(output.generationTokens) / output.totalTime
                    : 0,
                peakMemoryGB: output.peakMemoryUsage,
                encodedWindowCount: Int(ceil(audioSeconds / baseWindowSeconds)),
                checkpointCount: 0
            )
        }.value
    }

    func cancel() {
        feeder.cancel()
    }
}

private struct DecodedRollingWindow: Sendable {
    let startSample: Int
    let endSample: Int
    let text: String
    let decodeSeconds: Double
    let generatedTokens: Int
    let peakMemoryGB: Double
    let isFinal: Bool
}

private struct RollingSessionResult: Sendable {
    let windows: [DecodedRollingWindow]
    let audioSeconds: Double
    let totalDecodeSeconds: Double
    let finalDecodeSeconds: Double
    let generatedTokens: Int
    let peakMemoryGB: Double
    let checkpointCount: Int
}

private final class RollingInferenceSession: @unchecked Sendable {
    private let model: Qwen3ASRModel
    private let context: String
    private let configuration: RollingInferenceConfiguration
    private let sampleRate = 16_000
    private let refinementWindowSamples: Int
    private let overlapSamples: Int
    private let strideSamples: Int

    private var active = true
    private var buffer: [Float] = []
    private var bufferStartSample = 0
    private var totalSamples = 0
    private var nextCheckpointEndSample: Int
    private var decodedWindows: [DecodedRollingWindow] = []

    init(
        model: Qwen3ASRModel,
        context: String,
        configuration: RollingInferenceConfiguration
    ) {
        self.model = model
        self.context = context
        self.configuration = configuration
        self.refinementWindowSamples = Int(
            (configuration.refinementWindowSeconds * Double(sampleRate)).rounded()
        )
        self.overlapSamples = Int(
            (configuration.overlapSeconds * Double(sampleRate)).rounded()
        )
        self.strideSamples = refinementWindowSamples - overlapSamples
        self.nextCheckpointEndSample = refinementWindowSamples
        buffer.reserveCapacity(refinementWindowSamples + 4_096)
    }

    func feedAudio(samples: [Float]) {
        guard active, !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)
        totalSamples += samples.count

        while totalSamples >= nextCheckpointEndSample {
            let start = nextCheckpointEndSample - refinementWindowSamples
            guard let audio = self.samples(from: start, to: nextCheckpointEndSample) else { break }
            decodedWindows.append(decode(
                audio,
                startSample: start,
                endSample: nextCheckpointEndSample,
                isFinal: false
            ))
            nextCheckpointEndSample += strideSamples
            discardSamples(before: nextCheckpointEndSample - refinementWindowSamples)
        }
    }

    func finish() -> RollingSessionResult? {
        guard active, totalSamples > 0 else { return nil }
        active = false

        let lastCheckpointEnd = decodedWindows.last?.endSample ?? 0
        if totalSamples > lastCheckpointEnd {
            let finalStart = decodedWindows.last.map {
                max(0, $0.endSample - overlapSamples)
            } ?? 0
            guard let audio = samples(from: finalStart, to: totalSamples), !audio.isEmpty else {
                reset()
                return nil
            }
            decodedWindows.append(decode(
                audio,
                startSample: finalStart,
                endSample: totalSamples,
                isFinal: true
            ))
        }

        let windows = decodedWindows
        let result = RollingSessionResult(
            windows: windows,
            audioSeconds: Double(totalSamples) / Double(sampleRate),
            totalDecodeSeconds: windows.reduce(0) { $0 + $1.decodeSeconds },
            finalDecodeSeconds: windows.last(where: \.isFinal)?.decodeSeconds ?? 0,
            generatedTokens: windows.reduce(0) { $0 + $1.generatedTokens },
            peakMemoryGB: windows.map(\.peakMemoryGB).max() ?? 0,
            checkpointCount: windows.filter { !$0.isFinal }.count
        )
        reset()
        return result
    }

    func cancel() {
        active = false
        reset()
    }

    private func decode(
        _ samples: [Float],
        startSample: Int,
        endSample: Int,
        isFinal: Bool
    ) -> DecodedRollingWindow {
        let audioSeconds = Double(samples.count) / Double(sampleRate)
        let maxTokens = min(1_024, max(128, Int(ceil(audioSeconds * 16)) + 64))
        let output = model.generate(
            audio: MLXArray(samples),
            maxTokens: maxTokens,
            temperature: 0,
            context: context,
            language: nil,
            chunkDuration: Float(configuration.refinementWindowSeconds),
            minChunkDuration: 0.5,
            repetitionPenalty: 1,
            repetitionContextSize: 32
        )
        Memory.clearCache()
        return DecodedRollingWindow(
            startSample: startSample,
            endSample: endSample,
            text: output.text,
            decodeSeconds: output.totalTime,
            generatedTokens: output.generationTokens,
            peakMemoryGB: output.peakMemoryUsage,
            isFinal: isFinal
        )
    }

    private func samples(from start: Int, to end: Int) -> [Float]? {
        let localStart = start - bufferStartSample
        let localEnd = end - bufferStartSample
        guard localStart >= 0, localEnd <= buffer.count, localStart < localEnd else { return nil }
        return Array(buffer[localStart..<localEnd])
    }

    private func discardSamples(before globalSample: Int) {
        let count = min(buffer.count, max(0, globalSample - bufferStartSample))
        guard count > 0 else { return }
        buffer.removeFirst(count)
        bufferStartSample += count
    }

    private func reset() {
        buffer.removeAll(keepingCapacity: false)
        decodedWindows.removeAll(keepingCapacity: false)
        Memory.clearCache()
    }
}

private final class RollingSessionFeeder: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "io.dictateagent.DictateAgent.rolling-audio",
        qos: .userInitiated
    )
    private var session: RollingInferenceSession?

    func begin(_ session: RollingInferenceSession) {
        queue.async { [weak self] in
            self?.session?.cancel()
            self?.session = session
        }
    }

    func feed(_ samples: [Float]) {
        queue.async { [weak self] in
            self?.session?.feedAudio(samples: samples)
        }
    }

    func finish() async -> RollingSessionResult? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let active = self.session
                self.session = nil
                continuation.resume(returning: active?.finish())
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.session?.cancel()
            self?.session = nil
        }
    }
}

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
