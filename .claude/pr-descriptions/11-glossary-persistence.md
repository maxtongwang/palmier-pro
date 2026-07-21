# feat: glossary persistence across projects + classifier/corrector hardening

**Branch:** `feature/glossary-persistence` · **Depends on:** glossary, caption-resync

## Summary

Corrections learned in one project were invisible to the next: auto-promotions sank to project scope, project duplication dropped the glossary file, and the highest-frequency real error class (common-verb near-sound substitutions like 开照片→拍照片) never auto-promoted at all.

## What's included

- **Promotions land in library scope** — a caption-edit correction is speaker/domain knowledge, not project state. Project duplication now preserves `glossary.json`. New `glossary_promote` tool moves terms between scopes (single or all, confidence-filtered); `glossary_list` nudges when project-scope asserted terms could be promoted.
- **Span widening**: a sub-threshold single-character CJK correction widens to the enclosing token (开→拍 becomes 开照片→拍照片, safe to find/replace) instead of being dropped — with the rephrase/filler guards re-applied to the widened span so all-common-vocabulary homophone edits (在来→再来) can never promote into corruption-capable library terms.
- **Corrector hardening**: mixed-script variants enforce Latin word boundaries on their Latin edges ("AI技术" can't corrupt "OpenAI技术"); whitespace-only variants rejected; equal-length variant ties resolve deterministically.
- **Hermetic tests**: library/global scope directories are `@TaskLocal`-injectable; a test-scoping trait isolates every glossary-touching suite from the real user files.

## Testing

Scope/promotion matrix, duplication preservation, widening truth table (promotes: 开照片→拍照片, 师父→狮父; rejects: 在来→再来, 他说→她说, 的/地/了 grammar edits), mixed-script boundary cases, determinism. Full suite green, `$HOME` verified untouched.

## Also included

- Tool-executor suites run against an isolated glossary root (`.isolatedGlossaryRoot`), so tests can never read or write a developer's real library glossary.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
