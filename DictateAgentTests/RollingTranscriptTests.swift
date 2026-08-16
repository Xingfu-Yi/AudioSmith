import XCTest
@testable import DictateAgent

final class RollingTranscriptTests: XCTestCase {
    func testStandardConfigurationUsesDerivedTwentyFivePercentOverlap() {
        let configuration = RollingInferenceConfiguration.standard

        XCTAssertEqual(configuration.baseEncoderWindowSeconds, 8)
        XCTAssertEqual(configuration.refinementWindowSeconds, 16)
        XCTAssertEqual(configuration.overlapSeconds, 4)
        XCTAssertEqual(configuration.strideSeconds, 12)
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
        let end = 16 * 16_000

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
                overlapSamples: 4 * 16_000
            ),
            .init(startSample: 0, endSample: end)
        )
    }

    func testEveryShortBoundaryUsesOneWholeRequestFinalWindow() {
        let checkpointEnd = 16 * 16_000
        let durations = [
            1,
            8 * 16_000 - 1,
            8 * 16_000,
            16 * 16_000 - 1,
            16 * 16_000,
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
                    overlapSamples: 4 * 16_000
                ),
                .init(startSample: 0, endSample: totalSamples)
            )
        }
    }

    func testFinalTailRetainsOverlapAfterCheckpoint() {
        XCTAssertEqual(
            RollingWindowPlanner.finalWindow(
                totalSamples: 20 * 16_000,
                lastCheckpointEndSample: 16 * 16_000,
                overlapSamples: 4 * 16_000
            ),
            .init(startSample: 12 * 16_000, endSample: 20 * 16_000)
        )
    }

    func testShortFinalAudioIsPaddedToNativeEncoderWindow() {
        let samples: [Float] = [0.25, -0.5, 0.75]
        let padded = ASRAudioPadding.trailingSilence(samples, minimumSampleCount: 8)

        XCTAssertEqual(Array(padded.prefix(samples.count)), samples)
        XCTAssertEqual(padded.count, 8)
        XCTAssertEqual(Array(padded.dropFirst(samples.count)), Array(repeating: 0, count: 5))
    }

    func testAudioAtNativeEncoderLengthIsNotPadded() {
        let samples: [Float] = [0.1, 0.2, 0.3]

        XCTAssertEqual(
            ASRAudioPadding.trailingSilence(samples, minimumSampleCount: samples.count),
            samples
        )
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
