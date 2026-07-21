# feat: caption-style write path + lint dismissal memory

**Branch:** `feature/style-lint-persistence` · **Depends on:** caption-style, caption-lint

## Summary

The caption-style profile was read-only — the "reusable profile" had nothing to reuse unless a human hand-authored JSON — and rejected lint flags were forgotten, re-surfacing every run and every episode.

## What's included

- **`set_caption_style` tool**: writes a partial profile to a chosen scope (global/library/project; default library) via read-modify-write — provided keys replace that layer, absent keys and hand-authored unknown keys survive. Validated ranges, actionable errors. Measured project policy (typography, fillers, protected phrases) is now capturable for reuse.
- **Segmentation preference**: `typography.segmentation` in the profile is honored by `add_captions`, `resync_captions`, _and_ the reactive auto-resync path when no explicit param is passed; explicit always wins.
- **Lint dismissal memory**: `caption_lint {action:"dismiss", original}` records confirmed-correct surface forms at library scope; subsequent lint runs suppress them with the same diff-based masking as protected phrases (a dismissed term in unchanged context never suppresses an adjacent genuine flag). Short/common dismissals warn. The accept path already learned via glossary promotion — now the reject path learns too.
- **Cloud bias investigated**: the cloud transcription protocol exposes no vocabulary field; documented at the request site rather than half-built.
- **Hermetic tests**: `@TaskLocal` directory overrides on the style store + a scoping trait across style/lint suites.

## Testing

Layer-merge/survival probes, validation matrix, profile-vs-explicit precedence on all three resync paths, dismissal suppression + non-suppression, `$HOME` cleanliness. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
