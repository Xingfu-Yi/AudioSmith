import XCTest
@testable import AudioSmith

final class ProfessionalRefinementPolicyTests: XCTestCase {
    func testProfessionalModePlansExactlyOneWholeTranscriptInvocation() {
        XCTAssertEqual(
            ProfessionalRefinementPolicy.invocationCount(
                mode: .professional,
                transcript: "第一段和第二段组成完整 ASR 原文。"
            ),
            1
        )
    }

    func testRecordingChunksAndFastModeNeverPlanTextModelInvocations() {
        XCTAssertEqual(
            ProfessionalRefinementPolicy.invocationCount(mode: .fast, transcript: "八秒窗口文本"),
            0
        )
        XCTAssertEqual(
            ProfessionalRefinementPolicy.invocationCount(mode: .professional, transcript: "  \n"),
            0
        )
    }

    func testOutputAndTimeoutBudgetsAreBounded() {
        let short = ProfessionalRefinementBudget(rawTokenCount: 80)
        XCTAssertEqual(short.outputTokens, 132)
        XCTAssertEqual(short.timeoutSeconds, 8.6, accuracy: 0.001)
        let maximum = ProfessionalRefinementBudget(rawTokenCount: 100_000)
        XCTAssertEqual(maximum.outputTokens, 8 * 1_024)
        XCTAssertEqual(maximum.timeoutSeconds, 45)
    }

    func testPromptIsCompactAndUsesNoProtocolTags() {
        XCTAssertLessThan(RefinementPrompt.systemInstructions.count, 40)
        let prompt = RefinementPrompt.userPrompt(
            transcript: "模型使用 RMSNorm 和 AdaLN。"
        )
        XCTAssertFalse(prompt.contains("<raw_transcript>"))
        XCTAssertFalse(prompt.contains("<dictation_context>"))
        XCTAssertFalse(prompt.contains("术语参考"))
        XCTAssertFalse(prompt.contains("AdaLN <- Adam"))
        XCTAssertTrue(prompt.contains("模型使用 RMSNorm 和 AdaLN。"))
    }

    func testLegacyQwenTemplateGetsExplicitNoThinkingPrefix() {
        XCTAssertTrue(QwenThinkingCompatibility.shouldInjectNoThinkingPrefix(
            templateSupportsThinkingControl: false,
            additionalContext: ["enable_thinking": false]
        ))
        XCTAssertEqual(
            QwenThinkingCompatibility.noThinkingPrefix,
            "<think>\n\n</think>\n\n"
        )
    }

    func testModernQwenTemplateDoesNotDuplicateNoThinkingPrefix() {
        XCTAssertFalse(QwenThinkingCompatibility.shouldInjectNoThinkingPrefix(
            templateSupportsThinkingControl: true,
            additionalContext: ["enable_thinking": false]
        ))
        XCTAssertFalse(QwenThinkingCompatibility.shouldInjectNoThinkingPrefix(
            templateSupportsThinkingControl: false,
            additionalContext: ["enable_thinking": true]
        ))
    }

    func testSanitizerRemovesQwenThinkingAndAnswerWrappers() {
        XCTAssertEqual(
            RefinementOutputSanitizer.sanitize(
                "<think>不要暴露这些内容</think>\n润色后的文本：模型使用 RMSNorm 和 AdaLN。"
            ),
            "模型使用 RMSNorm 和 AdaLN。"
        )
        XCTAssertEqual(
            RefinementOutputSanitizer.sanitize(
                "<|im_start|>assistant\n```text\n模型使用 RMSNorm 和 AdaLN。\n```<|im_end|>"
            ),
            "模型使用 RMSNorm 和 AdaLN。"
        )
    }
}
