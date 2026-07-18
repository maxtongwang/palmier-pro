// Wraps the app's streaming AgentClient as a one-shot text completer for caption_lint's flags mode.
// Reachability mirrors AgentService.canStream: a personal API key uses the direct client, a
// signed-in account WITH credits uses the backend, and anything else means the app LLM is
// unreachable (the tool then degrades flags → context). refs feature/caption-lint

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
    /// A reachable completer, or nil when there's no personal key and the account can't stream (not
    /// signed in, or signed in with no credits) — in which case flags mode degrades to context
    /// rather than wasting a failing round-trip.
    static func reachable() -> AgentLintCompleter? {
        // Lint is a bounded proofread; Sonnet 5 (low effort) is the cheap default and the only
        // model available without a personal key.
        let model = AnthropicModel.sonnet5
        if let key = AnthropicKeychain.load(), !key.isEmpty {
            return AgentLintCompleter(client: AnthropicClient(apiKey: key, model: model))
        }
        let account = AccountService.shared
        if account.isSignedIn, account.hasCredits {
            return AgentLintCompleter(client: PalmierClient(model: model))
        }
        return nil
    }
}
