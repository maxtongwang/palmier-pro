# feat: caption tool-surface ergonomics — safety, batching, discoverability

**Branch:** `feature/tool-ergonomics` · **Depends on:** caption-resync, glossary, caption-style, caption-lint

## Summary

Workflow-audit fixes for the traps and friction an agent hits driving the caption pipeline at scale (1000+ captions).

## What's included

- **`add_texts` overwrite safety**: the schema now states that placement clears the target region (previously undocumented silent loss); new `onOverlap: "clear" | "fail"` — fail validates every entry against existing clips _and against the call's other entries_ per target track before any mutation, erroring atomically with the colliding ids.
- **Batch content apply**: `update_text` gains `entries: [{clipId, content}]` — a whole lint pass in one call, one undo step, per-entry retiming and glossary promotion.
- **Promotion visibility**: the `update_text` description states that caption edits may auto-promote; responses name the reason when a caption edit did _not_ promote (single reasoned note, no spam); the `undo` description notes glossary writes are not reverted (via a `classifyWithReason` wrapper — later unified with `classify` into a single implementation so they cannot drift).
- **Onboarding**: the agent-instructions text now describes the caption pipeline (style → captions → lint → fixes/promotion → automatic resync) so a cold agent can discover it from the session start.
- **Punctuation-run segmentation fix**: a run like 「。。。」 no longer explodes into per-mark lines or collapses the segment's acoustic word timing.
- **`resolved` echo on add_captions**: reports the segmentation/maxWords/fillerPolicy/typography source actually used.

## Testing

Overlap matrices (existing-clip, intra-call, new-track), batch entries with per-entry promotion + undo atomicity, reason-note coverage, punctuation-run timing preservation. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
