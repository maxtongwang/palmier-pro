# Caption Timing Fixes — Dependency Graph

## Tasks

| ID    | Task                                     | Depends on |
| ----- | ---------------------------------------- | ---------- |
| BUG-4 | `WordTiming.aligned` threaded end-to-end | —          |
| BUG-3 | Engine onset refinement (PCM envelope)   | BUG-4      |
| BUG-5 | Incremental re-alignment on text edit    | BUG-4      |
| BUG-6 | Word animation honors real spans (CJK)   | —          |

## Contracts

| Edge                | Contract                                                                  |
| ------------------- | ------------------------------------------------------------------------- |
| WordTiming          | adds `aligned: Bool?` (Codable, missing-key tolerant)                     |
| OnsetRefiner        | pure `refineOnsets(words:samples:sampleRate:fps:) -> [TranscriptionWord]` |
| CaptionText.tokens  | shared tokenizer: Latin runs grouped, CJK scalars individual              |
| WordTimingRealigner | `retime(old:newContent:duration:) -> [WordTiming]?` (nil = clear)         |

## Cache

Qwen3 cacheTag qw5→qw6, Whisper wk1→wk2 (onset refinement changes transcript output).
