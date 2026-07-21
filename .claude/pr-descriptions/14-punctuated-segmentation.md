# fix: punctuated local transcripts + pause/glossary-anchored natural segmentation

**Branch:** `fix/punctuated-segmentation` · **Depends on:** multilingual-asr, caption-segmentation, glossary, caption-style

## Summary

The local qwen3-asr port emits a pure character stream with zero punctuation (verified: the sherpa Qwen3 config has no punctuation option), which left `segmentation:natural` with no anchors — 2–3 character fragments, mid-name splits, merges across real speech pauses. Three compounding fixes, all local (the recognizer stays qwen3):

## What's included

- **Punctuation restoration**: sherpa-onnx's ct-transformer zh-en punctuation model runs as a post-pass over each chunk's text — marks fold onto the preceding word, piece counts and word timings byte-unchanged, WhisperKit anchor alignment unaffected (match keys strip punctuation). The model downloads on demand; any failure latches to passthrough — transcription never fails for punctuation. A guard rejects restorations that alter base characters. Engine cache tag bumped so stale transcripts regenerate punctuated.
- **Pause-aware hard breaks**: gaps ≥ 0.4 s between words split the stream into independently-segmented runs — real speech pauses always break, even on unpunctuated text; fps-independent (seconds-based). Content is provably never dropped (natural-mode output text equals fixedChars-mode text, pinned; zero-duration words survive with a floored display duration).
- **Glossary-aware protection**: protected phrases (glossary canonicals + caption-style protected phrases) become atomic tokens via longest-match — 重庆西站 never splits at a width cap; lines break before the term. A genuine pause _inside_ a protected term still splits (documented, pinned: silence mid-term implies a bad match).

## Testing

Punctuation fold/passthrough/altered-fallback, the real opening-line acceptance case (「好久没有拍视频了。那我现在人在重庆西站在等着」 → whole-phrase lines), pause-break and content-preservation pins, protection matrices. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
