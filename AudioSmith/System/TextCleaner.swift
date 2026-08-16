import Foundation

enum TextCleaner {
    static func stripModelProtocol(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Control tokens can precede the Qwen assistant protocol. Remove them
        // before deciding whether `language ...` is an incomplete prefix;
        // otherwise `<|im_start|>language` becomes a visible `language` only
        // after the old prefix check has already run.
        text = replacing(#"<\|[^>]+\|>"#, in: text, with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = replacing(
            #"(?is)^assistant\s+(?=language(?:\s|$))"#,
            in: text,
            with: ""
        )

        // Qwen3-ASR auto-language decoding may expose its assistant protocol
        // prefix token-by-token before the transcript begins. Hide an incomplete
        // prefix and remove complete prefixes at every encoder-window boundary.
        let lowercased = text.lowercased()
        if ("language".hasPrefix(lowercased) || lowercased.hasPrefix("language")),
           !text.contains("<asr_text>") {
            return ""
        }
        text = replacing(
            #"(?i)language\s+[^<\n]{0,48}\s*<asr_text>"#,
            in: text,
            with: ""
        )
        text = text.replacingOccurrences(of: "<asr_text>", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clean(_ input: String, replacements: [String: String] = [:]) -> String {
        var text = stripModelProtocol(input)
        text = replacing(#"[\t\n\r ]+"#, in: text, with: " ")
        text = replacing(#"\s+([，。！？；：、,.!?;:])"#, in: text, with: "$1")
        text = replacing(#"([，。！？；：、])\s+"#, in: text, with: "$1")
        text = replacing(#"([（【“‘])\s+"#, in: text, with: "$1")
        text = replacing(#"\s+([）】”’])"#, in: text, with: "$1")
        text = replacing(#"([\p{Han}])\s+([\p{Han}])"#, in: text, with: "$1$2")
        text = collapseRepeatedSentences(text)
        text = collapsePrefixRepeatedSentences(text)

        for (source, target) in replacements.sorted(by: { $0.key.count > $1.key.count }) {
            text = replacingAlias(source, in: text, with: target)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// English aliases are matched as complete words so a short pronunciation
    /// hint such as `repo` cannot corrupt an already-correct `repository`.
    /// Han aliases intentionally remain substring matches because written
    /// Chinese normally has no whitespace-delimited word boundaries.
    private static func replacingAlias(_ source: String, in input: String, with target: String) -> String {
        guard !source.isEmpty else { return input }
        if source.unicodeScalars.contains(where: { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }) {
            return input.replacingOccurrences(of: source, with: target, options: [.caseInsensitive])
        }

        let escapedSource = NSRegularExpression.escapedPattern(for: source)
        let escapedTarget = NSRegularExpression.escapedTemplate(for: target)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escapedSource + #"(?![\p{L}\p{N}_])"#
        return replacing(pattern, in: input, with: escapedTarget)
    }

    private static func collapseRepeatedSentences(_ input: String) -> String {
        replacing(#"(.{4,120}?[。！？!?])(?:\s*\1)+"#, in: input, with: "$1")
    }

    /// Rolling ASR can emit an incomplete sentence immediately before a
    /// longer hypothesis of that same sentence. Remove only adjacent cases
    /// where the normalized earlier sentence is an exact prefix of the next
    /// one; ordinary paraphrases and non-adjacent repetition remain intact.
    private static func collapsePrefixRepeatedSentences(_ input: String) -> String {
        var segments: [String] = []
        var current = ""
        for character in input {
            current.append(character)
            if "。！？!?".contains(character) {
                segments.append(current)
                current = ""
            }
        }
        if !current.isEmpty { segments.append(current) }

        var collapsed: [String] = []
        for segment in segments {
            if let previous = collapsed.last {
                let previousKey = comparisonKey(previous)
                let currentKey = comparisonKey(segment)
                if previousKey.count >= 8,
                   currentKey.count > previousKey.count,
                   currentKey.hasPrefix(previousKey),
                   hasDanglingConnector(previousKey) {
                    collapsed.removeLast()
                }
            }
            collapsed.append(segment)
        }
        return collapsed.joined()
    }

    private static func comparisonKey(_ input: String) -> String {
        input.precomposedStringWithCanonicalMapping
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func hasDanglingConnector(_ key: String) -> Bool {
        ["以及", "and", "or", "和", "与", "及", "或", "跟"].contains {
            key.hasSuffix($0)
        }
    }

    private static func replacing(_ pattern: String, in input: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
