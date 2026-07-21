# feat: transcript correction glossary — additive L1 layer, dual-layer search, auto-promotion

**Branch:** `feature/glossary` → `main` · 4 commits · 24 files, +1538/−22

## Summary

ASR reliably mis-hears proper nouns (shop names, places, dishes), and today a correction made in a caption never flows back: the transcript, search index, and every future project repeat the same mistake. This adds an additive correction layer over raw ASR output: corrections are stored as portable JSON glossary terms and applied at read time — the stored transcript is never mutated, so corrections survive engine swaps and re-transcription.

## Design

```
materialised = apply(glossary, raw_asr)   // at every read; raw stays raw
```

- **Layered store**, later wins: `~/.config/glossary/global.json` → library → `<project>.palmier/glossary.json`. Plain JSON; any tool can read/write it.
- **Term model:** canonical, variants (the mis-hearings), lang/type hints, provenance (`frame:<ref>@<sec>` / user / auto), confidence. `verified`/`declared`/`asserted` auto-apply; `inferred` is suggestion-only, never applied.
- **Materialisation** at all four read paths: `get_transcript`, `inspect_media`, `add_captions`, spoken search.
- **Dual-layer spoken search:** a query hits the raw OR the corrected text — editors often remember the wrong spelling because they read it in a transcript. Corrected hits rank above raw-only. No index, no migration.
- **Variant safety:** boundary matching (never substrings), longest-match-first, short variants rejected at write AND at read (hand-authored files are a supported path), collision warnings.
- **Auto-promotion:** a caption edit that is a single contiguous substitution of a rare term (e.g. 陈娘娘 → 陈嬢嬢) is silently recorded as an `asserted` glossary term — no confirmation prompts; promotions ride in the tool response and are reviewable via `glossary_list({confidence:"asserted"})`. Pure deletions, insertions, scattered edits, and common-word rephrases are never promoted. Phonetic distance is deliberately NOT a gate (ASR errors are frequently non-homophonic).
- **Decoder-bias API** (`hotwordTerms()`, `biasFingerprint()`, cache-key salting) ships here; engine wiring is intentionally left to integrators since engines vary.

## New tools

`glossary_list`, `glossary_add`, `glossary_remove`, `glossary_apply` (dry-run diff preview).

## Testing

33 unit tests: materialisation, layering, boundary safety (师→狮 cannot corrupt 老师, proven through the real store read path), classifier truth table, dual-layer search, re-index survival, malformed-file tolerance. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
