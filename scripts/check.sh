#!/bin/bash
# Fork verification gate — runs upstream's documented pipeline (CONTRIBUTING.md: swift build,
# swift test) plus the fork's own requirements (BundledSpeech trait build for transcription
# changes). Every change merges to main only after this passes clean.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (upstream CONTRIBUTING baseline)"
swift build

if git diff --name-only HEAD~1 2>/dev/null | grep -qE "Transcription|Speech|MLX|CaptionResync" || [ "${1:-}" = "--full" ]; then
  echo "==> swift build --traits BundledSpeech (transcription surface touched)"
  swift build --traits BundledSpeech
fi

echo "==> swift test (upstream CONTRIBUTING baseline)"
swift test

echo "==> OK — gate passed"
