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

/// Audio Smith closes ordinary ASR segments only at natural pauses. The native
/// audio tower can still encode a long request in internal blocks, but no
/// application-level eight-second timer decides where a sentence is cut.
struct PauseSegmentationConfiguration: Equatable, Sendable {
    static let standard = PauseSegmentationConfiguration(
        silenceConfirmationSeconds: 1.2,
        minimumVoicedSeconds: 1.5,
        boundaryOverlapSeconds: 0.4,
        hardMaximumSegmentSeconds: 30,
        speechRMSFloor: 0.006
    )

    let silenceConfirmationSeconds: Double
    let minimumVoicedSeconds: Double
    let boundaryOverlapSeconds: Double
    let hardMaximumSegmentSeconds: Double
    let speechRMSFloor: Float

    init(
        silenceConfirmationSeconds: Double,
        minimumVoicedSeconds: Double,
        boundaryOverlapSeconds: Double,
        hardMaximumSegmentSeconds: Double,
        speechRMSFloor: Float
    ) {
        precondition(silenceConfirmationSeconds > 0)
        precondition(minimumVoicedSeconds >= 0)
        precondition(boundaryOverlapSeconds >= 0)
        precondition(hardMaximumSegmentSeconds > silenceConfirmationSeconds)
        precondition(speechRMSFloor > 0)
        self.silenceConfirmationSeconds = silenceConfirmationSeconds
        self.minimumVoicedSeconds = minimumVoicedSeconds
        self.boundaryOverlapSeconds = boundaryOverlapSeconds
        self.hardMaximumSegmentSeconds = hardMaximumSegmentSeconds
        self.speechRMSFloor = speechRMSFloor
    }
}

enum PauseSegmentBoundaryReason: Equatable, Sendable {
    case naturalPause
    case safetyLimit
}

struct PauseSegmentBoundary: Equatable, Sendable {
    let segmentStartSample: Int
    let segmentEndSample: Int
    let nextSegmentStartSample: Int
    let reason: PauseSegmentBoundaryReason
}

/// Stateful, frame-based pause detector used before ASR. It deliberately does
/// not use recognized punctuation: the audio boundary is chosen before the
/// corresponding model request exists. A thirty-second limit is only a safety
/// valve for uninterrupted speech, never the normal segmentation cadence.
struct PauseSegmentDetector: Sendable {
    private struct Frame: Sendable {
        let start: Int
        let end: Int
        let rms: Float
        let voiced: Bool
    }

    private let configuration: PauseSegmentationConfiguration
    private let sampleRate: Int
    private let frameSamples: Int
    private let silenceConfirmationSamples: Int
    private let minimumVoicedSamples: Int
    private let overlapSamples: Int
    private let hardMaximumSamples: Int
    private let safetySearchSamples: Int

    private var pendingSamples: [Float] = []
    private var pendingOffset = 0
    private var analyzedSampleCount = 0
    private var segmentStartSample = 0
    private var voicedSampleCount = 0
    private var silenceStartSample: Int?
    private var recentFrames: [Frame] = []

    init(
        configuration: PauseSegmentationConfiguration = .standard,
        sampleRate: Int = 16_000
    ) {
        precondition(sampleRate > 0)
        self.configuration = configuration
        self.sampleRate = sampleRate
        self.frameSamples = max(1, Int((0.020 * Double(sampleRate)).rounded()))
        self.silenceConfirmationSamples = Int(
            (configuration.silenceConfirmationSeconds * Double(sampleRate)).rounded()
        )
        self.minimumVoicedSamples = Int(
            (configuration.minimumVoicedSeconds * Double(sampleRate)).rounded()
        )
        self.overlapSamples = Int(
            (configuration.boundaryOverlapSeconds * Double(sampleRate)).rounded()
        )
        self.hardMaximumSamples = Int(
            (configuration.hardMaximumSegmentSeconds * Double(sampleRate)).rounded()
        )
        self.safetySearchSamples = min(
            hardMaximumSamples / 3,
            5 * sampleRate
        )
        pendingSamples.reserveCapacity(frameSamples * 4)
    }

