import XCTest
@testable import AudioSmith

final class RollingTranscriptTests: XCTestCase {
    func testStandardConfigurationUsesDerivedTwentyFivePercentOverlap() {
        let configuration = RollingInferenceConfiguration.standard

        XCTAssertEqual(configuration.baseEncoderWindowSeconds, 8)
        XCTAssertEqual(configuration.refinementWindowSeconds, 8)
        XCTAssertEqual(configuration.overlapSeconds, 2)
        XCTAssertEqual(configuration.strideSeconds, 6)
    }

    func testSixteenSecondRefinementWindowDerivesFourSecondOverlap() {
        let configuration = RollingInferenceConfiguration(
            baseEncoderWindowSeconds: 8,
            refinementWindowSeconds: 16
        )

        XCTAssertEqual(configuration.overlapSeconds, 4)
        XCTAssertEqual(configuration.strideSeconds, 12)
    }

    func testOneRefinementWindowWaitsForFinalization() {
        let end = 8 * 16_000

        XCTAssertFalse(RollingWindowPlanner.shouldDecodeCheckpoint(
            totalSamples: end,
            checkpointEndSample: end
        ))
        XCTAssertTrue(RollingWindowPlanner.shouldDecodeCheckpoint(
            totalSamples: end + 1,
            checkpointEndSample: end
        ))
        XCTAssertEqual(
            RollingWindowPlanner.finalWindow(
                totalSamples: end,
                lastCheckpointEndSample: nil,
                nextWindowStartSample: nil
            ),
            .init(startSample: 0, endSample: end)
        )
    }

    func testEveryShortBoundaryUsesOneWholeRequestFinalWindow() {
        let checkpointEnd = 8 * 16_000
        let durations = [
            1,
            8 * 16_000 - 1,
            8 * 16_000,
        ]

        for totalSamples in durations {
            XCTAssertFalse(RollingWindowPlanner.shouldDecodeCheckpoint(
                totalSamples: totalSamples,
                checkpointEndSample: checkpointEnd
            ))
            XCTAssertEqual(
                RollingWindowPlanner.finalWindow(
                    totalSamples: totalSamples,
                    lastCheckpointEndSample: nil,
                    nextWindowStartSample: nil
                ),
                .init(startSample: 0, endSample: totalSamples)
            )
        }
    }

    func testFinalTailRetainsOverlapAfterCheckpoint() {
        XCTAssertEqual(
            RollingWindowPlanner.finalWindow(
                totalSamples: 12 * 16_000,
                lastCheckpointEndSample: 8 * 16_000,
                nextWindowStartSample: 6 * 16_000
            ),
            .init(startSample: 6 * 16_000, endSample: 12 * 16_000)
        )
    }

    func testPauseAwareBoundaryPrefersNaturalPauseNearNominalCheckpoint() {
        let sampleRate = 1_000
        var samples = Array(repeating: Float(0.20), count: 8 * sampleRate)
        for index in 5_750..<6_050 { samples[index] = 0.001 }

        let selection = RollingWindowBoundarySelector.select(
            samples: samples,
            transcript: "先介绍模型结构，然后讨论训练方法，最后说明推理。",
            sampleRate: sampleRate,
            minimumOverlapSamples: 2 * sampleRate
        )

        XCTAssertTrue(selection.usedPause)
        XCTAssertEqual(selection.offsetSamples, 5_900, accuracy: 40)
    }

    func testPauseAwareBoundaryFallsBackToNominalStrideWithoutPause() {
        let sampleRate = 1_000
        let samples = Array(repeating: Float(0.20), count: 8 * sampleRate)

        let selection = RollingWindowBoundarySelector.select(
            samples: samples,
            transcript: "continuous speech without a pause",
            sampleRate: sampleRate,
            minimumOverlapSamples: 2 * sampleRate
        )

        XCTAssertFalse(selection.usedPause)
        XCTAssertEqual(selection.offsetSamples, 6 * sampleRate)
    }

    func testPauseBeforeSearchRangeIsIgnored() {
        let sampleRate = 1_000
        var samples = Array(repeating: Float(0.20), count: 8 * sampleRate)
        for index in 2_500..<3_000 { samples[index] = 0.001 }

        let selection = RollingWindowBoundarySelector.select(
            samples: samples,
            transcript: "前半段有停顿，但后半段保持连续语音",
            sampleRate: sampleRate,
            minimumOverlapSamples: 2 * sampleRate
        )

        XCTAssertFalse(selection.usedPause)
        XCTAssertEqual(selection.offsetSamples, 6 * sampleRate)
    }

    func testAdaptiveFinalTailStartsAtSelectedBoundary() {
        XCTAssertEqual(
            RollingWindowPlanner.finalWindow(
                totalSamples: 13 * 16_000,
                lastCheckpointEndSample: 8 * 16_000,
                nextWindowStartSample: 5 * 16_000
            ),
            .init(startSample: 5 * 16_000, endSample: 13 * 16_000)
        )
    }

    func testExactCompletedWindowDoesNotDecodeOverlapAgain() {
        XCTAssertNil(
            RollingWindowPlanner.finalWindow(
                totalSamples: 8 * 16_000,
                lastCheckpointEndSample: 8 * 16_000,
                nextWindowStartSample: 6 * 16_000
            )
        )
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

    func testNewerWindowCoveringSamePrefixReplacesEarlierHypothesis() {
        let result = RollingTranscriptAssembler.assemble([
            .init(startSample: 0, endSample: 16, text: "错误的短结果"),
            .init(startSample: 0, endSample: 32, text: "完整而正确的结果")
        ])

        XCTAssertTrue(result.matchedEverySeam)
        XCTAssertEqual(result.text, "完整而正确的结果")
    }
}
