# fix: word-level animation granularity (off by default) + onset fixes reach existing captions

**Branch:** `fix/caption-anim-onset` · own diff: ~15 files · **Depends on:** fix/caption-timing, caption-resync

## Summary

Two follow-ups from user testing:

1. Per-character animation had become the de-facto default for CJK captions (correct timing data, wrong default look — every character bounced individually).
2. Improved speech onsets never reached already-placed captions: resync deliberately kept clip boundaries, so a caption anchored 1.5 s late stayed late even after the transcript was fixed.

## What's included

- **`TextAnimation.granularity: word | char`** (tolerant Codable; missing = word). Word mode groups CJK characters into NLTokenizer words — 电影 animates as one unit whose span is the union of its characters' timings; char mode is the explicit opt-in for per-character styles. Animations remain **off by default everywhere** — audited every construction path (generation, UI, tools, resync inheritance) and pinned with regression tests; tool schemas now state captions are static unless `animation` is passed.
- **Boundary retiming in resync:** provably-generated, unedited caption clips move to their live word span (earlier onset, tightened trailing silence) when it drifts beyond a 2-frame threshold — clamped against neighbors, karaoke timings rebased, changes reported in a new additive `retimed` list. Hand-edited/unknown-provenance clips' boundaries are never touched. Repeat resyncs are a no-op (idempotency pinned).
- **OnsetRefiner rollback cap 1.5 s → 2.5 s** — a real case had a 1.77 s lag that the old cap clipped; rollback stays bounded by the previous word's end and the energy edge, so the larger cap only helps genuine silence gaps.

## Testing

19 new tests: granularity grouping/opt-in/decoding, off-by-default pins, retiming extend/tighten/clamp/threshold/idempotency, tool-path end-to-end retime, beyond-old-cap onset. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