    var hasUncommittedVoice: Bool { voicedSampleCount > 0 }

    mutating func append(_ samples: [Float]) -> [PauseSegmentBoundary] {
        guard !samples.isEmpty else { return [] }
        pendingSamples.append(contentsOf: samples)
        var boundaries: [PauseSegmentBoundary] = []

        while pendingSamples.count - pendingOffset >= frameSamples {
            let frameStart = analyzedSampleCount
            let frameEnd = frameStart + frameSamples
            let localEnd = pendingOffset + frameSamples
            let frameSlice = pendingSamples[pendingOffset..<localEnd]
            var energy: Float = 0
            for sample in frameSlice { energy += sample * sample }
            let rms = sqrt(energy / Float(frameSamples))
            let voiced = rms > configuration.speechRMSFloor
            let frame = Frame(start: frameStart, end: frameEnd, rms: rms, voiced: voiced)
            recentFrames.append(frame)
            pendingOffset = localEnd
            analyzedSampleCount = frameEnd

            if voiced {
                voicedSampleCount += frameSamples
                silenceStartSample = nil
            } else if voicedSampleCount > 0, silenceStartSample == nil {
                silenceStartSample = frameStart
            }

            if let silenceStartSample,
               voicedSampleCount >= minimumVoicedSamples,
               frameEnd - silenceStartSample >= silenceConfirmationSamples {
                let cutSample = silenceStartSample + silenceConfirmationSamples / 2
                let halfOverlap = overlapSamples / 2
                let boundary = PauseSegmentBoundary(
                    segmentStartSample: segmentStartSample,
                    segmentEndSample: min(frameEnd, cutSample + halfOverlap),
                    nextSegmentStartSample: max(segmentStartSample, cutSample - halfOverlap),
                    reason: .naturalPause
                )
                boundaries.append(boundary)
                resetSegmentState(after: boundary.nextSegmentStartSample)
            } else if frameEnd - segmentStartSample >= hardMaximumSamples {
                let boundary = safetyBoundary(at: frameEnd)
                boundaries.append(boundary)
                resetSegmentState(after: boundary.nextSegmentStartSample)
            }

            trimRecentFrames()
        }

        compactPendingSamplesIfNeeded()
        return boundaries
    }

