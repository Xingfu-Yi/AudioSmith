import Foundation

enum RefinementValidator {
    static func accepts(
        candidate: String,
        original: String,
        skill _: DomainSkill = .general
    ) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !original.isEmpty else { return false }

        let forbidden = [
            "<think>", "</think>", "<|", "<asr_text>", "<raw_transcript>",
            "<dictation_context>",
            "assistant:", "system:", "user:", "助手：", "系统：", "用户：",
        ]
        let lower = candidate.lowercased()
        guard forbidden.allSatisfy({ !lower.contains($0) }) else { return false }

        guard captures(#"\d+(?:[.,]\d+)*"#, in: candidate) == captures(#"\d+(?:[.,]\d+)*"#, in: original),
              captures(#"https?://[^\s<>]+"#, in: candidate) == captures(#"https?://[^\s<>]+"#, in: original),
              captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: candidate, caseInsensitive: true)
                == captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: original, caseInsensitive: true)
        else { return false }

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
