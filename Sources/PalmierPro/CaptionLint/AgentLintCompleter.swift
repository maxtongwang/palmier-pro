// Wraps the app's streaming AgentClient as a one-shot text completer for caption_lint's flags mode.
// Reachability mirrors AgentService.selectClient: a personal API key uses the direct client, a
// signed-in account uses the backend, and neither means the app LLM is unreachable (the tool then
// degrades flags → context). refs feature/caption-lint

import Foundation

/// Drains the agent stream's text deltas into a single completion string (tools disabled).
struct AgentLintCompleter: LintCompleter {
    let client: any AgentClient

    func complete(system: String, user: String) async throws -> String {
        let stream = client.stream(
            system: system,
            tools: [],
            messages: [AnthropicMessage(role: .user, content: [["type": "text", "text": user]])]
        )
        var out = ""
        for try await event in stream {
            switch event {
            case .textDelta(let t): out += t
            case .messageStop: return out
            case .toolUseComplete: break
            }
        }
        return out
    }
}

@MainActor
enum CaptionLintClient {
    /// A reachable completer, or nil when there's no personal key and the user is not signed in —
    /// in which case caption_lint's flags mode degrades to context.
    static func reachable() -> AgentLintCompleter? {
        // Lint is a bounded proofread; Sonnet 5 (low effort) is the cheap default and the only
        // model available without a personal key.
        let model = AnthropicModel.sonnet5
        if let key = AnthropicKeychain.load(), !key.isEmpty {
            return AgentLintCompleter(client: AnthropicClient(apiKey: key, model: model))
        }
        if AccountService.shared.isSignedIn {
            return AgentLintCompleter(client: PalmierClient(model: model))
        }
        return nil
    }
}
