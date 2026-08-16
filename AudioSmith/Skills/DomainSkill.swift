import Foundation

struct DomainSkill: Equatable, Identifiable, Sendable {
    static let promptCharacterLimit = 8_000
    static let perSkillContextCharacterLimit = 4_000
    static let combinedTermLimit = 300

    struct Term: Equatable, Sendable {
        let preferred: String
        var aliases: [String] = []
    }

    let id: String
    let name: String
    let description: String
    var context: String
    var terms: [Term]

    static let general = DomainSkill(
        id: "general",
        name: "通用听写",
        description: "不添加领域上下文。",
        context: "",
        terms: []
    )

    var promptContext: String {
        guard id != Self.general.id else { return "" }
        var lines = [context.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !terms.isEmpty {
            lines.append("Transcribe verbatim. Prefer these exact domain terms and spellings when acoustically appropriate:")
            lines.append(terms.prefix(Self.combinedTermLimit).map { term in
                let aliases = term.aliases.isEmpty ? "" : " (may sound like: \(term.aliases.joined(separator: ", ")))"
                return "- \(term.preferred)\(aliases)"
            }.joined(separator: "\n"))
        }
        return String(lines.filter { !$0.isEmpty }.joined(separator: "\n").prefix(Self.promptCharacterLimit))
    }

    var deterministicReplacements: [String: String] {
        var result: [String: String] = [:]
        for term in terms.prefix(Self.combinedTermLimit) {
            for alias in term.aliases where !alias.isEmpty && alias.caseInsensitiveCompare(term.preferred) != .orderedSame {
                result[alias] = term.preferred
            }
        }
        return result
    }

    /// Creates the immutable, bounded snapshot used for one dictation. Skills
    /// are sorted by id so the same selection always produces the same prompt.
    static func combined(_ selected: [DomainSkill]) -> DomainSkill {
        let selected = selected
            .filter { $0.id != Self.general.id }
            .sorted { $0.id < $1.id }
        guard !selected.isEmpty else { return .general }

        let sections = selected.compactMap { skill -> String? in
            let body = skill.context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "## \(skill.name)\n\(String(body.prefix(Self.perSkillContextCharacterLimit)))"
        }

        var seenTerms: Set<String> = []
        var combinedTerms: [Term] = []
        for skill in selected {
            for term in skill.terms {
                let key = term.preferred.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                guard seenTerms.insert(key).inserted else { continue }
                combinedTerms.append(term)
                if combinedTerms.count == Self.combinedTermLimit { break }
            }
            if combinedTerms.count == Self.combinedTermLimit { break }
        }

        return DomainSkill(
            id: "combined",
            name: selected.map(\.name).joined(separator: "、"),
            description: "已组合 \(selected.count) 个 Skill；每次听写使用不可变快照。",
            context: sections.joined(separator: "\n\n"),
            terms: combinedTerms
        )
    }
}

enum SkillDocumentParser {
    private static let identifierPattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
    private static let vocabularyHeadings: Set<String> = [
        "vocabulary", "preferred vocabulary", "preferred terms", "词汇", "术语"
    ]

    static func parse(_ markdown: String, folderName: String) throws -> DomainSkill {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else {
            throw SkillValidationError.missingFrontmatter
        }

        var metadata: [String: String] = [:]
        for line in lines[1..<closingIndex] {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "name" || key == "description" else { continue }
            metadata[key] = unquote(String(parts[1]).trimmingCharacters(in: .whitespaces))
        }

        guard let identifier = metadata["name"],
              let description = metadata["description"],
              !identifier.isEmpty,
              !description.isEmpty else {
            throw SkillValidationError.missingRequiredMetadata
        }
        guard identifier.count <= 64,
              identifier.range(of: identifierPattern, options: .regularExpression) != nil else {
            throw SkillValidationError.invalidIdentifier
        }
        guard identifier == folderName else {
            throw SkillValidationError.nameDoesNotMatchFolder(name: identifier, folder: folderName)
        }

        let bodyStart = lines.index(after: closingIndex)
        let body = Array(lines[bodyStart...])
        let displayName = firstLevelOneHeading(in: body) ?? identifier
        let context = promptBodyExcludingVocabulary(in: body)
        let vocabularyLines = section(named: vocabularyHeadings, in: body)
        let terms = try parseTerms(vocabularyLines)

        guard !context.isEmpty || !terms.isEmpty else {
            throw SkillValidationError.missingDictationContent
        }

        return DomainSkill(
            id: identifier,
            name: displayName,
            description: description,
            context: context,
            terms: terms
        )
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func firstLevelOneHeading(in lines: [String]) -> String? {
        lines.lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
    }

    /// Treat the standard Markdown body as bounded ASR context while parsing
    /// Vocabulary separately into preferred spellings and aliases. This lets a
    /// Skill add guidance, examples, or project context without a companion
    /// schema, and still prevents executable resources from being loaded.
    private static func promptBodyExcludingVocabulary(in lines: [String]) -> String {
        var captured: [String] = []
        var isVocabularySection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                isVocabularySection = vocabularyHeadings.contains(heading)
                if !isVocabularySection { captured.append(line) }
                continue
            }
            if trimmed.hasPrefix("# ") { continue }
            if !isVocabularySection { captured.append(line) }
        }

        return captured
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func section(named acceptedHeadings: Set<String>, in lines: [String]) -> [String] {
        var captured: [String] = []
        var isCapturing = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if isCapturing { break }
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                isCapturing = acceptedHeadings.contains(heading)
                continue
            }
            if isCapturing {
                if trimmed.hasPrefix("# ") { break }
                captured.append(line)
            }
        }
        return captured
    }

    private static func parseTerms(_ lines: [String]) throws -> [DomainSkill.Term] {
        var terms: [DomainSkill.Term] = []

        for line in lines where line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
            let components = line.split(separator: "`", omittingEmptySubsequences: false)
            let values = stride(from: 1, to: components.count, by: 2)
                .map { String(components[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let preferred = values.first else { continue }
            terms.append(.init(preferred: preferred, aliases: Array(values.dropFirst())))
            if terms.count > 200 { throw SkillValidationError.tooManyTerms }
        }
        return terms
    }
}

enum SkillValidationError: LocalizedError, Equatable {
    case tooLarge
    case missingFrontmatter
    case missingRequiredMetadata
    case invalidIdentifier
    case nameDoesNotMatchFolder(name: String, folder: String)
    case missingDictationContent
    case tooManyTerms

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            "SKILL.md 超过 256KB 上限。"
        case .missingFrontmatter:
            "SKILL.md 缺少 YAML frontmatter。"
        case .missingRequiredMetadata:
            "SKILL.md frontmatter 必须包含 name 和 description。"
        case .invalidIdentifier:
            "Skill name 只能包含小写字母、数字和连字符。"
        case .nameDoesNotMatchFolder(let name, let folder):
            "Skill name（\(name)）必须与目录名（\(folder)）一致。"
        case .missingDictationContent:
            "Skill 至少需要 Dictation context 或 Vocabulary 章节。"
        case .tooManyTerms:
            "单个 Skill 最多包含 200 个术语。"
        }
    }
}
