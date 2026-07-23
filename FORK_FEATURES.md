# Fork Feature Manifest

Every fork change sliced by feature. Delta vs upstream (`origin/main` merge-base): **140 files, +14,070/−275** — 63 new files (feature-owned) + 50 modified upstream files (hook points) + tests/docs/scripts.

Use this manifest to: triage upstream-merge conflicts (find the owning feature fast), scope a future upstream _issue_ to one slice, and keep new work modular. Full design docs per feature live in `.claude/pr-descriptions/` (historical PR series).

## 1. On-device multilingual ASR

zh/en code-switched transcription: Qwen3-ASR 0.6B (authoritative text) + WhisperKit (timing anchor), engine routing with Apple fallback, identity-keyed transcript cache with per-engine slots, code-switch seam guard (interleave detection, fine sub-chunk re-decode, codeSwitchSpans flagging in get_transcript). Design: `1-multilingual-asr.md`, `8-transcription-model.md`.

- New: `Transcription/Engines/{Qwen3ASREngine,WhisperKitEngine,EngineAudio,SpeechModels,CodeSwitchAnalyzer}.swift`, `Transcription/LocalSpeechEngine.swift`, `scripts/fetch-sherpa.sh`, `Vendor/` (git-excluded binary)
- Hooks: `Transcription/Transcription.swift` (+87), `Transcription/TranscriptCache.swift` (+133), `Settings/StoragePane.swift` (+45)

## 2. zh-en punctuation restoration

ct-transformer post-pass folds sentence marks onto the unpunctuated qwen3 stream — count-preserving, script-aware (ASCII after Latin), merge-never-double. Design: `14-punctuated-segmentation.md`.

- New: `Transcription/Engines/PunctuationRestorer.swift` (+ fold logic inside `Qwen3ASREngine.swift`)

## 3. Transcript correction glossary

Layered (global/library/project) additive corrections, read-time materialisation (raw cache never mutated), auto-promotion of clean caption edits, confidence tiers, review UI. Design: `2-glossary.md`, `11-glossary-persistence.md`.

- New: `Glossary/` (10 files), `Agent/Tools/ToolExecutor+Glossary.swift`, `Editor/ViewModel/EditorViewModel+GlossaryPromotion.swift`, `MediaPanel/CaptionsTab/CaptionGlossarySection.swift`, `Transcription/TranscriptionBias.swift` (legacy cache shim only)
- Hooks: `ToolExecutor+Texts.swift` (promotion in update_text), `ToolExecutor+Media.swift`, `Project/VideoProject.swift` (glossary in export)

## 4. Reactive caption resync

Captions follow the audio under them: L2→L3 invariant, generatedText provenance, clean/dirty policy, span exclusion, cold-cache preservation, conflict flags + freeze. Design: `3-caption-resync.md`, `10-resync-materialisation.md`, `16-caption-ui-resync.md`.

- New: `Editor/CaptionResync/{CaptionResyncEngine,TimelineTranscriptProvider}.swift`, `Editor/ViewModel/EditorViewModel+{CaptionResync,CaptionConflict}.swift`, `Agent/Tools/ToolExecutor+CaptionResync.swift`
- Hooks: `EditorViewModel+{ClipMutations,Ripple,Timelines}.swift` (mutation triggers), `EditorUndo.swift`, `Timeline/ClipRenderer.swift` (conflict badge), `Timeline/TimelineInputController.swift`

## 5. Caption-style profiles & filler policy

Reusable measured typography/filler/protected-phrase policy, layered global→library→project, field-wise merge under explicit params. Design: `4-caption-style.md`, `12-style-lint-persistence.md`.

- New: `CaptionStyle/{CaptionStyleProfile,CaptionStyleStore,FillerPolicy}.swift`, `Agent/Tools/ToolExecutor+{CaptionStyle,SetCaptionStyle}.swift`
- Hooks: `ToolExecutor+Captions.swift` (+84, profile resolution)

## 6. CJK-natural segmentation & caption text

Punctuation/pause-driven line breaks (marks as signal, stripped per policy), protected phrases atomic, CJK-aware join/tokenize shared across generation and resync. Design: `5-caption-segmentation.md`, `14-punctuated-segmentation.md`.

