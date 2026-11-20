# VoiceNotes — iOS 语音速记 MVP

全程离线：录音 → **sherpa-onnx SenseVoice** ASR → **MLX Swift + Qwen 0.5B/0.6B** 整理（LLM 仍 stub）→ 本地 SwiftData。

工程路径：`/Users/xw/Documents/VoiceNotes`

## 用 Xcode 打开

```bash
cd /Users/xw/Documents/VoiceNotes
xcodegen generate   # 改过 project.yml 时
open VoiceNotes.xcodeproj
```

选 **iPhone 17 Simulator** 或真机（如 Ghost）⌘R。

SPM：`sherpa-onnx` **2.0.2**（含 iOS device + Simulator xcframework）。

## 验证：录一句中文短句

1. 首次启动后打开 **设置 → 下载** SenseVoice（~228MB，需网络；推理仍离线）。  
   或本机手动：
   ```bash
   ./scripts/download-sensevoice.sh
   # 再把 Models/ASR/sensevoice-small/ 拷进 App 沙盒：
   # Library/Application Support/VoiceNotes/Models/ASR/sensevoice-small/
   ```
2. 回首页，确认橙色提示消失（模型已就绪）。
3. 点录音，说一句中文（例如「明天上午十点开会」），停止。
4. 打开刚生成的笔记：应看到 **原文转写**；状态经 `transcribing` → `transcribed`（随后启发式整理可能到 `ready`）。
5. 失败时音频仍在；详情页可 **重试转写**。

飞行模式：模型下好后，转写不依赖网络。

## SenseVoice 模型文件

| 项 | 值 |
|----|-----|
| 本地目录 | `…/Application Support/VoiceNotes/Models/ASR/sensevoice-small/` |
| 文件 | `model.int8.onnx`（239 233 841 bytes）+ `tokens.txt`（315 894 bytes） |
| 归档名 | `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17` |
| GitHub 归档 | https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2 |
| 归档 SHA-256 | `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e` |
| App 内下载 | HuggingFace 同权单文件：`csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` 的 `model.int8.onnx` / `tokens.txt` |

## 已实现 vs Stub

| 模块 | 状态 |
|------|------|
| SwiftUI 壳 | ✅ |
| 16 kHz mono 录音 / 回放 | ✅ |
| SwiftData + NotePipeline | ✅ |
| **sherpa-onnx SPM 链接** | ✅ 2.0.2 |
| **SenseVoiceRecognizer 真实转写** | ✅（需模型文件） |
| ModelStore SenseVoice 下载 / 占用 / 删除 | ✅ |
| 关键词搜索 | ✅ |
| OnDeviceEnricher / MLX | 🔶 启发式 stub，未接 MLX |
| Qwen 模型下载 | ❌ |

## Simulator / 真机

- **Simulator**：xcframework 含 `ios-arm64_x86_64-simulator`，Debug 可编可跑；ASR 质量以真机为准。
- **真机**：同样链接；首次需下载模型。签名：在 Xcode 选自己的 Team。

## 目录

```text
VoiceNotes/
  App/
  Features/ Record · Notes · Settings
  Domain/   Note · SpeechRecognizer · Enricher · NotePipeline
  Infra/
    Audio/  Recorder · Player · SampleLoader（M4A→16k float）
    ASR/    SenseVoiceRecognizer（sherpa OfflineRecognizer）
    LLM/    OnDeviceEnricher（stub）
    ModelStore/
scripts/download-sensevoice.sh
```

**硬约束**：MVP 禁止云端 LLM；流水线只依赖 `Enricher`。
