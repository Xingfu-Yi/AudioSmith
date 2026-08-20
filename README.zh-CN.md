# Audio Smith

[English](README.md)

[![CI](https://github.com/Xingfu-Yi/AudioSmith/actions/workflows/ci.yml/badge.svg)](https://github.com/Xingfu-Yi/AudioSmith/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-111111?logo=apple)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Developer Preview](https://img.shields.io/badge/status-Developer%20Preview-orange)

**面向 Apple Silicon，保护隐私、完全本地并支持术语 Skill 的听写工具。** 按住可配置的听写快捷键（默认 `Fn`）说话时，只用轻量波形确认正在收音；松开后，应用利用整段上下文完成转写，并把结果粘贴到原来正在使用的应用。

> 首个二进制版本发布前会补充经过隐私检查的真实操作录像；当前源码预览不会用伪造界面充当演示。

## 开发者预览版

Audio Smith 目前是早期源码预览，不是完成的二进制产品。它只使用一个 Qwen3-ASR-1.7B 8-bit 模型做自然停顿分段和上下文识别，不再加载第二个文本模型，也不在松开后用 LLM 重写全文。目标仍是中英混说、严格的 5GB 内存发布门禁，以及用于专业术语的紧凑 Markdown Skills。

当前源码构建版本为 Audio Smith `0.1.7 (8)`，开发机上的 58 项单元测试已全部通过。但项目尚未完成 24GB 机器、五分钟长上下文会话、公开准确率、签名和公证门禁。因此目前没有下载按钮、tag 或 DMG；在公开基准证明之前，README 也不会宣称尚未验证的准确率。

## 运行要求

运行要求：

- Apple Silicon Mac
- macOS 14 或更高版本
- 至少 24GB 物理统一内存（启动时硬性检查）
- 麦克风和辅助功能权限（辅助功能同时用于全局快捷键监听）
- 模型权重约 2.46GB，另需安装安全余量

v1 有意不支持 16GB Mac，也不提供更低精度的降档模式。

已验证的构建环境：

- Xcode 26.6、Swift 6.3
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Xcode Metal Toolchain

以上是项目实际验证过的版本，不代表对最低构建工具版本的承诺。

## 从源码快速开始

```bash
git clone git@github.com:Xingfu-Yi/AudioSmith.git
cd AudioSmith
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
./scripts/install_dev.sh
```

首次启动时，请授予所需权限，并等待 Audio Smith 下载和校验 [Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit)。自动下载源会并行测试 Hugging Face 与 ModelScope 中经过同一清单校验的 `config.json`，不会调用 IP 定位服务。模型权重不会存入 Git 仓库。

安装脚本默认构建经过优化的 Release 版本，完成签名后启动固定路径 `/Applications/Audio Smith.app`；应用 target、可执行文件、模块、Bundle ID、数据目录和日志标识都已统一为 Audio Smith。只有开发调试时才需要显式传入 `Debug`。测试宿主使用独立的 `.TestHost` Bundle ID，安装器还会验证最终运行的一定是 `/Applications` 副本。如果钥匙串中存在 Apple Development 身份，构建脚本会自动检测并签署最终应用；没有开发证书时会回退到 ad-hoc 签名，二进制变化后 macOS 仍可能要求重新授权。

开发时可以复用已有模型目录：

```bash
AUDIO_SMITH_ASR_MODEL_PATH=/absolute/path/to/Qwen3-ASR-1.7B-8bit \
  "/Applications/Audio Smith.app/Contents/MacOS/AudioSmith"
```

## 工作原理

1. 按下已选择的听写快捷键时保存原前台应用和所有已选 Skills 的快照，然后开始 16kHz 单声道录音。悬浮窗只显示波形和时长，不用不稳定的候选文字分散讲话者注意力。
2. Qwen3-ASR-1.7B 在一段话包含至少约 1.5 秒人声后，以约 1.2 秒连续静音确认自然分段，并在边界保留 400ms 重叠保护尾音。已结束的语段会在录音期间串行、静默识别。
3. 短暂停顿不会切段。连续讲话始终没有停顿时，30 秒仅作为安全上限，并在末尾五秒内选择最低能量位置。松开快捷键后，任何尚未完成的有人声尾段都按真实长度处理；低于模型最短输入时才补到 0.5 秒。有人声但结果为空时只追加 250ms 尾部静音重试一次；弱语音重叠接缝最多重解码局部 12 秒。
4. 松开后只识别尚未完成的尾段，不重跑完整录音，也不用文本模型精修，因此等待时间主要取决于最后一段，而不是整次听写的总长度。
5. Skill 规范拼写修复与空白、标点等确定性清理只执行一次。最终文字保留在剪贴板；只有原目标仍然有效且输入位置安全时才自动粘贴。

按 `Esc` 可取消当前听写。默认快捷键是 `Fn`，也可选择右 Option、右 Control 或右 Command；快捷键组合仍会取消听写并保留原系统快捷键。数据流、状态机、停顿分段策略和内存门禁见[架构文档](docs/ARCHITECTURE.md)。

波形胶囊会跟随当前输入窗口进入全屏 Space，并显示在正确的显示器上。录音期间可以直接把它拖到不遮挡内容的位置，不会激活 Audio Smith 或抢走键盘焦点；该位置只对本次听写有效，下一次听写仍回到底部中央。纯黑胶囊以外完全透明，不带矩形窗口阴影。

## Skills

一个 Skill 就是包含标准 `SKILL.md` 的目录，不需要配套 JSON：

```markdown
---
name: aigc
description: Improve mixed Chinese and English AIGC dictation.
---

# AIGC 专有名词读法

## 专有名词与读法

| 规范写法 | 读法或常见误识别 |
|---|---|
| Qwen-Image-Edit | 千问 Image Edit |
| token | 偷啃 |
```

用户 Skills 固定放在 `~/Library/Application Support/AudioSmith/Skills/<name>/SKILL.md`。本版本首次启动时会自动把一个可编辑的 `aigc/SKILL.md` 模板复制进去；用户副本优先于应用内置后备版本，保存修改后下一次听写自动生效，不需要重启应用。系统设置负责展示 Skills，菜单栏只保留快捷键、系统设置和退出三行。

初始内容只保留一个 **AIGC 专有名词读法** Skill，用紧凑表格记录大语言模型、扩散架构、图像/视频生成、训练与推理术语的规范拼写、读法和常见误识别。用户可以直接编辑表格；以后确有需要时仍可自行增加其他 Skill 目录。

每次听写前，Audio Smith 会把所有已选 Skills 的读法表格解析为不可变快照。最多 40 个规范术语和读法会压缩到 1,000 字符以内，直接作为 Qwen3-ASR 的识别上下文。自由 Markdown 正文只作为不可执行的说明保留，不会发送给模型；完整的限额词典仍可用于识别后的保守规范拼写修复。

Skills 是术语与上下文数据，不是可执行插件。Audio Smith 不会运行其中提到的代码、工具、脚本或链接资源。完整说明见 [Skill 规范](docs/SKILLS.md)和[可复制示例](Examples/Skills)。

## 隐私

- 模型安装后，语音完全在本地处理。
- 音频只存在于内存中，完成或取消后释放。
- Audio Smith 不保存音频、转写历史或遥测。
- 日志不得包含音频或转写正文。
- 除模型下载和未来明确启用的更新器外，核心流程不依赖网络。

安全问题请按 [SECURITY.md](SECURITY.md) 中的方式私下报告，不要创建公开 Issue。

## 实测性能

目前公开数字是开发机（M1 Pro、32GB）的 1.7B ASR 基线。当前应用已回到相同模型与精度，但停顿分段后的端到端应用测试仍待完成：

| 测量项 | 结果 | 范围 |
|---|---:|---|
| Python/MLX 推理 30 秒音频 | 1.88 秒（RTF 0.063） | 离线推理测试 |
| Python 进程峰值 footprint | 4.43GB | 离线推理测试 |
| Swift Debug 加载并静音预热 | 峰值 3.40GB，稳定后 2.43GB | 仅启动阶段 |

这些结果属于离线推理或启动观测，不是完整产品的端到端基准。运行时在 4.7GB 发出诊断警告，任何超过 5.0GB 的结果都会阻止二进制发布。当前目标和缺口在[基准文档](docs/BENCHMARKS.md)中严格分开。

## 开发

运行仓库校验和当前单元测试：

```bash
python3 scripts/validate_skills.py
python3 scripts/validate_docs.py
./scripts/test.sh
```

生成的 Xcode 工程和 `Package.resolved` 都会提交。MLXAudio Swift 固定在 commit `4266f988d170a83017d1e82e2e4654602f277f1d`，其传递 MLX 依赖记录在 `Package.resolved` 中。旧转换工具仍保留在 [`scripts/quantize_qwen3_asr.sh`](scripts/quantize_qwen3_asr.sh)；Audio Smith 不使用 TorchAO FP8。

## 路线图

- 在 M1 Pro 32GB 和至少一台 24GB Apple Silicon Mac 上完成五分钟停顿分段听写与 5GB footprint 门禁。
- 公开中文、英文和中英混说相对 BF16 的准确率对比。
- 完成辅助功能、安全输入框、多显示器、全屏、睡眠唤醒及目标应用测试。
- 完成应用图标、第三方许可证终审、Developer ID 签名、公证和可验证 DMG。

完整发布矩阵见[测试与发布门禁](docs/TESTING.md)。[发布说明](docs/PUBLISHING.md)将源码公开与未来二进制发布视为两个独立里程碑。

## 参与贡献

欢迎贡献和可复现的测试报告。创建 Issue 或 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，绝不要提交模型权重、录音、私人转写、证书或凭据。

## 许可证

Audio Smith 应用代码使用 [MIT License](LICENSE)。Qwen3-ASR 使用 Apache-2.0；MLXAudio Swift 和 MLX Swift 使用 MIT。归属和模型条款见[第三方声明](THIRD_PARTY_NOTICES.md)。
