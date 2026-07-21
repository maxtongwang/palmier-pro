# feat: caption settings & glossary in the editor UI

**Branch:** `feature/caption-ui-settings` · **Depends on:** caption-segmentation, caption-style, glossary-persistence, local-model-selection

## Summary

Caption behavior added over the last cycles (segmentation, animation granularity, per-project model routing, the glossary) was driveable only through agent tools; the profile silently filled defaults the UI never showed, and the Mode radio was disconnected from the persisted transcription preference.

## What's included

- **CaptionTab controls**: "Line breaks" (Natural / Fixed) and "Animate by" (Word / Character, shown when a preset is active) rows; profile-sourced values annotated "(profile)" so silently-driven defaults become visible; profile-aware Max words. A pure resolver mirrors the tool-side precedence exactly, so UI and MCP cannot disagree.
- **Per-project model routing**: a "Model" row (Default / Qwen3 / Whisper / Apple with size details) writing the per-project override; the Mode radio reconciled with `transcriptionPreference` — one persisted control initialized from the project (display-only auto resolution, persists only on a deliberate pick), so manual Generate and agent captioning always agree. Settings > Storage gains an honesty caption when open projects override the global engine.
- **Glossary review list**: merged terms with variants, scope, and confidence; delete/promote through the same shared VM helpers the MCP tools now delegate to (single implementation); inline add with sanitization warnings surfaced in amber (dropped variants are never silent); promote-upward gate matches `glossary_promote` semantics; load-on-expand with a refresh affordance. The "Fix names & jargon" agent handoff remains an agent-menu action.

## Testing

Resolver precedence matrix, reconciler mapping, helper/tool parity (add sanitizes + warns, remove triggers §5.2, promote moves scope), persistence round-trips. Full suite green.

## Also included

- **Animate-by row is always visible** under the Animation section (dimmed when the preset has no granularity), instead of appearing and disappearing — discoverability over modality.
- **Model menu never shows a phantom "Default" choice**: it lists the concrete engines and annotates the inherited one with "— Default", so the effective model is always explicit.
- **One-click Confirm on inferred glossary suggestions**: the glossary review list upgrades an inferred term to declared (provenance "user") in place, with an amber chip marking suggestion-only entries.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
