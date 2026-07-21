# feat: on-device multilingual ASR (Qwen3-ASR + WhisperKit) with anchored CJK word timing

**Branch:** `multilingual-asr` → `main` · 7 commits · 14 files, +1162/−9

## Summary

Adds two on-device transcription engines beside Apple Speech and makes Qwen3-ASR 0.6B the default local engine: Alibaba's newest open ASR (30+ languages, 20+ Chinese dialects, native code-switching). Dramatically better zh/en code-switched transcription than Apple Speech, fully offline.

## What's included

- `Transcription/Engines/Qwen3ASREngine.swift` — Qwen3-ASR 0.6B int8 via sherpa-onnx (C API). Model auto-downloads (~840 MB) on first use. Audio is chunked ~12 s at quiet points to stay inside the decoder's token budget.
- `Transcription/Engines/WhisperKitEngine.swift` — Whisper large-v3 turbo via WhisperKit (CoreML/ANE). Doubles as a standalone engine and as Qwen3's timing track.
- **Anchored word timing:** sherpa's Qwen3 port emits no token timestamps, so a parallel WhisperKit pass supplies DTW word times, LCS-aligned to Qwen3's text on normalized keys. Code-switched runs that Whisper auto-translates away are rescued by re-running the chunk with the language forced. Words with no acoustic anchor are interpolated and marked `aligned: false` on `TranscriptionWord` — timing honesty is part of the contract; consumers can tell measured from fabricated.
- `Transcription/LocalSpeechEngine.swift` — engine selection (qwen3 | whisper | apple), persisted, with a Settings picker; any engine failure falls through to Apple Speech.
- Engine-tagged transcript cache keys so switching engines re-transcribes instead of serving another engine's output.
- `scripts/fetch-sherpa.sh` vendors the sherpa-onnx xcframework (exceeds GitHub's file cap, so it is fetched, not committed).

## Testing

Unit tests for the engine plumbing and alignment; full suite green. Verified end-to-end on 40-minute zh/en code-switched footage.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
