// caption_lint tool — an optional, context-aware proofreading pass over the caption text clips.
// It FLAGS suspected ASR word-substitution errors for review (flag-only by default); auto-apply is
// opt-in via autoApplyThreshold, routed through update_text(origin:"user") so the glossary
// promotion classifier can learn repeated domain terms. refs feature/caption-lint

import Foundation

extension ToolExecutor {
    private static let captionLintAllowedKeys: Set<String> = [
        "startFrame", "endFrame", "clipId", "mode", "autoApplyThreshold",
    ]
    static let captionLintMaxWindows = 200

    func captionLint(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try await captionLint(editor, args, completer: CaptionLintClient.reachable())
    }

    /// Testable core: `completer` is injected so tests can stub the model. nil means the app LLM is
    /// unreachable and flags mode degrades to context.
    func captionLint(_ editor: EditorViewModel, _ args: [String: Any], completer: LintCompleter?) async throws -> ToolResult {
        try validateUnknownKeys(args, allowed: Self.captionLintAllowedKeys, path: "caption_lint")

        let mode: CaptionLinter.Mode
        if let raw = args.string("mode") {
            guard let m = CaptionLinter.Mode(rawValue: raw) else {
                throw ToolError("caption_lint.mode: expected 'flags' or 'context'")
            }
            mode = m
        } else {
            mode = .flags
        }

        let clipFilter = args.string("clipId")
        let windowStart = args.int("startFrame")
        let windowEnd = args.int("endFrame")
        if let s = windowStart, let e = windowEnd, s >= e {
            throw ToolError("caption_lint: startFrame (\(s)) must be less than endFrame (\(e))")
        }

        var threshold: Double?
        if args.keys.contains("autoApplyThreshold") {
            guard let t = args.double("autoApplyThreshold"), t.isFinite, (0...1).contains(t) else {
                throw ToolError("caption_lint.autoApplyThreshold: expected a number between 0 and 1")
            }
            threshold = t
        }

        // Neighbours are computed over the whole group first, so context survives window edges.
        let allWindows = Self.captionWindows(editor)
        if let clipFilter, !allWindows.contains(where: { $0.clipId == clipFilter }) {
            throw ToolError("caption_lint: no caption clip found for clipId \(clipFilter)")
        }
        var windows = allWindows.filter { w in
            if let clipFilter { return w.clipId == clipFilter }
            if let s = windowStart, w.endFrame <= s { return false }
            if let e = windowEnd, w.startFrame >= e { return false }
            return true
        }
        let totalWindows = windows.count
        var nextStartFrame: Int?
        if windows.count > Self.captionLintMaxWindows {
            nextStartFrame = windows[Self.captionLintMaxWindows].startFrame
            windows = Array(windows.prefix(Self.captionLintMaxWindows))
        }

        let exclusions = Self.lintExclusions(editor)
        var payload: [String: Any] = [
            "transcriptionSource": "captions",
            "skippedExclusions": CaptionLinter.maskedCount(windows: windows, exclusions: exclusions),
        ]
        if totalWindows > windows.count, let nextStartFrame {
            payload["nextStartFrame"] = nextStartFrame
            payload["windowsNote"] = "First \(windows.count) of \(totalWindows) caption windows. Continue with startFrame = nextStartFrame."
        }
        if allWindows.isEmpty {
            payload["flags"] = []
            payload["note"] = "No caption clips found. Generate captions with add_captions before linting."
            return .ok(Self.jsonString(payload) ?? "{}")
        }

        func contextResponse(note: String?) -> ToolResult {
            var out = payload
            out["segments"] = CaptionLinter.contextSegments(windows: windows, exclusions: exclusions)
            out["flags"] = []
            if let note { out["note"] = note }
            return .ok(Self.jsonString(out) ?? "{}")
        }

        if mode == .context {
            return contextResponse(note: "context mode: judge each window yourself, then apply corrections with update_text (origin:\"user\"). No model was called.")
        }

        guard let completer else {
            return contextResponse(note: "App LLM unreachable — sign in to Palmier or add an Anthropic API key. Returning context windows for you to judge; no flags were generated.")
        }

        let candidates: [LintCandidate]
        do {
            candidates = try await CaptionLinter.flag(windows: windows, exclusions: exclusions, completer: completer)
        } catch {
            return contextResponse(note: "Lint model call failed (\(error.localizedDescription)). Returning context windows for you to judge.")
        }

        let (toApply, toFlag) = CaptionLinter.partition(candidates, threshold: threshold)
        var applied: [[String: Any]] = []
        var flags = toFlag
        for c in toApply {
            if applyLintCandidate(c, editor: editor) {
                applied.append(Self.candidateRow(c, applied: true))
            } else {
                flags.append(c)  // couldn't apply (text drifted) — surface it instead of dropping it
            }
        }

        payload["flags"] = flags.map { Self.candidateRow($0, applied: false) }
        payload["applied"] = applied
        if threshold == nil, !candidates.isEmpty {
            payload["note"] = "Flag-only: nothing changed. Apply a fix with update_text (origin:\"user\"), or re-run with autoApplyThreshold to auto-apply high-confidence flags."
        }
        return .ok(Self.jsonString(payload) ?? "{}")
    }

