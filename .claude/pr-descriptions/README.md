# Upstream PR Descriptions

One file per branch, ready to paste when opening PRs against `palmier-io/palmier-pro`.

## Stacking order

| Wave | Branch                         | Depends on                                                               |
| ---- | ------------------------------ | ------------------------------------------------------------------------ |
| 1    | multilingual-asr               | —                                                                        |
| 1    | feature/glossary               | —                                                                        |
| 1    | feature/caption-resync         | —                                                                        |
| 1    | feature/caption-style          | —                                                                        |
| 2    | fix/caption-segmentation       | caption-resync (engine edits), caption-style (add_captions params)       |
| 2    | fix/caption-timing             | caption-resync (generatedText/retimer), multilingual-asr (engine timing) |
| 3    | fix/caption-anim-onset         | fix/caption-timing (renderer/word timings), caption-resync               |
| 3    | feature/transcription-model    | multilingual-asr (engine ids), caption-resync (ProjectFile pattern)      |
| 3    | feature/caption-lint           | feature/glossary, feature/caption-style                                  |
| 4    | fix/resync-materialisation     | glossary, caption-resync, multilingual-asr, transcription-model          |
| 4    | feature/glossary-persistence   | glossary, caption-resync                                                 |
| 4    | feature/style-lint-persistence | caption-style, caption-lint                                              |
| 4    | feature/tool-ergonomics        | caption-resync, glossary, caption-style, caption-lint                    |

Wave 1 branches sit directly on upstream v0.6.11 and can be PR'd as-is.
Wave 2/3 branches were cut from the fork integration branch; to PR upstream, either
(a) open them as stacked PRs after their dependencies merge, retargeting each PR's
base branch, or (b) rebase each onto upstream main once dependencies land and let
CI confirm. Their descriptions below describe only the branch's own change set.
