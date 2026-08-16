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
/// only independent timing parameters. Twenty-five percent is the nominal
/// overlap; runtime window boundaries may move to a nearby clause pause while
/// retaining a safe minimum overlap.
struct RollingInferenceConfiguration: Equatable, Sendable {
    static let overlapFraction = 0.25
    static let standard = RollingInferenceConfiguration(
        baseEncoderWindowSeconds: 8,
        refinementWindowSeconds: 8
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

struct RollingFinalWindow: Equatable, Sendable {
    let startSample: Int
    let endSample: Int
}

enum RollingWindowPlanner {
    /// A checkpoint is intentionally delayed until audio extends beyond its
    /// right edge. This keeps requests up to and including one refinement
    /// window on the single-pass finalization path.
    static func shouldDecodeCheckpoint(totalSamples: Int, checkpointEndSample: Int) -> Bool {
        totalSamples > checkpointEndSample
    }

    static func finalWindow(
        totalSamples: Int,
        lastCheckpointEndSample: Int?,
        nextWindowStartSample: Int?
    ) -> RollingFinalWindow? {
        guard totalSamples > 0 else { return nil }
        if let lastCheckpointEndSample,
           totalSamples <= lastCheckpointEndSample {
            return nil
        }
        let startSample = min(totalSamples, max(0, nextWindowStartSample ?? 0))
        guard totalSamples > startSample else { return nil }
        return .init(
            startSample: startSample,
            endSample: totalSamples
        )
    }
}

struct RollingBoundarySelection: Equatable, Sendable {
    let offsetSamples: Int
    let usedPause: Bool
}

/// Selects the next refinement-window start near the nominal 75% checkpoint.
/// Punctuation supplies only a coarse semantic hint because Qwen's plain ASR
/// result has no word timestamps. The actual cut must land inside a measured
/// low-energy pause, which prevents character-count estimates from clipping
/// speech when the speaker changes pace.
enum RollingWindowBoundarySelector {
    static let minimumSearchFraction = 0.50
    static let targetFraction = 0.75
    static let minimumPauseSeconds = 0.12

    static func select(
        samples: [Float],
        transcript: String,
        sampleRate: Int,
        minimumOverlapSamples: Int
    ) -> RollingBoundarySelection {
        guard !samples.isEmpty, sampleRate > 0 else {
            return .init(offsetSamples: 0, usedPause: false)
        }

        let lowerBound = min(
            samples.count,
            max(0, Int((Double(samples.count) * minimumSearchFraction).rounded()))
        )
        let upperBound = max(lowerBound, samples.count - max(0, minimumOverlapSamples))
        let nominalTarget = min(
            upperBound,
            max(lowerBound, Int((Double(samples.count) * targetFraction).rounded()))
        )
        guard upperBound > lowerBound else {
            return .init(offsetSamples: nominalTarget, usedPause: false)
        }

        let frameSize = max(1, Int((Double(sampleRate) * 0.020).rounded()))
        let hopSize = max(1, Int((Double(sampleRate) * 0.010).rounded()))
        let minimumPauseSamples = max(
            frameSize,
            Int((Double(sampleRate) * minimumPauseSeconds).rounded())
        )

        var frames: [(start: Int, end: Int, rms: Double)] = []
        var frameStart = lowerBound
        while frameStart < upperBound {
            let frameEnd = min(upperBound, frameStart + frameSize)
            guard frameEnd > frameStart else { break }
            var energy = 0.0
            for sample in samples[frameStart..<frameEnd] {
                let value = Double(sample)
                energy += value * value
            }
            frames.append((
                start: frameStart,
                end: frameEnd,
                rms: sqrt(energy / Double(frameEnd - frameStart))
            ))
            frameStart += hopSize
        }

        guard !frames.isEmpty else {
            return .init(offsetSamples: nominalTarget, usedPause: false)
        }

        let sortedLevels = frames.map(\.rms).sorted()
        let quietLevel = sortedLevels[0]
        let speechIndex = min(
            sortedLevels.count - 1,
            Int((Double(sortedLevels.count - 1) * 0.75).rounded())
        )
        let speechLevel = sortedLevels[speechIndex]
        let separation = speechLevel - quietLevel

        // A flat envelope does not contain a defensible pause. Falling back to
        // the nominal checkpoint is safer than cutting at a quiet phoneme.
        guard speechLevel >= 0.006,
              separation >= max(0.002, speechLevel * 0.18) else {
            return .init(offsetSamples: nominalTarget, usedPause: false)
        }
        let quietThreshold = quietLevel + separation * 0.30

        var pauses: [(center: Int, duration: Int)] = []
        var runStart: Int?
        var runEnd = lowerBound

        func finishRun() {
            guard let start = runStart else { return }
            let duration = runEnd - start
            if duration >= minimumPauseSamples {
                pauses.append((center: start + duration / 2, duration: duration))
            }
            runStart = nil
        }

        for frame in frames {
            if frame.rms <= quietThreshold {
                if runStart == nil { runStart = frame.start }
                runEnd = frame.end
            } else {
                finishRun()
            }
        }
        finishRun()

        guard !pauses.isEmpty else {
            return .init(offsetSamples: nominalTarget, usedPause: false)
        }

        let maximumFraction = Double(upperBound) / Double(samples.count)
        let punctuationFraction = punctuationTargetFraction(
            in: transcript,
            maximumFraction: maximumFraction
        )
        let semanticTarget = punctuationFraction.map {
            Int((Double(samples.count) * ($0 * 0.65 + targetFraction * 0.35)).rounded())
        } ?? nominalTarget

        let selected = pauses.min { left, right in
            let leftScore = abs(left.center - semanticTarget)
                + abs(left.center - nominalTarget) / 4
            let rightScore = abs(right.center - semanticTarget)
                + abs(right.center - nominalTarget) / 4
            if leftScore == rightScore { return left.duration > right.duration }
            return leftScore < rightScore
        }!

        return .init(
            offsetSamples: min(upperBound, max(lowerBound, selected.center)),
            usedPause: true
        )
    }

    static func punctuationTargetFraction(
        in transcript: String,
        maximumFraction: Double
    ) -> Double? {
        let units = transcript.filter { !$0.isWhitespace }
        guard units.count >= 2 else { return nil }

        let denominator = Double(units.count - 1)
        return units.enumerated()
            .compactMap { index, character -> Double? in
                guard character.isClauseBoundaryPunctuation else { return nil }
                let fraction = Double(index) / denominator
                guard fraction >= minimumSearchFraction,
                      fraction <= maximumFraction else { return nil }
                return fraction
            }
            .min { abs($0 - targetFraction) < abs($1 - targetFraction) }
    }
}

enum ASRAudioPadding {
    /// Qwen3-ASR's chunker only requires half a second of input. The native
    /// eight-second encoder window is a maximum processing block, not a minimum
    /// request length. Padding short commands to eight seconds wastes several
    /// seconds in the audio tower and can dilute very short speech with silence.
    static let minimumInferenceSeconds = 0.5

    static func trailingSilence(_ samples: [Float], minimumSampleCount: Int) -> [Float] {
        guard samples.count < minimumSampleCount else { return samples }
        return samples + Array(repeating: 0, count: minimumSampleCount - samples.count)
    }
}

enum ASRDecodeBudget {
    /// Keep a modest safety margin for the language prefix and punctuation while
    /// avoiding the old 128-token floor for one- or two-second commands.
    static func maxTokens(sampleCount: Int, sampleRate: Int = 16_000) -> Int {
        let audioSeconds = Double(max(0, sampleCount)) / Double(sampleRate)
        return min(1_024, max(64, Int(ceil(audioSeconds * 16)) + 48))
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

    var isClauseBoundaryPunctuation: Bool {
        switch self {
        case ",", "，", ".", "。", ";", "；", ":", "：", "!", "！", "?", "？":
            true
        default:
            false
        }
    }
}

/// Owns Qwen's waveform-only rolling inference path. The audio tower still uses
/// its native ~8-second blocks internally. The app advances by a nominal six
/// seconds (two-second overlap), preferring a nearby clause pause while
/// retaining enough overlap for deterministic stitching.
@MainActor
final class QwenStreamingEngine {
    private var model: Qwen3ASRModel?
    private nonisolated let feeder = RollingSessionFeeder()
    private let configuration = RollingInferenceConfiguration.standard

    var isLoaded: Bool { model != nil }

    func load(from directory: URL) async throws {
        model = try await Qwen3ASRModel.fromModelDirectory(directory)
    }

    func unload() {
        feeder.cancel()
        model = nil
        Memory.clearCache()
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
                chunkDuration: 16,
                minChunkDuration: 0.5
            )
            Memory.clearCache()
        }.value
    }

    /// Skills remain request-scoped for deterministic cleanup, but their full
    /// Markdown body is intentionally not injected into Qwen. A large text
    /// prompt can dominate one- or two-second utterances, adding seconds of
    /// prefill latency and occasionally suppressing an otherwise valid result.
    func begin() {
        guard let model else { return }
        feeder.begin(RollingInferenceSession(
            model: model,
            context: "",
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

    /// One-shot retry path. It is deliberately capped at twelve seconds so a
    /// bad local seam or empty tail can never cause the entire long recording to
    /// be decoded a second time.
    func transcribe(samples: [Float]) async -> LongContextTranscription? {
        guard let model, !samples.isEmpty else { return nil }
        let maximumSamples = 12 * 16_000
        let boundedSamples = samples.count > maximumSamples
            ? Array(samples.suffix(maximumSamples))
            : samples
        let modelBox = UnsafeSendableBox(model)
        let audioSeconds = Double(boundedSamples.count) / 16_000.0
        let maxTokens = ASRDecodeBudget.maxTokens(sampleCount: boundedSamples.count)
        let baseWindowSeconds = configuration.baseEncoderWindowSeconds

        return await Task.detached(priority: .userInitiated) {
            let output = modelBox.value.generate(
                audio: MLXArray(boundedSamples),
                maxTokens: maxTokens,
                temperature: 0,
                context: "",
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
    private let minimumOverlapSamples: Int

    private var active = true
    private var buffer: [Float] = []
    private var bufferStartSample = 0
    private var totalSamples = 0
    private var nextWindowStartSample = 0
    private var nextCheckpointEndSample: Int
    private var decodedWindows: [DecodedRollingWindow] = []
    private var totalDecodeSeconds = 0.0
    private var totalGeneratedTokens = 0
    private var measuredPeakMemoryGB = 0.0
    private var finalDecodeSeconds = 0.0
    private var checkpointCount = 0

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
        // Keep at least 25% of the native encoder block (2 seconds by default)
        // even when a punctuation-aligned pause lies near the window's end.
        self.minimumOverlapSamples = Int(
            (configuration.baseEncoderWindowSeconds * 0.25 * Double(sampleRate)).rounded()
        )
        self.nextCheckpointEndSample = refinementWindowSamples
        buffer.reserveCapacity(refinementWindowSamples + 4_096)
    }

    func feedAudio(samples: [Float]) {
        guard active, !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)
        totalSamples += samples.count

        while RollingWindowPlanner.shouldDecodeCheckpoint(
            totalSamples: totalSamples,
            checkpointEndSample: nextCheckpointEndSample
        ) {
            let start = nextWindowStartSample
            guard let audio = self.samples(from: start, to: nextCheckpointEndSample) else { break }
            let decodedWindow = decode(
                audio,
                startSample: start,
                endSample: nextCheckpointEndSample,
                isFinal: false
            )
            checkpointCount += 1
            appendWithLocalSeamRepair(decodedWindow)

            let boundary = RollingWindowBoundarySelector.select(
                samples: audio,
                transcript: decodedWindow.text,
                sampleRate: sampleRate,
                minimumOverlapSamples: minimumOverlapSamples
            )
            nextWindowStartSample = start + boundary.offsetSamples
            nextCheckpointEndSample = nextWindowStartSample + refinementWindowSamples
            // Retain four seconds behind the next start so a failed seam can
            // be repaired with at most a twelve-second local union window.
            discardSamples(before: max(0, nextWindowStartSample - 4 * sampleRate))
        }
    }

    func finish() -> RollingSessionResult? {
        guard active, totalSamples > 0 else { return nil }
        active = false

        if let finalWindow = RollingWindowPlanner.finalWindow(
            totalSamples: totalSamples,
            lastCheckpointEndSample: decodedWindows.last?.endSample,
            nextWindowStartSample: decodedWindows.isEmpty ? nil : nextWindowStartSample
        ) {
            guard let audio = samples(
                from: finalWindow.startSample,
                to: finalWindow.endSample
            ), !audio.isEmpty else {
                reset()
                return nil
            }
            let minimumSampleCount = Int(
                (ASRAudioPadding.minimumInferenceSeconds * Double(sampleRate)).rounded()
            )
            let inferenceAudio = ASRAudioPadding.trailingSilence(
                audio,
                minimumSampleCount: minimumSampleCount
            )
            appendWithLocalSeamRepair(decode(
                inferenceAudio,
                startSample: finalWindow.startSample,
                endSample: finalWindow.endSample,
                isFinal: true
            ))
        }

        let windows = decodedWindows
        let result = RollingSessionResult(
            windows: windows,
            audioSeconds: Double(totalSamples) / Double(sampleRate),
            totalDecodeSeconds: totalDecodeSeconds,
            finalDecodeSeconds: finalDecodeSeconds,
            generatedTokens: totalGeneratedTokens,
            peakMemoryGB: measuredPeakMemoryGB,
            checkpointCount: checkpointCount
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
        let maxTokens = ASRDecodeBudget.maxTokens(
            sampleCount: samples.count,
            sampleRate: sampleRate
        )
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
        let window = DecodedRollingWindow(
            startSample: startSample,
            endSample: endSample,
            text: output.text,
            decodeSeconds: output.totalTime,
            generatedTokens: output.generationTokens,
            peakMemoryGB: output.peakMemoryUsage,
            isFinal: isFinal
        )
        totalDecodeSeconds += output.totalTime
        totalGeneratedTokens += output.generationTokens
        measuredPeakMemoryGB = max(measuredPeakMemoryGB, output.peakMemoryUsage)
        if isFinal { finalDecodeSeconds += output.totalTime }
        return window
    }

    private func appendWithLocalSeamRepair(_ window: DecodedRollingWindow) {
        guard let previous = decodedWindows.last,
              window.startSample < previous.endSample else {
            decodedWindows.append(window)
            return
        }

        let seam = RollingTranscriptAssembler.assemble([
            .init(
                startSample: previous.startSample,
                endSample: previous.endSample,
                text: previous.text
            ),
            .init(startSample: window.startSample, endSample: window.endSample, text: window.text),
        ])
        guard !seam.matchedEverySeam else {
            decodedWindows.append(window)
            return
        }

        let repairStart = max(previous.startSample, window.endSample - 12 * sampleRate)
        guard let repairAudio = samples(from: repairStart, to: window.endSample),
              !repairAudio.isEmpty else {
            decodedWindows.append(window)
            return
        }

        // Keep the previous hypothesis as the stable prefix and replace only
        // the failed incoming side with a bounded local re-decode.
        decodedWindows.append(decode(
            repairAudio,
            startSample: repairStart,
            endSample: window.endSample,
            isFinal: window.isFinal
        ))
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
        totalDecodeSeconds = 0
        totalGeneratedTokens = 0
        measuredPeakMemoryGB = 0
        finalDecodeSeconds = 0
        checkpointCount = 0
        Memory.clearCache()
    }
}

private final class RollingSessionFeeder: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.xingfuyi.AudioSmith.rolling-audio",
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