    // MARK: - Window + exclusion assembly

    /// Every caption text clip as a lint window, with within-group neighbours for context.
    static func captionWindows(_ editor: EditorViewModel) -> [LintWindow] {
        var byGroup: [String: [Clip]] = [:]
        for track in editor.timeline.tracks {
            for clip in track.clips where clip.mediaType == .text {
                guard let gid = clip.captionGroupId else { continue }
                byGroup[gid, default: []].append(clip)
            }
        }
        var windows: [LintWindow] = []
        for clips in byGroup.values {
            let ordered = clips.sorted { ($0.startFrame, $0.endFrame) < ($1.startFrame, $1.endFrame) }
            for (i, clip) in ordered.enumerated() {
                windows.append(LintWindow(
                    clipId: clip.id,
                    startFrame: clip.startFrame,
                    endFrame: clip.endFrame,
                    text: clip.textContent ?? "",
                    prevText: i > 0 ? ordered[i - 1].textContent : nil,
                    nextText: i + 1 < ordered.count ? ordered[i + 1].textContent : nil
                ))
            }
        }
        return windows.sorted { ($0.startFrame, $0.endFrame) < ($1.startFrame, $1.endFrame) }
    }

    /// Terms that glossary and caption-style already own — masked out of lint candidacy.
    static func lintExclusions(_ editor: EditorViewModel) -> LintExclusions {
        var terms: [String] = []
        for merged in GlossaryStore.load(projectURL: editor.projectURL).merged() {
            terms.append(merged.term.canonical)
            terms.append(contentsOf: merged.term.variants)
        }
        let profile = CaptionStyleStore.resolve(projectPackageURL: editor.projectURL).profile
        terms.append(contentsOf: profile.fillers.removeAlways)
        terms.append(contentsOf: profile.fillers.caseByCase)
        terms.append(contentsOf: profile.fillers.neverRemove)
        terms.append(contentsOf: profile.protectedPhrases)
        return LintExclusions(terms: terms)
    }

    // MARK: - Apply (opt-in)

    /// Apply one candidate by rewriting its clip through the update_text(origin:"user") path, so the
    /// glossary auto-promotion classifier sees the edit. Returns false if the clip or word drifted.
    private func applyLintCandidate(_ c: LintCandidate, editor: EditorViewModel) -> Bool {
        guard let loc = editor.findClip(id: c.clipId) else { return false }
        let clip = editor.timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
        guard let current = clip.textContent, let range = current.range(of: c.original) else { return false }
        let newContent = current.replacingCharacters(in: range, with: c.suggestion)
        guard newContent != current else { return false }
        let result = try? updateText(editor, ["clipIds": [c.clipId], "content": newContent, "origin": "user"])
        return result?.isError == false
    }

    private static func candidateRow(_ c: LintCandidate, applied: Bool) -> [String: Any] {
        var row: [String: Any] = [
            "clipId": c.clipId,
            "frameRange": [c.startFrame, c.endFrame],
            "original": c.original,
            "suggestion": c.suggestion,
            "reason": c.reason,
            "confidence": c.confidence,
        ]
        if applied { row["applied"] = true }
        return row
    }
}
