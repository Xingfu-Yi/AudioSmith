import Foundation

enum RefinementValidationFailure: String, Equatable {
    case empty = "候选或原文为空"
    case protocolText = "候选包含模型协议文本"
    case changedNumber = "原文中的数字未被保留"
    case changedURL = "原文中的 URL 被改变"
    case changedEmail = "原文中的邮箱被改变"
}

enum RefinementValidator {
    static func accepts(
        candidate: String,
        original: String,
        skill _: DomainSkill = .general
    ) -> Bool {
        rejectionFailure(candidate: candidate, original: original) == nil
    }

    static func rejectionFailure(
        candidate: String,
        original: String
    ) -> RefinementValidationFailure? {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !original.isEmpty else { return .empty }

        let forbidden = [
            "<think>", "</think>", "<|", "<asr_text>", "<raw_transcript>",
            "<dictation_context>",
            "assistant:", "system:", "user:", "助手：", "系统：", "用户：",
        ]
        let lower = candidate.lowercased()
        guard forbidden.allSatisfy({ !lower.contains($0) }) else { return .protocolText }

        // Protect numbers the speaker actually dictated, but allow a selected
        // Skill to introduce digits as part of a canonical spelling such as
        // `千问三` -> `Qwen3`. Exact array equality incorrectly rejected those
        // useful terminology corrections and forced an ASR fallback.
        let originalNumbers = captures(#"\d+(?:[.,]\d+)*"#, in: original)
        let candidateNumbers = captures(#"\d+(?:[.,]\d+)*"#, in: candidate)
        guard preserves(originalNumbers, in: candidateNumbers) else { return .changedNumber }

        guard captures(#"https?://[^\s<>]+"#, in: candidate)
            == captures(#"https?://[^\s<>]+"#, in: original) else { return .changedURL }
        guard captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: candidate, caseInsensitive: true)
            == captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: original, caseInsensitive: true)
        else { return .changedEmail }

        return nil
    }

    private static func preserves(_ protected: [String], in candidate: [String]) -> Bool {
        var candidateIndex = candidate.startIndex
        for value in protected {
            guard let match = candidate[candidateIndex...].firstIndex(of: value) else { return false }
            candidateIndex = candidate.index(after: match)
        }
        return true
    }

    private static func captures(
        _ pattern: String,
        in text: String,
        caseInsensitive: Bool = false
    ) -> [String] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
