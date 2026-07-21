# feat: caption_lint — context-aware ASR-error review stage (flags, never silent fixes)

**Branch:** `feature/caption-lint` · own diff: ~6 files · **Depends on:** feature/glossary, feature/caption-style

## Summary

No pipeline stage owns plain ASR word errors: fillers have a policy, known proper nouns have the glossary, but a near-sound mistake like 好久没有**开**视频了 (said: **拍**视频了) passes straight into the shipped captions until a human notices. This adds an optional lint pass that flags suspected word-substitution errors with context — flag, don't silently apply, the same judgment principle as `caseByCase` fillers.

## What's included

- New `caption_lint` tool over caption text clips (frame-referenced, so fixes route through `update_text`):
  - **`mode: "flags"`** — runs windows (with neighbor-sentence context) through the app's agent LLM; returns `{clipId, frameRange, original, suggestion, reason, confidence}` candidates. Prompted for word-substitution errors only — never rephrasing or grammar.
  - **`mode: "context"`** — no LLM call: returns the same prepared windows (text, neighbors, exclusions) for the _calling_ agent to judge. Also the automatic degradation when the app LLM is unreachable (unauthenticated / no credits) — the tool never hard-fails.
  - **`autoApplyThreshold`** (absent by default = flag-only): when set, high-confidence fixes apply via `update_text(origin:"user")`, which feeds the existing glossary auto-promotion — a repeated domain term becomes a persistent correction automatically.
- **Exclusions:** glossary terms (all confidences) and caption-style filler/protected tokens are masked from candidacy — those stages own them. Masking is diff-based: only the _changed_ tokens are tested against exclusions, so a protected noun inside a flagged span doesn't suppress a genuine adjacent fix (e.g. glossary 视频 doesn't block 开视频→拍视频).
- Deterministic paging via a clipId cursor (safe under overlapping captions); LLM behind a protocol seam — tests inject responses, no network.

## Testing

18 tests: the headline 开/拍 case end-to-end, exclusion matrix (fillers/glossary/protected + the diff-masking edge cases), flag-only immutability, context-mode zero-LLM proof, auto-apply threshold behavior, paging disjointness. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
