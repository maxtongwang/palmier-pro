# feat: reusable caption-style profile — measured filler policy + typography defaults

**Branch:** `feature/caption-style` → `main` · 4 commits · 11 files, +829/−6

## Summary

Filler distributions are corpus-specific: on real zh/en footage, English hesitation fillers totaled 5 tokens in 7601 words — the actual filler load was CJK particles and "like". A generic "strip um/uh" pass is a no-op, and worse, naive dedup rules destroy Chinese grammar (存存钱, 试试看 are reduplication, not stutters) and comic timing (太酷了×3). This adds a layered, portable style profile that records measured policy — including where judgment is required instead of pretending to automate it.

## Design

- **Profile JSON**, layered later-wins: `~/.config/caption-style/global.json` → library → `<project>.palmier/caption-style.json`. Tolerant decoding; malformed/missing → defaults + warning, never a crash.
- **Filler policy:** `removeAlways` (safe to strip), `neverRemove`, and `caseByCase` — tokens that must NEVER be auto-removed (啊 is usually a sentence-final particle, only sometimes filler); tools surface them for per-occurrence judgment. `neverDedupe` guards CJK reduplication and comic repetition. `protectedPhrases` are untouchable by any pass.
- **Typography defaults** (font, size, color, outline, shadow, position, maxWords) fill in when `add_captions` is called without explicit params; explicit params always win.
- `add_captions` gains `fillerPolicy: off | removeAlways` (default off) — display-text only, never cuts audio.
- New read-only `caption_style` tool returns the resolved profile + provenance + per-layer origin, so agents honor project policy before captioning.

## Testing

16 unit tests: policy classification, phrase protection through filler AND dedup passes, reduplication guards, layering precedence, malformed tolerance, verbatim pass-through of non-filler content, profile-vs-explicit precedence. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
