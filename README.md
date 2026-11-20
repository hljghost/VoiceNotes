# VoiceNotes — iOS 语音速记 MVP

全程离线：录音 → **sherpa-onnx SenseVoice** ASR → **MLX + Qwen2.5 0.5B Instruct 4bit** 整理 → SwiftData。

工程：`/Users/xw/Documents/VoiceNotes`

## 打开 / 编译

```bash
cd /Users/xw/Documents/VoiceNotes
xcodegen generate
# MLX 的 CudaBuild 插件仅 Linux 用；本机需跳过校验，并确保已装 Metal Toolchain：
#   xcodebuild -downloadComponent MetalToolchain
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug -skipPackagePluginValidation build
open VoiceNotes.xcodeproj
```

SPM：`sherpa-onnx` 2.0.2 · `mlx-swift-lm` 2.31.3（含 mlx-swift / swift-transformers）。

## 验证

1. 设置页下载 SenseVoice + Qwen（或脚本）：
   ```bash
   ./scripts/download-sensevoice.sh
   ./scripts/download-qwen.sh
   # 拷进沙盒 Application Support/VoiceNotes/Models/{ASR,LLM}/…
   ```
2. 录一句中文，或 `-AutoASRFixture` + `Fixtures/zh-16k.wav`。
3. 详情应有转写；整理后有标题/摘要/要点。
4. **真机**：`llmModelID` = `qwen2.5-0.5b-instruct`（真实 MLX）。  
   **Simulator**：Metal 不可用 → 自动启发式，`llmModelID` 带 `-simulator-heuristic`（权重可已下载）。

## 模型

| | ASR | LLM |
|--|-----|-----|
| 目录 | `Models/ASR/sensevoice-small/` | `Models/LLM/qwen2.5-0.5b-instruct/` |
| 主文件 | `model.int8.onnx` + `tokens.txt` | `model.safetensors` + tokenizer* |
| 大陆镜像 | **ModelScope** 多仓库（主：`pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue`，备：`chriscrs/…-int8-2024-07-17` 等）；校验 SHA-256 | **ModelScope** `mlx-community/Qwen2.5-0.5B-Instruct-4bit`（`resolve/master`）；校验各文件 SHA-256 |
| 上游内容 | sherpa-onnx SenseVoice Small int8 | 与 HF 同权重（ModelScope 镜像） |

应用内下载**只走 ModelScope（modelscope.cn）**，不直连 HuggingFace / GitHub；`hf-mirror.com` 本机实测会 308 到 HF，故未采用。失败提示中文并可重试。Mac 侧载：`./scripts/download-sensevoice.sh` · `./scripts/download-qwen.sh`。

## 已实现 vs 仍缺

| 项 | 状态 |
|----|------|
| SenseVoice 离线 ASR | ✅ |
| OnDeviceEnricher + MLX 链接 | ✅（真机推理；Sim 启发式降级） |
| ModelStore 双模型下载/删除/占用 | ✅ |
| 串行卸载 ASR↔LLM | ✅ |
| 真机签名部署本环境 | ❌（无 Xcode Account / profile；需本机 Xcode 登录后装 Ghost） |
| 云端 Enricher | ❌ 故意不做 |

## 降级策略

- 未下载 Qwen → 启发式整理，`…-heuristic`；Settings 橙色说明。
- Simulator 有权重 → 不初始化 Metal，启发式 `…-simulator-heuristic`。
- 真机有权重但推理失败 → `failedEnrich`，可重试，不丢转写。
