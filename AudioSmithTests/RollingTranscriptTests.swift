import XCTest
@testable import AudioSmith

final class RollingTranscriptTests: XCTestCase {
    private func configuration(
        silence: Double = 1.2,
        minimumVoice: Double = 1.5,
        overlap: Double = 0.4,
        hardMaximum: Double = 30
    ) -> PauseSegmentationConfiguration {
        .init(
            silenceConfirmationSeconds: silence,
            minimumVoicedSeconds: minimumVoice,
            boundaryOverlapSeconds: overlap,
            hardMaximumSegmentSeconds: hardMaximum,
            speechRMSFloor: 0.006
        )
    }

    func testStandardConfigurationUsesNaturalPauseAndThirtySecondSafetyLimit() {
        let configuration = PauseSegmentationConfiguration.standard

        XCTAssertEqual(configuration.silenceConfirmationSeconds, 1.2)
        XCTAssertEqual(configuration.minimumVoicedSeconds, 1.5)
        XCTAssertEqual(configuration.boundaryOverlapSeconds, 0.4)
        XCTAssertEqual(configuration.hardMaximumSegmentSeconds, 30)
    }

    func testNaturalPauseClosesSegmentAfterOnePointTwoSeconds() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )
        let speech = Array(repeating: Float(0.10), count: 2 * sampleRate)
        let silence = Array(repeating: Float(0.001), count: 1_200)

        let boundaries = detector.append(speech + silence)

        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries[0].reason, .naturalPause)
        XCTAssertEqual(boundaries[0].segmentStartSample, 0)
        XCTAssertEqual(boundaries[0].segmentEndSample, 2_800, accuracy: 20)
        XCTAssertEqual(boundaries[0].nextSegmentStartSample, 2_400, accuracy: 20)
        XCTAssertFalse(detector.hasUncommittedVoice)
    }

    func testBriefPauseDoesNotSplitPhrase() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )
        let speech = Array(repeating: Float(0.10), count: 2 * sampleRate)
        let briefPause = Array(repeating: Float(0.001), count: 800)

        XCTAssertTrue(detector.append(speech + briefPause + speech).isEmpty)
        XCTAssertTrue(detector.hasUncommittedVoice)
    }

    func testShortUtteranceRemainsAvailableForFnReleaseInsteadOfBeingDiscarded() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )

        XCTAssertTrue(detector.append(Array(repeating: Float(0.10), count: 700)).isEmpty)
        XCTAssertTrue(detector.hasUncommittedVoice)
    }

    func testTooLittleVoiceDoesNotCreateBackgroundSegment() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )
        let shortSpeech = Array(repeating: Float(0.10), count: 1_000)
        let silence = Array(repeating: Float(0.001), count: 1_500)

        XCTAssertTrue(detector.append(shortSpeech + silence).isEmpty)
        XCTAssertTrue(detector.hasUncommittedVoice)
    }

    func testContinuedSilenceDoesNotEmitRepeatedSegments() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )
        let speech = Array(repeating: Float(0.10), count: 2 * sampleRate)
        let firstSilence = Array(repeating: Float(0.001), count: 1_200)
        let moreSilence = Array(repeating: Float(0.001), count: 2 * sampleRate)

        XCTAssertEqual(detector.append(speech + firstSilence).count, 1)
        XCTAssertTrue(detector.append(moreSilence).isEmpty)
        XCTAssertFalse(detector.hasUncommittedVoice)
    }

    func testSafetyLimitUsesLowestEnergyPointNearEndOfContinuousSpeech() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(hardMaximum: 10),
            sampleRate: sampleRate
        )
        var speech = Array(repeating: Float(0.10), count: 10 * sampleRate)
        for index in 8_400..<8_600 { speech[index] = 0.007 }

        let boundaries = detector.append(speech)

        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries[0].reason, .safetyLimit)
        XCTAssertEqual(boundaries[0].segmentEndSample, 8_700, accuracy: 40)
        XCTAssertEqual(boundaries[0].nextSegmentStartSample, 8_300, accuracy: 40)
        XCTAssertTrue(detector.hasUncommittedVoice)
    }

    func testVoiceAfterPauseIsKeptAsFinalTailEvenBelowMinimumSegmentDuration() {
        let sampleRate = 1_000
        var detector = PauseSegmentDetector(
            configuration: configuration(),
            sampleRate: sampleRate
        )
        let speech = Array(repeating: Float(0.10), count: 2 * sampleRate)
        let silence = Array(repeating: Float(0.001), count: 1_200)

        XCTAssertEqual(detector.append(speech + silence).count, 1)
        XCTAssertTrue(detector.append(Array(repeating: Float(0.10), count: 400)).isEmpty)
        XCTAssertTrue(detector.hasUncommittedVoice)
    }

    func testShortFinalAudioIsPaddedToModelMinimumOnly() {
        let samples: [Float] = [0.25, -0.5, 0.75]
        let padded = ASRAudioPadding.trailingSilence(samples, minimumSampleCount: 8)

        XCTAssertEqual(Array(padded.prefix(samples.count)), samples)
        XCTAssertEqual(padded.count, 8)
        XCTAssertEqual(Array(padded.dropFirst(samples.count)), Array(repeating: 0, count: 5))
    }

    func testAudioAtModelMinimumLengthIsNotPadded() {
        let samples: [Float] = [0.1, 0.2, 0.3]

        XCTAssertEqual(
            ASRAudioPadding.trailingSilence(samples, minimumSampleCount: samples.count),
            samples
        )
    }

    func testModelMinimumIsHalfASecondRatherThanEncoderWindow() {
        XCTAssertEqual(ASRAudioPadding.minimumInferenceSeconds, 0.5)
        XCTAssertEqual(
            Int(ASRAudioPadding.minimumInferenceSeconds * 16_000),
            8_000
        )
    }

    func testShortCommandUsesSmallerDecodeBudget() {
        XCTAssertEqual(ASRDecodeBudget.maxTokens(sampleCount: 1 * 16_000), 64)
        XCTAssertEqual(ASRDecodeBudget.maxTokens(sampleCount: 2 * 16_000), 80)
        XCTAssertEqual(ASRDecodeBudget.maxTokens(sampleCount: 16 * 16_000), 304)
    }

    func testAssemblerRemovesChineseEnglishOverlapWithoutChangingCommittedPrefix() {
        let result = RollingTranscriptAssembler.assemble([
            .init(
                startSample: 0,
                endSample: 32,
                text: "我们正在讨论 diffusion models 和 epsilon prediction"
            ),
            .init(
                startSample: 24,
                endSample: 56,
                text: "diffusion models 和 epsilon prediction，以及 flow matching"
            )
        ])

        XCTAssertTrue(result.matchedEverySeam)
        XCTAssertEqual(
            TextCleaner.clean(result.text),
            "我们正在讨论 diffusion models 和 epsilon prediction，以及 flow matching"
        )
    }

    func testAssemblerIgnoresPunctuationAndCaseAtOverlap() {
        let result = RollingTranscriptAssembler.assemble([
            .init(startSample: 0, endSample: 32, text: "Use MLX Audio, then Qwen3-ASR."),
            .init(startSample: 24, endSample: 56, text: "mlx audio then qwen3-asr for dictation")
        ])

        XCTAssertTrue(result.matchedEverySeam)
        XCTAssertEqual(
            result.text,
            "Use MLX Audio, then Qwen3-ASR. for dictation"
        )
    }

    func testAssemblerMarksUnmatchedOverlapForSafeFullPass() {
        let result = RollingTranscriptAssembler.assemble([
            .init(startSample: 0, endSample: 32, text: "第一段完全不同"),
            .init(startSample: 24, endSample: 56, text: "unrelated second segment")
        ])

        XCTAssertFalse(result.matchedEverySeam)
    }

    func testNaturalPauseJoinsIndependentClausesWithoutDemandingLexicalOverlap() {
        let result = RollingTranscriptAssembler.assemble([
            .init(
                startSample: 0,
                endSample: 32,
                text: "第一句话已经自然结束。",
                seam: .initial
            ),
            .init(
                startSample: 28,
                endSample: 64,
                text: "Now continue with a different clause.",
                seam: .naturalPause
            )
        ])

        XCTAssertTrue(result.matchedEverySeam)
        XCTAssertEqual(result.text, "第一句话已经自然结束。 Now continue with a different clause.")
    }

    func testNewerWindowCoveringSamePrefixReplacesEarlierHypothesis() {
        let result = RollingTranscriptAssembler.assemble([
            .init(startSample: 0, endSample: 16, text: "错误的短结果"),
            .init(startSample: 0, endSample: 32, text: "完整而正确的结果")
        ])

        XCTAssertTrue(result.matchedEverySeam)
        XCTAssertEqual(result.text, "完整而正确的结果")
    }
}
