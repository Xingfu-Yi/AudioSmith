import Foundation

enum RefinementValidator {
    static func accepts(
        candidate: String,
        original: String,
        skill: DomainSkill = .general
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

        let originalCount = original.count
        let candidateCount = candidate.count
        if originalCount <= 20 {
            guard abs(candidateCount - originalCount) <= 8 else { return false }
        } else {
            let ratio = Double(candidateCount) / Double(max(1, originalCount))
            guard (0.65...1.35).contains(ratio) else { return false }
        }

        // A pronunciation correction can look like a large character edit
        // even though it is exactly what the selected Skill requested (for
        // example, “千维 Image Editor” -> “Qwen-Image-Edit”). Canonicalize
        // only for the distance calculation; the candidate itself still has
        // to pass every length, protocol, number, URL and email safeguard.
        let normalizedOriginal = normalize(original, skill: skill)
        let normalizedCandidate = normalize(candidate, skill: skill)
        let distance = normalizedEditDistance(normalizedOriginal, normalizedCandidate)
        let maximumLength = max(normalizedOriginal.count, normalizedCandidate.count)
        let ratio = maximumLength > 0 ? Double(distance) / Double(maximumLength) : 0
        guard ratio <= (originalCount <= 20 ? 0.50 : 0.35) else { return false }

        guard captures(#"\d+(?:[.,]\d+)*"#, in: candidate) == captures(#"\d+(?:[.,]\d+)*"#, in: original),
              captures(#"https?://[^\s<>]+"#, in: candidate) == captures(#"https?://[^\s<>]+"#, in: original),
              captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: candidate, caseInsensitive: true)
                == captures(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: original, caseInsensitive: true)
        else { return false }

        return true
    }

    private static func normalize(_ text: String, skill: DomainSkill) -> [Character] {
        var canonicalized = text
        let hints = skill.terms
            .flatMap { term in term.spokenForms.map { ($0, term.preferred) } }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0.count > $1.0.count }
        for (spokenForm, canonical) in hints {
            canonicalized = replaceKnownForm(
                spokenForm,
                in: canonicalized,
                with: canonical
            )
        }

        return Array(canonicalized
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation })
    }

    private static func replaceKnownForm(
        _ spokenForm: String,
        in input: String,
        with canonical: String
    ) -> String {
        if spokenForm.unicodeScalars.contains(where: { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value)
        }) {
            return input.replacingOccurrences(
                of: spokenForm,
                with: canonical,
                options: [.caseInsensitive]
            )
        }

        let escaped = NSRegularExpression.escapedPattern(for: spokenForm)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: canonical)
        )
    }

    private static func normalizedEditDistance(_ left: [Character], _ right: [Character]) -> Int {
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        let short: [Character]
        let long: [Character]
        if left.count <= right.count {
            short = left
            long = right
        } else {
            short = right
            long = left
        }

        var previous = Array(0...short.count)
        for (longIndex, longCharacter) in long.enumerated() {
            var current = Array(repeating: 0, count: short.count + 1)
            current[0] = longIndex + 1
            for (shortIndex, shortCharacter) in short.enumerated() {
                current[shortIndex + 1] = min(
                    current[shortIndex] + 1,
                    previous[shortIndex + 1] + 1,
                    previous[shortIndex] + (longCharacter == shortCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[short.count]
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