    mutating func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        pendingOffset = 0
        analyzedSampleCount = 0
        segmentStartSample = 0
        voicedSampleCount = 0
        silenceStartSample = nil
        recentFrames.removeAll(keepingCapacity: true)
    }

    private func safetyBoundary(at frameEnd: Int) -> PauseSegmentBoundary {
        let lowerBound = max(
            segmentStartSample + hardMaximumSamples - safetySearchSamples,
            segmentStartSample + overlapSamples
        )
        let upperBound = max(lowerBound, frameEnd - overlapSamples / 2)
        let candidates = recentFrames.filter {
            $0.start >= lowerBound && $0.end <= upperBound
        }
        let target = frameEnd - safetySearchSamples / 2
        let cutSample: Int
        if let minimumRMS = candidates.map(\.rms).min() {
            let quietThreshold = minimumRMS + max(0.0005, minimumRMS * 0.10)
            var runs: [(start: Int, end: Int)] = []
            for frame in candidates where frame.rms <= quietThreshold {
                if let last = runs.last, frame.start <= last.end + frameSamples {
                    runs[runs.count - 1].end = frame.end
                } else {
                    runs.append((start: frame.start, end: frame.end))
                }
            }
            let selected = runs.min { left, right in
                abs((left.start + left.end) / 2 - target)
                    < abs((right.start + right.end) / 2 - target)
            }
            cutSample = selected.map { ($0.start + $0.end) / 2 } ?? upperBound
        } else {
            cutSample = upperBound
        }
        let halfOverlap = overlapSamples / 2
        return PauseSegmentBoundary(
            segmentStartSample: segmentStartSample,
            segmentEndSample: min(frameEnd, cutSample + halfOverlap),
            nextSegmentStartSample: max(segmentStartSample, cutSample - halfOverlap),
            reason: .safetyLimit
        )
    }

    private mutating func resetSegmentState(after nextStart: Int) {
        segmentStartSample = nextStart
        let retained = recentFrames.filter { $0.end > nextStart }
        voicedSampleCount = retained.reduce(into: 0) { total, frame in
            guard frame.voiced else { return }
            total += max(0, frame.end - max(frame.start, nextStart))
        }
        if let lastVoiced = retained.last(where: \.voiced) {
            silenceStartSample = lastVoiced.end < analyzedSampleCount ? lastVoiced.end : nil
        } else {
            silenceStartSample = nil
        }
        recentFrames = retained
    }

    private mutating func trimRecentFrames() {
        let keepAfter = max(segmentStartSample, analyzedSampleCount - safetySearchSamples - overlapSamples)
        if let first = recentFrames.firstIndex(where: { $0.end > keepAfter }), first > 0 {
            recentFrames.removeFirst(first)
        }
    }

    private mutating func compactPendingSamplesIfNeeded() {
        guard pendingOffset >= frameSamples * 8 else { return }
        pendingSamples.removeFirst(pendingOffset)
        pendingOffset = 0
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
    enum Seam: Equatable, Sendable {
        case initial
        case naturalPause
        case overlappingSpeech
    }

    let startSample: Int
    let endSample: Int
    let text: String
    let seam: Seam

    init(
        startSample: Int,
        endSample: Int,
        text: String,
        seam: Seam = .overlappingSpeech
    ) {
        self.startSample = startSample
        self.endSample = endSample
        self.text = text
        self.seam = seam
    }
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

            if window.seam == .naturalPause {
                text = join(text, window.text)
            } else if window.startSample < previous.endSample {
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

/// Owns Qwen's waveform-only pause-segmented inference path. Completed phrases
/// are decoded invisibly while the user is still speaking; the UI continues to
/// show only a waveform and publishes text once after Fn is released.
@MainActor
final class QwenStreamingEngine {
    private var model: Qwen3ASRModel?
    private nonisolated let feeder = RollingSessionFeeder()
    private let configuration = PauseSegmentationConfiguration.standard
    private let nativeEncoderWindowSeconds = 8.0

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

    /// Only the selected Skill's bounded vocabulary context enters ASR. Its
    /// free-form Markdown body is excluded so short commands remain responsive.
    func begin(skill: DomainSkill) {
        guard let model else { return }
        feeder.begin(RollingInferenceSession(
            model: model,
            context: skill.asrContext,
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
                .init(
                    startSample: $0.startSample,
                    endSample: $0.endSample,
                    text: $0.text,
                    seam: $0.seam
                )
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
                result.audioSeconds / nativeEncoderWindowSeconds
            )),
            checkpointCount: result.checkpointCount
        )
    }

    /// One-shot retry path. It is deliberately capped at twelve seconds so a
    /// bad local seam or empty tail can never cause the entire long recording to
    /// be decoded a second time.
    func transcribe(samples: [Float], skill: DomainSkill = .general) async -> LongContextTranscription? {
        guard let model, !samples.isEmpty else { return nil }
        let maximumSamples = 12 * 16_000
        let boundedSamples = samples.count > maximumSamples
            ? Array(samples.suffix(maximumSamples))
            : samples
        let modelBox = UnsafeSendableBox(model)
        let audioSeconds = Double(boundedSamples.count) / 16_000.0
        let maxTokens = ASRDecodeBudget.maxTokens(sampleCount: boundedSamples.count)
        let baseWindowSeconds = nativeEncoderWindowSeconds
        let context = skill.asrContext

        return await Task.detached(priority: .userInitiated) {
            let output = modelBox.value.generate(
                audio: MLXArray(boundedSamples),
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
    let seam: RollingTranscriptWindow.Seam
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
    private let configuration: PauseSegmentationConfiguration
    private let sampleRate = 16_000

    private var active = true
    private var buffer: [Float] = []
    private var bufferStartSample = 0
    private var totalSamples = 0
    private var nextSegmentStartSample = 0
    private var nextSegmentSeam = RollingTranscriptWindow.Seam.initial
    private var detector: PauseSegmentDetector
    private var decodedWindows: [DecodedRollingWindow] = []
    private var totalDecodeSeconds = 0.0
    private var totalGeneratedTokens = 0
    private var measuredPeakMemoryGB = 0.0
    private var finalDecodeSeconds = 0.0
    private var checkpointCount = 0

    init(
        model: Qwen3ASRModel,
        context: String,
        configuration: PauseSegmentationConfiguration
    ) {
        self.model = model
        self.context = context
        self.configuration = configuration
        self.detector = PauseSegmentDetector(
            configuration: configuration,
            sampleRate: sampleRate
        )
        buffer.reserveCapacity(Int(configuration.hardMaximumSegmentSeconds * Double(sampleRate)))
    }

    func feedAudio(samples: [Float]) {
        guard active, !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)
        totalSamples += samples.count

        for boundary in detector.append(samples) {
            guard let segmentAudio = self.samples(
                from: boundary.segmentStartSample,
                to: boundary.segmentEndSample
            ), !segmentAudio.isEmpty else { continue }
            appendWithLocalSeamRepair(decode(
                segmentAudio,
                startSample: boundary.segmentStartSample,
                endSample: boundary.segmentEndSample,
                seam: nextSegmentSeam,
                isFinal: false
            ))
            checkpointCount += 1
            nextSegmentStartSample = boundary.nextSegmentStartSample
            nextSegmentSeam = boundary.reason == .naturalPause
                ? .naturalPause
                : .overlappingSpeech
            // A local seam repair needs at most twelve seconds of prior audio.
            discardSamples(before: max(0, nextSegmentStartSample - 12 * sampleRate))
        }
    }

    func finish() -> RollingSessionResult? {
        guard active, totalSamples > 0 else { return nil }
        active = false

        let shouldDecodeTail = decodedWindows.isEmpty || detector.hasUncommittedVoice
        if shouldDecodeTail, totalSamples > nextSegmentStartSample {
            guard let audio = samples(from: nextSegmentStartSample, to: totalSamples),
                  !audio.isEmpty else {
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
                startSample: nextSegmentStartSample,
                endSample: totalSamples,
                seam: nextSegmentSeam,
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
        seam: RollingTranscriptWindow.Seam,
        isFinal: Bool
    ) -> DecodedRollingWindow {
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
            // Application segmentation already supplied one complete phrase.
            // Keep MLXAudio from imposing another short app-level chunk here.
            chunkDuration: Float(configuration.hardMaximumSegmentSeconds),
            minChunkDuration: 0.5,
            repetitionPenalty: 1,
            repetitionContextSize: 32
        )
        Memory.clearCache()
        let window = DecodedRollingWindow(
            startSample: startSample,
            endSample: endSample,
            text: output.text,
            seam: seam,
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

        // Natural-pause overlap consists primarily of silence and exists only
        // to protect boundary phonemes. It should be joined, not treated as a
        // failed lexical seam that triggers an unnecessary second decode.
        guard window.seam == .overlappingSpeech else {
            decodedWindows.append(window)
            return
        }

        let seam = RollingTranscriptAssembler.assemble([
            .init(
                startSample: previous.startSample,
                endSample: previous.endSample,
                text: previous.text,
                seam: previous.seam
            ),
            .init(
                startSample: window.startSample,
                endSample: window.endSample,
                text: window.text,
                seam: window.seam
            ),
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
            seam: .overlappingSpeech,
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
        detector.reset()
        nextSegmentStartSample = 0
        nextSegmentSeam = .initial
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
