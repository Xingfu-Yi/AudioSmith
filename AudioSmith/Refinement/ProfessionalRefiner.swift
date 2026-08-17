import Foundation
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon
import Tokenizers

struct RefinementRequest: Sendable {
    let transcript: String
}

enum ProfessionalRefinerError: LocalizedError {
    case notLoaded
    case inputTooLong
    case timeout
    case rejectedCandidate(RefinementValidationFailure)

    var errorDescription: String? {
        switch self {
        case .notLoaded: "专业精修模型尚未加载。"
        case .inputTooLong: "听写文本超过专业精修的 24K token 输入上限。"
        case .timeout: "专业精修超时。"
        case .rejectedCandidate(let failure): "专业精修结果未通过校验：\(failure.rawValue)。"
        }
    }
}

actor ProfessionalRefiner {
    private var model: ModelContainer?
    private var generationCount = 0

    var isLoaded: Bool { model != nil }
    var completedGenerationCount: Int { generationCount }

    func load(from directory: URL) async throws {
        guard model == nil else { return }
        model = try await loadModelContainer(
            from: directory,
            using: LocalTokenizerLoader()
        )
    }

    func prewarm() async {
        guard let model else { return }
        let session = ChatSession(
            model,
            instructions: RefinementPrompt.systemInstructions,
            generateParameters: .init(maxTokens: 1, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        _ = try? await session.respond(to: "Transcript: 测试")
        Memory.clearCache()
    }

    func unload() {
        model = nil
        Memory.clearCache()
    }

    func refine(_ request: RefinementRequest) async throws -> String {
        guard let model else { throw ProfessionalRefinerError.notLoaded }
        let raw = request.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        let tokenizer = await model.tokenizer
        let rawTokenCount = tokenizer.encode(text: raw, addSpecialTokens: false).count
        let prompt = try makePrompt(
            transcript: raw,
            tokenizer: tokenizer
        )
        let budget = ProfessionalRefinementBudget(rawTokenCount: rawTokenCount)
        let session = ChatSession(
            model,
            instructions: RefinementPrompt.systemInstructions,
            generateParameters: .init(
                maxTokens: budget.outputTokens,
                temperature: 0,
                topP: 1,
                repetitionPenalty: 1
            ),
            additionalContext: ["enable_thinking": false]
        )

        generationCount += 1
        let generated = try await generate(
            session: session,
            prompt: prompt,
            timeout: budget.timeoutSeconds
        )
        let candidate = RefinementOutputSanitizer.sanitize(generated)
        Memory.clearCache()

        if let failure = RefinementValidator.rejectionFailure(
            candidate: candidate,
            original: raw
        ) {
            throw ProfessionalRefinerError.rejectedCandidate(failure)
        }
        return candidate
    }

    private func makePrompt(
        transcript: String,
        tokenizer: any MLXLMCommon.Tokenizer
    ) throws -> String {
        let prompt = RefinementPrompt.userPrompt(transcript: transcript)
        let tokenCount = tokenizer.encode(
            text: RefinementPrompt.systemInstructions + prompt,
            addSpecialTokens: false
        ).count
        guard tokenCount <= ProfessionalRefinementBudget.maximumInputTokens else {
            throw ProfessionalRefinerError.inputTooLong
        }
        return prompt
    }

    private func generate(
        session: ChatSession,
        prompt: String,
        timeout: TimeInterval
    ) async throws -> String {
        let gate = RefinementResultGate<String>()
        let sessionBox = RefinementUncheckedSendable(session)
        let generation = Task.detached(priority: .userInitiated) {
            do {
                var output = ""
                for try await chunk in sessionBox.value.streamResponse(to: prompt) {
                    try Task.checkCancellation()
                    output += chunk
                }
                gate.resolve(.success(output))
            } catch {
                gate.resolve(.failure(error))
            }
        }
        let timeoutTask = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            generation.cancel()
            gate.resolve(.failure(ProfessionalRefinerError.timeout))
        }
        defer { timeoutTask.cancel() }

        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
            }
        } onCancel: {
            generation.cancel()
            timeoutTask.cancel()
            gate.resolve(.failure(CancellationError()))
        }
        return result
    }

}

enum RefinementPrompt {
    static let systemInstructions = "在忠实原意的基础上润色听写文本，只输出润色后的完整文本。"

    static func userPrompt(transcript: String) -> String {
        "听写文本：\n\(transcript)"
    }
}

enum QwenThinkingCompatibility {
    static let noThinkingPrefix = "<think>\n\n</think>\n\n"

    static func shouldInjectNoThinkingPrefix(
        templateSupportsThinkingControl: Bool,
        additionalContext: [String: any Sendable]?
    ) -> Bool {
        guard !templateSupportsThinkingControl else { return false }
        return additionalContext?["enable_thinking"] as? Bool == false
    }
}

enum RefinementOutputSanitizer {
    static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Some Qwen chat templates may still emit a thinking wrapper even
        // when thinking is disabled. Keep only the answer after it.
        if let closingThink = text.range(of: "</think>", options: .caseInsensitive) {
            text = String(text[closingThink.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        text = text.replacingOccurrences(
            of: #"<\|[^>]+\|>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)</?think>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(
            of: #"(?i)^(?:assistant(?:\s*[:：]|\s*\n)|output\s*[:：]\s*|(?:润色后的(?:完整)?文本|润色结果|修订结果)\s*[:：]\s*)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(
                of: #"^```[^\n]*\n?"#,
                with: "",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: #"\n?```$"#,
                with: "",
                options: .regularExpression
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RefinementUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        let supportsThinkingControl = Self.templateSupportsThinkingControl(in: directory)
        return LocalTokenizerBridge(
            upstream,
            templateSupportsThinkingControl: supportsThinkingControl
        )
    }

    private static func templateSupportsThinkingControl(in directory: URL) -> Bool {
        let url = directory.appendingPathComponent("tokenizer_config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let template = object["chat_template"] as? String else {
            // This loader is pinned to Qwen3. Treat a missing flag as the
            // legacy template that needs the explicit no-thinking prefix.
            return false
        }
        return template.contains("enable_thinking")
    }
}

private struct LocalTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer
    private let templateSupportsThinkingControl: Bool

    init(
        _ upstream: any Tokenizers.Tokenizer,
        templateSupportsThinkingControl: Bool
    ) {
        self.upstream = upstream
        self.templateSupportsThinkingControl = templateSupportsThinkingControl
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            var tokens = try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
            if QwenThinkingCompatibility.shouldInjectNoThinkingPrefix(
                templateSupportsThinkingControl: templateSupportsThinkingControl,
                additionalContext: additionalContext
            ) {
                tokens += upstream.encode(
                    text: QwenThinkingCompatibility.noThinkingPrefix,
                    addSpecialTokens: false
                )
            }
            return tokens
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private final class RefinementResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var resolvedResult: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let immediate: Result<Value, Error>? = lock.withLock {
            if let result = resolvedResult { return result }
            self.continuation = continuation
            return nil
        }
        if let immediate { continuation.resume(with: immediate) }
    }

    func resolve(_ result: Result<Value, Error>) {
        let continuation: CheckedContinuation<Value, Error>? = lock.withLock {
            guard resolvedResult == nil else { return nil }
            resolvedResult = result
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
