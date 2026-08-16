import Foundation

enum ProfessionalRefinementPolicy {
    /// This count is deliberately binary: one whole-transcript request after
    /// release in Professional mode, and no text-model request in Fast mode or
    /// for an empty ASR result.
    static func invocationCount(mode: RefinementMode, transcript: String) -> Int {
        mode == .professional && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? 1
            : 0
    }
}

struct ProfessionalRefinementBudget: Equatable, Sendable {
    static let maximumInputTokens = 24 * 1_024
    static let maximumOutputTokens = 8 * 1_024

    let outputTokens: Int
    let timeoutSeconds: TimeInterval

    init(rawTokenCount: Int) {
        outputTokens = min(
            Self.maximumOutputTokens,
            max(32, Int(ceil(Double(max(0, rawTokenCount)) * 1.25)) + 32)
        )
        timeoutSeconds = min(45, max(3, 2 + Double(outputTokens) / 20))
    }
}
