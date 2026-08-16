import XCTest
@testable import AudioSmith

final class RefinementValidatorTests: XCTestCase {
    func testAcceptsFaithfulTerminologyAndPunctuationCorrection() {
        XCTAssertTrue(RefinementValidator.accepts(
            candidate: "Diffusion models 的 epsilon prediction 会影响 SNR、RMSNorm、LayerNorm 和 AdaLN。",
            original: "diffusion models 的 app store prediction 会影响 SNR RMS norm layer norm 和 At LN"
        ))
    }

    func testRejectsSummaryOrExpansion() {
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "这段话主要讨论扩散模型，并总结了几个归一化方法的差异和应用场景。",
            original: "我们讨论 diffusion models 和 RMSNorm。"
        ))
    }

    func testRejectsChangedNumbersURLsAndEmailAddresses() {
        let original = "版本 2.1，地址 https://example.com，邮箱 dev@example.com。"
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "版本 2.2，地址 https://example.com，邮箱 dev@example.com。",
            original: original
        ))
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "版本 2.1，地址 https://example.org，邮箱 dev@example.com。",
            original: original
        ))
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "版本 2.1，地址 https://example.com，邮箱 team@example.com。",
            original: original
        ))
    }

    func testRejectsThinkingAndProtocolText() {
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "<think>先分析</think>这是原文。",
            original: "这是原文。"
        ))
        XCTAssertFalse(RefinementValidator.accepts(
            candidate: "<raw_transcript>这是原文。</raw_transcript>",
            original: "这是原文。"
        ))
    }

    func testAllowsTheOrdinaryWordLanguage() {
        XCTAssertTrue(RefinementValidator.accepts(
            candidate: "Swift is a programming language.",
            original: "swift is a programming language"
        ))
    }
}
