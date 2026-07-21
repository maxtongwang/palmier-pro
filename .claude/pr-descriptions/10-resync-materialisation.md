# fix: resync reads the materialised transcript + cache/onset correctness

**Branch:** `fix/resync-materialisation` · **Depends on:** glossary, caption-resync, multilingual-asr, transcription-model

## Summary

Four audit findings, one critical: caption _generation_ read the glossary-materialised transcript while the resync engine's word source read raw cached JSON — so an ordinary trim silently reverted corrected captions to the mis-heard text, and glossary→caption propagation was a no-op.

## What's included

- **Materialising word source**: `TimelineTranscriptProvider` loads the project glossary corrector once per resync and applies it to cached reads — resync now sees exactly what generation sees. Corrected captions survive edits; adding a term genuinely rewrites the sibling captions that still show the variant.
- **Cloud resync**: cloud transcripts publish a provider-neutral full-file read alias, so cloud-transcribed projects resync instead of silently skipping.
- **Cache churn ended**: transcript cache keys are no longer salted by the glossary fingerprint by default (read-time materialisation applies corrections regardless, so per-term re-transcription of long files bought marginal decode gain at large cost). Explicit `cacheTag` opt-in remains; reads try unsalted → salted → alias so fresh writes win and legacy entries stay readable.
- **Onset refiner speech-attack gate**: rollback now requires a fast rise from near-silence that stays elevated — music fade-ins and isolated clicks no longer pull word starts onto non-speech energy (verified: genuine attacks over faint music beds still refine).
- **Uncached-ref protection**: a clean caption whose transcript isn't cached is preserved with a reasoned conflict instead of being deleted or partially shrunk by a glossary-triggered resync; promotion responses surface `skippedNoTranscript`.

## Testing

Materialisation pins (never-revert, propagation, removal round-trip), alias/read-order regressions, fade-in/click onset scenarios, uncached-preservation matrix. Full suite green.

## Also included

- **A cold cache never deletes captions**: resync over a source with no cached transcript previously hit the clean-clip empty-span auto-remove and silently deleted the caption — an empty word set is a missing read, not a speech cut. Destructive resolution of a clean clip is now gated on cache coverage; uncached refs preserve the clip and surface a conflict ("transcript not cached — resync skipped"). `update_text`'s promotion path surfaces the same report (`captionResync.skippedNoTranscript`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
