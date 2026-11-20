# VoiceNotes — iOS 语音速记 MVP

全程离线：录音 → **sherpa-onnx SenseVoice** ASR → **MLX Swift + Qwen 0.5B/0.6B** 整理 → 本地 SwiftData。

工程路径：`/Users/xw/Documents/VoiceNotes`

## 用 Xcode 打开

```bash
cd /Users/xw/Documents/VoiceNotes
xcodegen generate   # 若尚无 .xcodeproj，或改过 project.yml
open VoiceNotes.xcodeproj
```

选择任意 **iPhone Simulator**，⌘R 运行。

## 目录

```text
VoiceNotes/
  App/                 # @main、DI
  Features/
    Record/            # 首页录音
    Notes/             # 列表、详情、搜索
    Settings/          # 模型占用、隐私
  Domain/
    Note.swift         # SwiftData 模型 + status
    SpeechRecognizer.swift
    Enricher.swift     # 协议；云端预留，MVP 不实现
    NotePipeline.swift # 录音→ASR→整理状态机
  Infra/
    Audio/             # AVAudioRecorder / Player · 16 kHz mono
    ASR/               # SenseVoiceRecognizer（sherpa 适配层 stub）
    LLM/               # OnDeviceEnricher（MLX Qwen stub）
    Persistence/
    ModelStore/
```

## 已实现 vs Stub

| 模块 | 状态 |
|------|------|
| SwiftUI 壳（录音 / 列表 / 详情 / 设置） | ✅ 可编译运行 |
| AVAudioRecorder 16 kHz mono M4A | ✅ |
| SwiftData `Note` + 状态枚举 | ✅ |
| `NotePipeline` 状态机 + 失败重试 | ✅ |
| 关键词搜索 | ✅（内存过滤） |
| `SpeechRecognizer` / `Enricher` 协议 | ✅ |
| `SenseVoiceRecognizer` | 🔶 适配层 stub（Simulator 返回模拟转写） |
| `OnDeviceEnricher` | 🔶 无权重时用本地启发式；有权重目录时待接 MLX |
| 模型按需下载 | 🔶 API 位已留，抛 `notImplemented` |
| sherpa-onnx / MLX 原生链接 | ❌ 见下方步骤（避免首次骨架被大包体卡住） |

## 后续依赖（真实 ASR / LLM）

在 `project.yml` 取消注释 `packages` 与 target `dependencies`，然后：

```yaml
packages:
  sherpa-onnx:
    url: https://github.com/k2-fsa/sherpa-onnx
    from: 1.12.0
  mlx-swift:
    url: https://github.com/ml-explore/mlx-swift
    from: 0.33.0
  mlx-swift-lm:
    url: https://github.com/ml-explore/mlx-swift-lm
    from: 2.0.0
```

Target 依赖产品建议：

- `sherpa-onnx` → product `sherpa-onnx`
- `mlx-swift-lm` → product `MLXLLM`（及 `MLXLMCommon`）

```bash
xcodegen generate
# Xcode 会拉 SPM；sherpa 的 xcframework 体积较大
```

模型权重放到（或由 ModelStore 下载到）：

- ASR：`Library/Application Support/VoiceNotes/Models/ASR/sensevoice-small/`
- LLM：`Library/Application Support/VoiceNotes/Models/LLM/qwen2.5-0.5b-instruct/`

然后实现：

1. `Infra/ASR/SenseVoiceRecognizer.transcribe` → sherpa `OfflineRecognizer` + SenseVoice
2. `Infra/LLM/OnDeviceEnricher.enrich` → MLX `ModelContainer` 生成 JSON
3. `ModelStore.download` → Wi-Fi 下载 + 哈希校验

**硬约束**：MVP 禁止云端 LLM；流水线只依赖 `Enricher`，日后云端另实现同一协议且勿接线进设置可选项。

## 重新生成工程

```bash
cd /Users/xw/Documents/VoiceNotes
xcodegen generate
```
