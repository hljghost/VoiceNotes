#!/usr/bin/env bash
# Download SenseVoice Small int8 from ModelScope（大陆可达），校验 SHA-256。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/Models/ASR/sensevoice-small}"

# 勿直连 GitHub / HuggingFace；优先 ModelScope 多镜像
REPOS=(
  "pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue"
  "chriscrs/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
  "vqhvqh/SenseVoice_Small_int8_ONNX"
  "burgess123/sherpa-onnx-SenseVoice-Small-onnx"
  "vcbvcx/SenseVoice_Small_Int8"
)

MODEL_SHA256="c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
TOKENS_SHA256="f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"

mkdir -p "$OUT_DIR"

download_one() {
  local file="$1" sha="$2" dest="$OUT_DIR/$1"
  if [[ -f "$dest" ]]; then
    local actual
    actual="$(shasum -a 256 "$dest" | awk '{print $1}')"
    if [[ "$actual" == "$sha" ]]; then
      echo "skip existing $file (sha ok)"
      return 0
    fi
    echo "re-download $file (sha mismatch)"
    rm -f "$dest"
  fi

  local ok=0
  for repo in "${REPOS[@]}"; do
    local url="https://www.modelscope.cn/models/${repo}/resolve/master/${file}"
    echo "  try ModelScope $repo …"
    if curl -L --http1.1 --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 900 \
        -o "$dest" "$url"; then
      local actual
      actual="$(shasum -a 256 "$dest" | awk '{print $1}')"
      if [[ "$actual" == "$sha" ]]; then
        echo "  ok $file from $repo sha=${actual:0:12}…"
        ok=1
        break
      fi
      echo "  sha mismatch from $repo, try next"
      rm -f "$dest"
    fi
  done
  if [[ "$ok" != "1" ]]; then
    echo "下载失败：$file（所有 ModelScope 镜像均不可用）。请换网络后重试。" >&2
    exit 1
  fi
}

echo "Downloading SenseVoice int8 from ModelScope…"
download_one "model.int8.onnx" "$MODEL_SHA256"
download_one "tokens.txt" "$TOKENS_SHA256"

echo "Installed:"
ls -lh "$OUT_DIR"
echo
echo "Mirror: ModelScope (pengzhendong / chriscrs / vqhvqh / …)"
echo "App expects:"
echo "  <App Sandbox>/Library/Application Support/VoiceNotes/Models/ASR/sensevoice-small/{model.int8.onnx,tokens.txt}"
