# perf: transcription indexing — lazy, prioritized, preemptible, with a persistent audio-extraction cache

**Branch:** `feature/indexing-throughput` · **Depends on:** multilingual-asr (engines, cache slots), caption-resync (resync's cache-only reads), local-model-selection (per-project engine slots)

## Summary

On a real 293-asset library (~5 h of source audio for a 42-minute cut), background transcription indexing blocked the editor: library order ignored what the user was editing, one long unused asset could starve an interactive request for half an hour, and any cache invalidation re-demuxed multi-GB source video. This PR makes indexing serve the editor first and re-runs cost only what actually changed.

## What's included

- **Lazy, scoped background transcription**: only assets referenced by an open timeline transcribe eagerly; idle library media is visual-indexed but transcribes on first read, so a cache invalidation can never fan re-transcription across the whole library.
- **Timeline-ordered priority**: tier 0 = active-timeline assets in timeline order (the top of the cut is ready before the tail), tier 1 = other open timelines, tier 2 = the rest. A timeline switch re-sorts the pending queue in place.
- **Non-blocking reads with an explicit partial contract**: `get_transcript` returns cached clips immediately; uncached ones get transcription fired and come back under `pending` (with `indexing {done,total}` progress). A clip is in `clips` or in `pending`, never both, and the payload carries `complete:false` while anything visible is pending — an automated diff pass cannot mistake an in-flight read for a settled one.
- **Chunk-level preemption**: background transcription yields to interactive reads *between decode chunks* (the engine actor is re-entrant at that suspension), not just between assets — a `get_transcript` is never stuck behind a 28-minute library asset.
- **Single-asset refresh**: `get_transcript {clipId, refresh:true}` invalidates that one asset's cached transcript and re-transcribes it — verification of a transcription change no longer costs a full-library run, and the clipId requirement means it can never fan out.
- **Persistent audio-extraction cache**: the audio-only 16 kHz mono extraction (CAF, ~110 MB/h) persists keyed by source-file identity (path|mtime|size), bounded by a 4 GB LRU. Re-transcription after a model or pipeline change reads the small mono file instead of re-demuxing source video. Video frames are never decoded at any point.
- **Stage instrumentation**: every transcription logs its split — extract / decode / punctuation / timing-anchor wait / total / real-time factor / compute backend — so future optimization starts from measurement, not guesses.

## Testing

Priority-tier ordering (incl. timeline-order within tier 0), queue re-prioritization, gate preemption determinism (continuation-based, no sleeps), audio-cache round-trip/identity-key/LRU eviction, pending-vs-clips mutual exclusion, refresh validation. Full suite green on the branch.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
