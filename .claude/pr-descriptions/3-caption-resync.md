# feat: reactive caption resync — captions follow the audio under them

**Branch:** `feature/caption-resync` → `main` · 4 commits · 21 files, +1236/−15

## Summary

Captions are a snapshot; the timeline is live. Trim a sentence in half and the caption keeps showing the whole original sentence. This adds a reactive invariant: **a caption's text always equals the words currently audible in its frame range** — maintained automatically on every mutation that changes what audio occupies a frame range (ripple deletes, `remove_words`, inserts, moves, trims, speed), from both the agent tools and UI drags.

## Design

- **Span-scoped, never whole-timeline:** cost scales with the edit. A clip that merely rippled is excluded by a deterministic caption-alignment test (the captions above it moved by the same delta); anything else re-derives.
- **Reconciliation, not regeneration:** per caption clip — no live words → remove; text differs and the clip is untouched → replace (text + karaoke timings); differs but hand-edited → policy (default **preserve** + conflict report with reason); uncovered speech → create, inheriting group style. Hand edits are detected via a new `generatedText` provenance field (dirty ⇔ content ≠ generatedText); unknown-provenance clips are preserved, never clobbered or deleted.
- **Same undo step as the trigger:** resync writes join the mutation's transaction; one ⌘Z reverts both.
- **L1/L2 isolation by type:** the engine's word source protocol has no write surface and reads only cached transcripts — resync can never mutate an asset transcript or trigger ASR.
- **Reporting:** results ride the existing mutation delta (`extra.captionResync`: updated/removed/created/conflicts), so agents see caption effects without re-reading.
- New `resync_captions` tool as the manual/repair escape hatch (group/window scoping, dry-run, per-call conflict policy).
- Also fixes a UI/MCP inconsistency: inspector content edits now clear stale `wordTimings` like `update_text` does.

## Testing

28 unit tests behind an injected word-source: trim/ripple/insert/split semantics, conflict policies, undo atomicity, block-swap determinism (50-run stability), move-onto-occupied, cost confinement (lookup counting), cache-isolation proof, mixed zh/en round-trip. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
