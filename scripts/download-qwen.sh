#!/usr/bin/env bash
# Download MLX Qwen2.5-0.5B-Instruct-4bit via ModelScope（大陆可达）
# into Models/LLM/qwen2.5-0.5b-instruct/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/Models/LLM/qwen2.5-0.5b-instruct}"
# 勿直连 HuggingFace；使用 ModelScope resolve
REPO="https://www.modelscope.cn/models/mlx-community/Qwen2.5-0.5B-Instruct-4bit/resolve/master"

# file|sha256|expected_bytes
FILES=(
  "config.json|b045e57ea90b8f1b35f89f954b176a5c1faa02bd0af2c89bcec191239d66cef4|783"
  "model.safetensors|ddffab9cbc7bf6dde941c6724841eeca8981fcfa81ca20ff8efff1396326d153|278064920"
  "tokenizer.json|a8506e7111b80c6d8635951a02eab0f4e1a8e4e5772da83846579e97b16f61bf|7031673"
  "tokenizer_config.json|f7c61e32b7a17d19bf8e7037dcb74079a833e53ea9801f24008cac68458f03b7|7308"
  "special_tokens_map.json|76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd|613"
  "vocab.json|ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910|2776833"
  "merges.txt|8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5|1671853"
  "added_tokens.json|58b54bbe36fc752f79a24a271ef66a0a0830054b4dfad94bde757d851968060b|605"
)

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

for entry in "${FILES[@]}"; do
  IFS='|' read -r f sha expected <<<"$entry"
  if [[ -f "$f" ]]; then
    actual="$(shasum -a 256 "$f" | awk '{print $1}')"
    if [[ "$actual" == "$sha" ]]; then
      echo "skip existing $f (sha ok)"
      continue
    fi
    echo "re-download $f (sha mismatch)"
    rm -f "$f"
  fi
  echo "Downloading $f from ModelScope…"
  curl -L --http1.1 --retry 3 --retry-delay 2 -C - -o "$f" "$REPO/$f"
  actual="$(shasum -a 256 "$f" | awk '{print $1}')"
  if [[ "$actual" != "$sha" ]]; then
    echo "Checksum mismatch for $f: $actual (expected $sha)" >&2
    exit 1
  fi
  size="$(wc -c <"$f" | tr -d ' ')"
  echo "  ok size=$size expected≈$expected sha=${actual:0:12}…"
done

ls -lh "$OUT_DIR"
echo
echo "Mirror: ModelScope ($REPO)"
echo "App expects:"
echo "  <App Sandbox>/Library/Application Support/VoiceNotes/Models/LLM/qwen2.5-0.5b-instruct/"
echo "Or use Settings → 下载 inside the app."
