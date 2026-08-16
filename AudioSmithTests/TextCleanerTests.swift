import XCTest
@testable import AudioSmith

final class TextCleanerTests: XCTestCase {
    func testCleansWhitespaceAndPunctuation() {
        XCTAssertEqual(
            TextCleaner.clean(" 这是 一个 测试 ， mixed   English ！ "),
            "这是一个测试，mixed English！"
        )
    }

    func testCollapsesRepeatedCompleteSentence() {
        XCTAssertEqual(TextCleaner.clean("模型已经加载。模型已经加载。"), "模型已经加载。")
    }

    func testCollapsesIncompleteSentenceBeforeItsLongerReplacement() {
        XCTAssertEqual(
            TextCleaner.clean("模型使用 RMS Norm 和。模型使用 RMSNorm 和 AdaLN。"),
            "模型使用 RMSNorm 和 AdaLN。"
        )
    }

    func testDoesNotCollapseDistinctAdjacentSentences() {
        XCTAssertEqual(
            TextCleaner.clean("我们使用这个模型。我们使用这个模型训练图像。"),
            "我们使用这个模型。我们使用这个模型训练图像。"
        )
    }

    func testRepairsPunctuationInsertedInsideSelectedCanonicalTerm() {
        XCTAssertEqual(
            TextCleaner.clean(
                "模型使用 RMS。norm 和 Ada L N。",
                canonicalTerms: ["RMSNorm", "AdaLN"]
            ),
            "模型使用 RMSNorm 和 AdaLN。"
        )
    }

    func testDoesNotApplyPhoneticSkillAliasDuringDeterministicCleanup() {
        XCTAssertEqual(
            TextCleaner.clean(
                "a unit test",
                canonicalTerms: ["UNet"]
            ),
            "a unit test"
        )
    }

    func testAppliesLongestReplacementFirst() {
        let result = TextCleaner.clean(
            "Use MLX Audio Swift and M L X.",
            replacements: ["MLX Audio Swift": "MLXAudio Swift", "M L X": "MLX"]
        )
        XCTAssertEqual(result, "Use MLXAudio Swift and MLX.")
    }

    func testEnglishAliasDoesNotReplaceInsideLongerWord() {
        let result = TextCleaner.clean(
            "Keep the repository and open the repo.",
            replacements: ["repo": "repository"]
        )
        XCTAssertEqual(result, "Keep the repository and open the repository.")
    }

    func testChineseAliasStillMatchesWithoutWhitespaceBoundaries() {
        let result = TextCleaner.clean(
            "这里说的是艾普西龙参数。",
            replacements: ["艾普西龙": "epsilon"]
        )
        XCTAssertEqual(result, "这里说的是epsilon参数。")
    }

    func testStripsQwenLanguageProtocolMarker() {
        XCTAssertEqual(
            TextCleaner.stripModelProtocol("language None<asr_text>你现在能听到我说话吗？"),
            "你现在能听到我说话吗？"
        )
        XCTAssertEqual(TextCleaner.stripModelProtocol("language Chinese"), "")
        XCTAssertEqual(TextCleaner.stripModelProtocol("langu"), "")
        XCTAssertEqual(TextCleaner.stripModelProtocol("language"), "")
        XCTAssertEqual(
            TextCleaner.stripModelProtocol("<|im_start|>assistant\nlanguage"),
            ""
        )
    }

    func testStripsRepeatedWindowProtocolMarkers() {
        XCTAssertEqual(
            TextCleaner.stripModelProtocol(
                "language Chinese<asr_text>你好 language English<asr_text>MLX"
            ),
            "你好 MLX"
        )
    }

}
