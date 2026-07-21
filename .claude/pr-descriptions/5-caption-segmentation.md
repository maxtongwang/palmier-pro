# fix: natural caption segmentation (CJK-aware) + caption-group joining for custom text

**Branch:** `fix/caption-segmentation` · own diff: ~6 files · **Depends on:** caption-resync, caption-style

## Summary

Two production bugs from a 1000+-caption zh/en project:

1. Caption chunking treated each CJK character as a "word", so `maxWords` sliced lines every ~5 characters — mid-word, mid-name, across sentence ends (`「现在人在重」「庆西站在等」` splits 城南西站 down the middle).
2. Text created with `add_texts` on a caption track was orphaned — no `captionGroupId` — so group restyling and resync never covered rebuilt lines.

## What's included

- **`segmentation: "natural"` (new default)** for `add_captions`, `resync_captions`, and the reactive resync path: hard breaks at sentence/clause punctuation (binding left — a line never starts with 。，？！), then only at NLTokenizer word boundaries; never inside a token; one semantic unit per line, preferring shorter lines; `maxWords` means characters/line for CJK, words for Latin. `"fixedChars"` preserves the legacy split (pinned by a byte-exact regression test).
- Known limitation, documented and test-pinned: a multi-token proper noun (城南|西站) can split at the token seam under very tight width caps — preventing that needs NER, out of scope. Mid-character splits are impossible.
- **`add_texts` joins the track's caption group** when the track's text clips all share one; explicit `captionGroupId` param to force a group, `"none"` to opt out.
- **Provenance-safe deletion:** since custom text can now join groups, the resync engine's empty-span removal is gated symmetrically with replacement — only provably-generated, unedited clips auto-remove; custom or hand-edited captions over silence are preserved with a reasoned conflict entry (policy-controllable).

## Testing

15 new tests including the exact production regressions (break at 。; 城南西站 whole at normal widths; token-seam pin at tight caps), group-joining matrix, and the silence-preservation policy matrix. Full suite green.

## Also included

- **No decoder biasing — glossary corrections are read-time only.** An earlier iteration fed glossary terms into the qwen3 decoder as hotwords; prompt-conditioning the 0.6B model measurably perturbed recognition of unrelated audio (verified on identical audio with/without hotwords). This PR ships with recognition as a pure function of audio + model: no hotword injection, no bias-salted cache keys. Corrections apply when transcripts are read, never at decode.
- **Hermetic glossary tests**: a `@TaskLocal` root override pins the library/global glossary scopes to an isolated directory so the suite never reads a developer's real `~/Documents` glossary.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
