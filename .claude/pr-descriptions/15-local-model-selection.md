# feat: per-project local transcription model selection

**Branch:** `feature/local-model-selection` · **Depends on:** multilingual-asr, transcription-model

## Summary

The smallest local model (qwen3-asr-0.6B-int8, the only qwen3 archive sherpa publishes — verified across all release assets) makes near-sound Mandarin errors. Model choice was app-global only. This makes the local engine selectable per project, with correct cache semantics.

## What's included

- **`transcriptionLocalModel`** per-project setting (qwen3 | whisper | apple | default), persisted in the project file (tolerant decoding), exposed via `set_project_settings` with RAM/disk costs documented. The resolved engine threads _explicitly_ through `TranscriptCache.transcript(engine:)` → `Transcription.transcribe(engine:)` — no global mutation; the process default applies when no override is set.
- **Per-variant cache slots**: keys derive from the resolved engine's tag, so switching models re-transcribes and cross-variant collisions are impossible. Read/write symmetric across every consumer — resync, glossary apply, inspect/get_transcript, and spoken search/indexing all read the project's slot (no zero-hit search or duplicate transcription under an override).
- **Fallback honesty**: when an engine falls through to Apple Speech, the result is cached under the engine that _actually ran_ — the requested slot stays empty and retryable, so a later successful qwen3 run wins; responses always report the true model. (Known coherent tradeoff: while the requested engine is unavailable, cache-only readers treat those clips as uncached — conservative and self-healing; a sibling-slot read fallback is noted as follow-up.)
- Acceptance test pinning the caption_lint near-sound safety net (开照片→拍照片 flag → apply → glossary promotion) under a model override.

## Testing

Override-resolution matrix, per-variant key distinctness invariant, read/write symmetry probes (search, preflight, resync), fallback slot routing, ProjectFile round-trip/legacy decode. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
