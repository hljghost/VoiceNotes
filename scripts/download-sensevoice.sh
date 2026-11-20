#!/usr/bin/env bash
# Download SenseVoice Small int8 into the iOS Simulator / Mac Application Support layout,
# or into a local Models/ folder for manual copy onto a device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/Models/ASR/sensevoice-small}"
ARCHIVE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
ARCHIVE_SHA256="7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"
FOLDER="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading SenseVoice int8 archive…"
curl -L --http1.1 -o "$TMP/model.tar.bz2" "$ARCHIVE_URL"

echo "Verifying SHA-256…"
ACTUAL="$(shasum -a 256 "$TMP/model.tar.bz2" | awk '{print $1}')"
if [[ "$ACTUAL" != "$ARCHIVE_SHA256" ]]; then
  echo "Checksum mismatch: $ACTUAL" >&2
  exit 1
fi

tar -xjf "$TMP/model.tar.bz2" -C "$TMP"
mkdir -p "$OUT_DIR"
cp "$TMP/$FOLDER/model.int8.onnx" "$TMP/$FOLDER/tokens.txt" "$OUT_DIR/"

echo "Installed:"
ls -lh "$OUT_DIR"
echo
echo "App expects:"
echo "  <App Sandbox>/Library/Application Support/VoiceNotes/Models/ASR/sensevoice-small/{model.int8.onnx,tokens.txt}"
echo "For Simulator, copy into the app container Application Support path after first launch,"
echo "or use Settings → 下载 inside the app (HuggingFace file URLs)."
