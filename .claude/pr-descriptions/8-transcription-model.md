# feat: transcription model selection — per-project preference, resolved-model reporting, no silent degradation

**Branch:** `feature/transcription-model` · own diff: ~16 files · **Depends on:** multilingual-asr (model ids), caption-resync (ProjectFile pattern)

## Summary

A captioning run silently fell back to local ASR because the account lacked cloud credits, producing word errors the higher-accuracy path would have avoided — and nothing surfaced which model ran. Model choice was invisible at the tool layer and configurable only as an app-global setting.

## What's included

- **`transcriptionPreference: auto | cloud | local`** persisted per project (tolerant decoding), exposed via `set_project_settings`:
  - `auto` — today's behavior exactly (cloud when signed in with credits, else local), byte-identical decision path.
  - `cloud` — fail loudly with an actionable error (distinct signed-out vs no-credits messages) instead of silently degrading. The point: accuracy-critical captioning can force the high-accuracy path.
  - `local` — always local, no cost estimation.
- **Resolved-model reporting:** `TranscriptionResult` is stamped at the engine boundary (`qwen3-asr-0.6B-int8`, `whisper-large-v3_turbo`, `apple-speech`, or the cloud backend's model id) and preserved through every transform; `get_transcript`, `add_captions`, and `inspect_media` responses now carry `transcriptionModel` + `transcriptionSource`. Cached entries report the model that produced them, never the currently-configured engine (engine-tagged keys make a mislabel structurally impossible; invariant pinned by test).
- **Low-accuracy notice** on responses only when `auto` degraded to local — never when local was chosen deliberately.
- Selection logic documented inline at both decision points (engine routing incl. the Apple-fallback path; the new pure `resolveTranscriptionProvider` seam).

Deliberately NOT included: per-project local-engine override — the engine choice participates in transcript cache keys, so a per-project override needs a threaded cache-contract change; noted as follow-up rather than half-done.

## Testing

23 new tests: full preference × account-state matrix, model stamping per engine incl. failure fallback, notice gating, ProjectFile round-trip/legacy decode, cache-tag distinctness invariant. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
