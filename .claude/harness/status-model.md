# feature/local-model-selection — Status (builder-model)

Phase 2 complete. Ready for Evaluator. Full `swift build` + full `swift test` (1326/1326) green.

## Deliverable 1 — larger/higher-precision local variant

| Finding               | Detail                                                                                                                                                                                                               |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sherpa publishes      | ONLY `sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25` (GitHub API, asr-models tag, 486 assets)                                                                                                                           |
| No larger qwen3       | No 1.7B, no fp16/fp32 qwen3 archive exists (`asr-models-qnn*` tags are Qualcomm binaries, not macOS-CPU)                                                                                                             |
| Accurate local option | The already-integrated WhisperKit large-v3 turbo engine (`.whisper`)                                                                                                                                                 |
| Decision              | No speculative archives/variant scaffolding invented (YAGNI). The 3 `LocalSpeechEngine` cases ARE the selectable local models. RAM/disk documented in set_project_settings schema. Not hardware-gated — user choice. |

## Deliverable 2 — per-project transcription model override

| Area           | Change                                                                                                                                                                                                                                                               |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Model          | `ProjectFile.transcriptionLocalModel: LocalSpeechEngine?` (LocalSpeechEngine now Codable; tolerant optional decode); `EditorViewModel.transcriptionLocalModel` + `resolvedLocalEngine` (override ?? .current)                                                        |
| Persist        | load/snapshot in EditorViewModel+Timelines (nil override omitted); set_project_settings hook (checkpoint autosave, same path as transcriptionPreference)                                                                                                             |
| Threading      | Explicit `engine:` param, no global mutation: `TranscriptCache.transcript(…engine:)` → `Transcription.transcribe/transcribeVideoAudio(…engine:)`; cache key from `CacheVariant.local(engine:)` → `engine.cacheTag` (per-variant, cross-variant collision impossible) |
| Read symmetry  | `cachedOnDisk/hasCachedOnDisk(…engine:)` + `readKeys(for:engine:)`; TimelineTranscriptProvider (resync), glossary_apply, inspect_media, get_transcript all pass `editor.resolvedLocalEngine`                                                                         |
| Reported model | resolvedModelLabel/transcriptionMeta gain `localModelId` param → response transcriptionModel reflects the override; set_project_settings response adds `transcriptionLocalModel` + `resolvedLocalModel`                                                              |
| Schema         | set_project_settings `transcriptionLocalModel` enum: qwen3/whisper/apple/default ("default" clears). Descriptions carry per-engine RAM/disk cost.                                                                                                                    |

## Deliverable 3 — lint safety-net acceptance

`nearSoundLintFlagAndApplyComposeUnderModelOverride` (CaptionLintToolTests): captions with 开视频,
stubbed completer suggests 拍视频 → flag surfaces (flag-only default, nothing applied) → update_text
rewrites clip + promotes the widened term (开→拍 widened to 拍视频 by the classifier) — run under a
`.whisper` project override, asserting the override is untouched (features are independent).

## Cache-tag composition note (for merge with fix/punctuated-segmentation)

Per-variant tags read `engine.cacheTag` directly. Qwen3's tag is a single source (`LocalSpeechEngine.qwen3.cacheTag`
= "qw6"). If the sibling bumps qw6→qw7, this code inherits it automatically — no separate variant axis
to compose, so the merge is clean. Engine edits here are additive (Codable conformance only).

## Tests

Added to TranscriptionModelSelectionTests: override resolution, editor apply/snapshot, ProjectFile
round-trip + legacy decode, per-engine cache-key distinctness, read/write cache symmetry under override,
resolvedModelLabel honours override, set_project_settings pin/clear/reject/schema. Engine downloads not
unit-tested (installed-files check stubbed as existing tests do).
