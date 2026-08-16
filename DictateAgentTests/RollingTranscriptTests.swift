import XCTest
@testable import DictateAgent

final class RollingTranscriptTests: XCTestCase {
    func testStandardConfigurationUsesDerivedTwentyFivePercentOverlap() {
        let configuration = RollingInferenceConfiguration.standard

        XCTAssertEqual(configuration.baseEncoderWindowSeconds, 8)
        XCTAssertEqual(configuration.refinementWindowSeconds, 32)
        XCTAssertEqual(configuration.overlapSeconds, 8)
        XCTAssertEqual(configuration.strideSeconds, 24)
    }

    func testSixteenSecondRefinementWindowDerivesFourSecondOverlap() {
        let configuration = RollingInferenceConfiguration(
            baseEncoderWindowSeconds: 8,
            refinementWindowSeconds: 16
        )

        XCTAssertEqual(configuration.overlapSeconds, 4)
        XCTAssertEqual(configuration.strideSeconds, 12)
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
