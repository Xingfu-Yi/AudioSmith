import XCTest
@testable import AudioSmith

final class DomainSkillTests: XCTestCase {
    func testSkillBuildsBoundedPromptAndReplacementMap() {
        let skill = DomainSkill(
            id: "medical",
            name: "医学",
            description: "test",
            context: String(repeating: "x", count: 5_000),
            terms: [.init(preferred: "HbA1c", aliases: ["H B A one C"])]
        )
        XCTAssertLessThanOrEqual(skill.promptContext.count, DomainSkill.promptCharacterLimit)
        XCTAssertEqual(skill.deterministicReplacements["H B A one C"], "HbA1c")
    }

    func testGeneralSkillHasNoContext() {
        XCTAssertTrue(DomainSkill.general.promptContext.isEmpty)
    }

    func testCombinesMultipleSkillsIntoOneBoundedSnapshot() {
        let ai = DomainSkill(
            id: "ai",
            name: "AI",
            description: "AI terms",
            context: "The speaker is discussing diffusion models.",
            terms: [
                .init(preferred: "epsilon", aliases: ["App Store"]),
                .init(preferred: "MLX")
            ]
        )
        let training = DomainSkill(
            id: "training",
            name: "Training",
            description: "Training terms",
            context: "The speaker is discussing training frameworks.",
            terms: [
                .init(preferred: "epsilon", aliases: ["Epsilon"]),
                .init(preferred: "training framework")
            ]
        )

        let snapshot = DomainSkill.combined([training, ai])

        XCTAssertEqual(snapshot.id, "combined")
        XCTAssertTrue(snapshot.promptContext.contains("diffusion models"))
        XCTAssertTrue(snapshot.promptContext.contains("training frameworks"))
        XCTAssertEqual(snapshot.terms.map(\.preferred), ["epsilon", "MLX", "training framework"])
        XCTAssertEqual(snapshot.deterministicReplacements["App Store"], "epsilon")
        XCTAssertLessThanOrEqual(snapshot.promptContext.count, DomainSkill.promptCharacterLimit)
    }

    func testEmptySelectionUsesGeneralSkill() {
        XCTAssertEqual(DomainSkill.combined([]), .general)
    }

    func testCombinedSnapshotBoundsEachSkillContext() {
        let skill = DomainSkill(
            id: "detailed-domain",
            name: "Detailed Domain",
            description: "Detailed context",
            context: String(repeating: "x", count: DomainSkill.perSkillContextCharacterLimit + 500),
            terms: []
        )

        let snapshot = DomainSkill.combined([skill])

        XCTAssertTrue(snapshot.context.hasPrefix("## Detailed Domain\n"))
        XCTAssertEqual(
            snapshot.context.count,
            "## Detailed Domain\n".count + DomainSkill.perSkillContextCharacterLimit
        )
    }

    func testParsesStandardSkillMarkdown() throws {
        let markdown = #"""
        ---
        name: medical
        description: Improve medical dictation.
        ---

        # 医学听写

        ## Dictation context

        The speaker is discussing endocrinology.

        ## Vocabulary

        - `HbA1c`: `H B A one C`, `糖化血红蛋白`
        - `metformin`
        """#

        let skill = try SkillDocumentParser.parse(markdown, folderName: "medical")

        XCTAssertEqual(skill.id, "medical")
        XCTAssertEqual(skill.name, "医学听写")
        XCTAssertEqual(skill.description, "Improve medical dictation.")
        XCTAssertTrue(skill.context.contains("## Dictation context"))
        XCTAssertTrue(skill.context.contains("The speaker is discussing endocrinology."))
        XCTAssertFalse(skill.context.contains("## Vocabulary"))
        XCTAssertEqual(skill.terms.count, 2)
        XCTAssertEqual(skill.terms[0].preferred, "HbA1c")
        XCTAssertEqual(skill.terms[0].aliases, ["H B A one C", "糖化血红蛋白"])
    }

    func testPassesGuidanceAndExamplesAsContextButParsesVocabularySeparately() throws {
        let markdown = #"""
        ---
        name: aigc
        description: Improve AIGC dictation.
        ---

        # AIGC

        ## Dictation context

        Mixed Chinese and English speech.

        ## Transcription guidance

        - Do not translate technical terms.

        ## Examples

        - 艾普西龙 → epsilon

        ## Vocabulary

        - `epsilon`: `艾普西龙`
        """#

        let skill = try SkillDocumentParser.parse(markdown, folderName: "aigc")

        XCTAssertTrue(skill.context.contains("## Transcription guidance"))
        XCTAssertTrue(skill.context.contains("Do not translate technical terms."))
        XCTAssertTrue(skill.context.contains("## Examples"))
        XCTAssertFalse(skill.context.contains("## Vocabulary"))
        XCTAssertEqual(skill.terms, [.init(preferred: "epsilon", aliases: ["艾普西龙"])])
    }

    func testParsesCategorizedVocabularySubheadings() throws {
        let markdown = #"""
        ---
        name: aigc
        description: Improve categorized AIGC dictation.
        ---

        # AIGC

        ## Vocabulary

        ### LLM and Transformer

        - `RMSNorm`: `R M S norm`

        ### Diffusion

        - `v-prediction`: `v prediction`
        """#

        let skill = try SkillDocumentParser.parse(markdown, folderName: "aigc")

        XCTAssertEqual(skill.terms.map(\.preferred), ["RMSNorm", "v-prediction"])
        XCTAssertTrue(skill.context.isEmpty)
    }

    func testRejectsSkillWhoseNameDoesNotMatchFolder() {
        let markdown = """
        ---
        name: legal
        description: Legal terms.
        ---

        ## Vocabulary
        - `amicus curiae`
        """

        XCTAssertThrowsError(try SkillDocumentParser.parse(markdown, folderName: "medical")) { error in
            XCTAssertEqual(
                error as? SkillValidationError,
                .nameDoesNotMatchFolder(name: "legal", folder: "medical")
            )
        }
    }

    func testRepositoryExampleSkillIsValid() throws {
        let skillURL = try XCTUnwrap(
            Bundle(for: Self.self).resourceURL?
                .appendingPathComponent("Skills/medical-dictation/SKILL.md")
        )
        let markdown = try String(contentsOf: skillURL, encoding: .utf8)
        let skill = try SkillDocumentParser.parse(markdown, folderName: "medical-dictation")

        XCTAssertEqual(skill.id, "medical-dictation")
        XCTAssertEqual(skill.name, "医学听写示例")
        XCTAssertEqual(skill.terms.first?.preferred, "HbA1c")
        XCTAssertFalse(skill.promptContext.isEmpty)
    }
}
