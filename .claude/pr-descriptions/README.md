# Upstream PR Descriptions

One file per branch, ready to paste when opening PRs against `palmier-io/palmier-pro`.
18 branches total. Fix branches have been **folded into their parent feature branches** —
upstream never sees a bug and its fix as separate PRs.

## How to read this table

Upstream has zero context on this fork. Every PR body must state its dependencies
explicitly (the `Depends on:` line in each description), because a reviewer cannot
infer them. Do not open a PR before everything it depends on has merged.

| Wave | Branch                         | Depends on (must be merged first)                                                |
| ---- | ------------------------------ | -------------------------------------------------------------------------------- |
| 1    | multilingual-asr               | — (sits on upstream v0.6.11)                                                     |
| 1    | feature/glossary               | — (sits on upstream v0.6.11)                                                     |
| 1    | feature/caption-resync         | — (sits on upstream v0.6.11)                                                     |
| 1    | feature/caption-style          | — (sits on upstream v0.6.11)                                                     |
| 2    | fix/caption-segmentation       | caption-resync, caption-style                                                    |
| 2    | fix/caption-timing             | caption-resync, multilingual-asr                                                 |
| 3    | fix/caption-anim-onset         | fix/caption-timing, caption-resync                                               |
| 3    | feature/transcription-model    | multilingual-asr, caption-resync                                                 |
| 3    | feature/caption-lint           | feature/glossary, feature/caption-style                                          |
| 4    | fix/resync-materialisation     | glossary, caption-resync, multilingual-asr, transcription-model                  |
| 4    | feature/glossary-persistence   | glossary, caption-resync                                                         |
| 4    | feature/style-lint-persistence | caption-style, caption-lint                                                      |
| 4    | feature/tool-ergonomics        | caption-resync, glossary, caption-style, caption-lint                            |
| 5    | fix/punctuated-segmentation    | multilingual-asr, fix/caption-segmentation, glossary, caption-style              |
| 5    | feature/local-model-selection  | multilingual-asr, transcription-model                                            |
| 5    | feature/indexing-throughput    | multilingual-asr, caption-resync, local-model-selection                          |
| 6    | feature/caption-ui-resync      | caption-resync, glossary-persistence, fix/caption-anim-onset                     |
| 6    | feature/caption-ui-settings    | caption-segmentation, caption-style, glossary-persistence, local-model-selection |

## Branch mechanics (read before opening any PR)

- **Wave 1** branches sit directly on upstream v0.6.11 and can be PR'd as-is, today.
- **Waves 2–6** were cut from this fork's integration branch, so each branch's _tree_
  contains its dependencies' code. The branch's own change set is what its description
  documents. To PR upstream: after a branch's dependencies merge, **rebase it onto
  upstream main and let the squashed diff shrink to just its own changes** — duplicate
  hunks (shared fixes present in two snapshots) resolve as already-applied. Open stacked
  PRs only in dependency order.
- **Decoder biasing does not exist upstream.** `fix/caption-segmentation` ships with
  recognition as a pure function of audio + model (no glossary hotword injection, no
  bias-salted cache keys). Later-wave snapshots may still contain remnants of the
  removed bias plumbing from the fork's history — strip any such remnant at rebase
  time; nothing may reference `TranscriptionBias` in an upstream PR.
- **Cache tags**: upstream ships qwen3 at tag `qw7`. The fork's `qw8` bump existed only
  to invalidate locally-biased cache entries; upstream never had biased entries, so do
  NOT carry the bump into a PR.

## Folded fixes (why some branches have an "Also included" section)

These fixes were developed as separate branches on the fork and have been folded into
their parents so upstream reviews one coherent feature:

| Folded fix                                                                        | Now part of                                                                   |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| never-cache-interrupted decodes                                                   | multilingual-asr (+ fix/punctuated-segmentation, feature/indexing-throughput) |
| decoder-bias removal                                                              | fix/caption-segmentation                                                      |
| punctuation merge-not-double, CJK join, punctuation-as-signal, script-aware marks | fix/punctuated-segmentation                                                   |
| CJK sentence rows in get_transcript                                               | feature/tool-ergonomics                                                       |
| cold-cache never deletes captions                                                 | fix/resync-materialisation                                                    |
| classifier single-implementation                                                  | feature/caption-ui-resync (introduced classifyWithReason)                     |
| hermetic glossary test roots                                                      | fix/caption-segmentation, feature/glossary-persistence                        |
| Animate-by row, Model default annotation, glossary Confirm                        | feature/caption-ui-settings                                                   |
| lazy reindex + priority + audio cache + partial-flag                              | feature/indexing-throughput (new consolidated branch)                         |