- New: `MediaPanel/CaptionsTab/CaptionText.swift`
- Hooks: `CaptionBuilder.swift` (+288), `CaptionTranscriptMapper.swift` (+50)

## 7. Word-timing correctness & onset

Acoustic onset rollback, edit-safe timing retimes, interpolated-times honesty (`aligned` flag through get_transcript). Design: `6-caption-timing.md`, `7-caption-anim-onset.md`.

- New: `Transcription/Engines/OnsetRefiner.swift`, `MediaPanel/CaptionsTab/WordTimingRetimer.swift`
- Hooks: `Models/Timeline.swift` (wordTimings model + rescale), `ToolExecutor+Words.swift`

## 8. Caption animation granularity

Word/char karaoke units (NLTokenizer CJK words), off by default, agent-settable. Design: `7-caption-anim-onset.md`, `17-caption-ui-settings.md`.

- Hooks: `Models/TextAnimation.swift` (+22), `Compositing/TextFrameRenderer.swift` (+76), `Inspector/Tabs/TextTab.swift` (Animate-by row)

## 9. Caption lint

Suspected mis-recognition proofreading (near-sound substitutions), agent-completed suggestions, dismissals persisted in the style profile. Design: `9-caption-lint.md`.

- New: `CaptionLint/{CaptionLinter,AgentLintCompleter}.swift`, `Agent/Tools/ToolExecutor+CaptionLint.swift`

## 10. Transcription routing & per-project model selection

Cloud/auto/local preference persisted per project, per-project local-engine override with separate cache slots, cost gating, resolved-model reporting. Design: `8-transcription-model.md`, `15-local-model-selection.md`.

- New: `Transcription/TranscriptionPreference.swift`, `MediaPanel/CaptionsTab/TranscriptionModeReconciler.swift`
- Hooks: `ToolExecutor+ProjectSettings.swift` (+52), `Models/ProjectFile.swift`, `CloudTranscription.swift`, `TranscriptionBackend.swift`

## 11. Transcription indexing throughput

Lazy scoped background transcription, timeline-ordered priority queue, chunk-level foreground yield, persistent extracted-audio cache, non-blocking get_transcript (pending/complete contract), dual-layer bounded search. Design: `18-indexing-throughput.md`.

- New: `Transcription/{BackgroundTranscriptionGate,ExtractedAudioCache}.swift`
- Hooks: `Search/SearchIndexCoordinator.swift` (+78), `Transcription/TranscriptSearch.swift` (+64), `ToolExecutor+Transcription.swift` (+263), `MediaTab+Search.swift`, `ToolExecutor+Search.swift`

## 12. Caption editor UI

Resync toast/badge/freeze toggle, glossary review with one-click Confirm, model row with "— Default" annotation, settings surfacing of segmentation/maxWords. Design: `16-caption-ui-resync.md`, `17-caption-ui-settings.md`.

- New: `MediaPanel/CaptionsTab/CaptionSettingsResolver.swift`
- Hooks: `CaptionTab.swift` (+186), `TextTab.swift` (+89), `EditorViewModel.swift` (+80, UI state)

## Shared hook surfaces

Files several features touch — expect merge conflicts here first, resolve feature-by-feature:

| File                                                           | Serves                                                                                                  |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `Agent/Tools/ToolDefinitions.swift` (+186)                     | every feature with a tool schema                                                                        |
| `Models/Timeline.swift` (+60/−30)                              | resync provenance fields, timing model, decoder restructure                                             |
| `ToolExecutor+Texts.swift` (+213)                              | glossary promotion, entries batching, lint application                                                  |
| `CaptionsTab/CaptionSpecBuilder.swift`                         | upstream's off-main spec build; carries our segmentation, punctuation, protected phrases, filler policy |
| `ToolExecutor+Transcription.swift` (+263)                      | ASR routing, indexing contract, aligned flag                                                            |
| `AgentInstructions.swift`, `AppTheme.swift`, `Constants.swift` | small cross-feature additions                                                                           |

## Tests

Feature-sliced under `Tests/PalmierProTests/`: `Captions/`, `Glossary/`, `Transcription/`, `Search/`, `Rendering/`, `Agent/` — 1,453 tests; every feature carries its regression suite (fixtures anonymized, hermetic against real user files).
