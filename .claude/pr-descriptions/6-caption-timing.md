# fix: caption timing pipeline — speech-onset refinement, honest word timing, edit-surviving karaoke

**Branch:** `fix/caption-timing` · own diff: ~12 files · **Depends on:** multilingual-asr, caption-resync

## Summary

Four timing bugs from production zh/en footage:

1. **Onset lag** — captions appeared up to ~1.8 s after the speaker started (word starts quantized to chunk/anchor boundaries after silence gaps).
2. **CJK word timings were interpolation** (equal spacing by character count) with no way for consumers to know.
3. **Any content edit cleared the whole line's word timings** — removing one filler killed karaoke for the line.
4. **Word animations ignored real word timings**, using a uniform per-word duration.

## What's included

- **`OnsetRefiner`** — pure function over the 16 kHz PCM envelope: a word starting a speech run after a silence gap rolls back to the energy rising edge, biased 2–3 frames early, clamped to the previous word, capped rollback. Wired into the Qwen3 and Whisper paths at the engine level so the transcript itself improves; engine cache tags bumped so stale transcripts regenerate.
- **`WordTiming.aligned`** — the engine-level `aligned: false` (interpolated) flag now travels into caption clips and the tool read path, so karaoke consumers can distinguish measured timing from fabricated. (True CJK forced alignment is future work; honest marking is the fix.)
- **`WordTimingRetimer`** — on content edits, word timings are re-aligned by token LCS instead of cleared: unchanged words keep their exact spans, deletions absorb into the gap without shifting neighbors, insertions interpolate (marked unaligned). Only a full rewrite falls back to clearing. Applies to both the tool path and the inspector.
- **Renderer honors word timings** — per-word animation progression uses the clip's actual spans when present; the whitespace tokenizer that collapsed space-less CJK lines into a single animation unit is replaced with CJK-aware tokenization. Uniform `perWordFrames` remains the fallback.

## Testing

21 new tests: onset synthesis (tone-burst rollback, clamping, caps), aligned round-trips, retimer exact-span preservation (the delete-a-leading-comma case keeps every remaining span byte-identical), renderer non-uniform progression + mismatch tolerance. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
