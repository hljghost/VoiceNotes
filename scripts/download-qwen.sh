#!/usr/bin/env bash
# Download MLX Qwen2.5-0.5B-Instruct-4bit into Models/LLM/qwen2.5-0.5b-instruct/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/Models/LLM/qwen2.5-0.5b-instruct}"
REPO="https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit/resolve/main"

FILES=(
  config.json
  model.safetensors
  tokenizer.json
  tokenizer_config.json
  special_tokens_map.json
  vocab.json
  merges.txt
  added_tokens.json
)

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo "skip existing $f"
    continue
  fi
  echo "Downloading $f …"
  curl -L --http1.1 -C - -o "$f" "$REPO/$f"
done

ls -lh "$OUT_DIR"
echo
echo "App expects:"
echo "  <App Sandbox>/Library/Application Support/VoiceNotes/Models/LLM/qwen2.5-0.5b-instruct/"
echo "Or use Settings → 下载 inside the app."
