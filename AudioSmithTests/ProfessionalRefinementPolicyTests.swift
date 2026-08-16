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
}
