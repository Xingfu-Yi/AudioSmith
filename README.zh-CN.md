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

Audio Smith 目前是早期源码预览，不是完成的二进制产品。项目围绕 Qwen3-ASR-1.7B、MLX 8-bit affine 权重、中英混说、严格的 5GB 内存发布门禁，以及用于专业术语的标准 Markdown Skills 设计。

源码已能在开发机上构建，核心单元测试也已通过。但项目尚未完成 24GB 机器、五分钟长上下文会话、公开准确率、签名和公证门禁。因此目前没有下载按钮、tag 或 DMG；在公开基准证明之前，README 也不会宣称尚未验证的准确率。

## 运行要求

运行要求：

- Apple Silicon Mac
- macOS 14 或更高版本
- 至少 24GB 物理统一内存（启动时硬性检查）
- 麦克风、输入监控和辅助功能权限
- 固定模型约 2.46GB，另需安装安全余量

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

首次启动时，请授予所需权限，并等待 Audio Smith 下载和校验固定版本的 [mlx-community/Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit) 模型。下载量约 2.46GB，模型权重不会存入 Git 仓库。

安装脚本会构建、签名并启动固定路径 `/Applications/DictateAgent.app`。`AudioSmith` 仓库暂时保留历史内部应用路径、Bundle ID 和数据目录，因此现有模型、Skills 与 macOS 权限无需迁移。测试宿主使用独立的 `.TestHost` Bundle ID，安装器还会验证最终运行的一定是 `/Applications` 副本。如果钥匙串中存在 Apple Development 身份，构建脚本会自动检测并签署最终应用；没有开发证书时会回退到 ad-hoc 签名，二进制变化后 macOS 仍可能要求重新授权。

开发时可以复用已有模型目录：

```bash
DICTATE_AGENT_MODEL_PATH=/absolute/path/to/Qwen3-ASR-1.7B-8bit \
  /Applications/DictateAgent.app/Contents/MacOS/DictateAgent
```

## 工作原理

1. 按下已选择的听写快捷键时保存原前台应用和所有已选 Skills 的快照，然后开始 16kHz 单声道录音。悬浮窗只显示波形和时长，不用不稳定的候选文字分散讲话者注意力。
2. Qwen 保留原生约 8 秒编码块；Audio Smith 在后台使用 32 秒滑动精修窗口。25% overlap 自动得到 8 秒重叠和 24 秒步长，界面仍只显示波形。
3. 超出活动 overlap 的前文在内部封存。松开快捷键后只解码最后的尾部窗口；若窗口拼接置信度不足，则安全回退到一次整段解码。
4. 术语替换、空白和标点清理只执行一次。最终文字保留在剪贴板；只有原目标仍然有效且输入位置安全时才自动粘贴。

按 `Esc` 可取消。默认快捷键是 `Fn`，也可选择右 Option、右 Control 或右 Command；`Fn` 与 F1–F12 组合，或其他所选修饰键与任意按键组合时，会取消听写并保留原快捷键。音频与编码器状态都有边界，长会话不会被设计为持续积累无限历史。数据流、状态机、窗口策略和内存门禁见[架构文档](docs/ARCHITECTURE.md)。

## Skills

一个 Skill 就是包含标准 `SKILL.md` 的目录，不需要配套 JSON：

```markdown
---
name: aigc
description: Improve mixed Chinese and English AIGC dictation.
---

# AIGC 词汇与转写

## Dictation context

The speaker discusses LLMs, diffusion models, and video generation.

## Transcription guidance

- Preserve English technical terms inside Chinese sentences.
- Use a long rolling context and the selected Skills to disambiguate similar sounds.

## Vocabulary

- `Diffusion Models`: `diffusion models`
- `epsilon`: `艾普西龙`
```

用户 Skills 固定放在 `~/Library/Application Support/DictateAgent/Skills/<name>/SKILL.md`。本版本首次启动时会自动把一个可编辑的 `aigc/SKILL.md` 模板复制进去；用户副本优先于应用内置后备版本，保存修改后下一次听写自动生效，不需要重启应用。系统设置负责展示 Skills，菜单栏只保留快捷键、系统设置和退出三行。

初始内容只保留一个 **AIGC 词汇与转写** Skill，覆盖大语言模型、扩散架构、图像/视频生成、训练、推理，以及容易听错的框架和模型名称。用户可以直接编辑它；以后确有需要时仍可自行增加其他 Skill 目录。

除了 `Vocabulary` 以外的正文段落都会成为有长度限制的 ASR 上下文，所以 `Transcription guidance`、示例、项目背景和个人转写偏好都能影响解码；`Vocabulary` 则单独解析成标准拼写和安全别名。本次请求使用不可变快照，prompt 上限为 8,000 字符、去重术语上限为 300 个；未选择 Skill 时使用通用听写。

Skills 是文本上下文，不是可执行插件：Markdown 中的转写规则可以影响 ASR，但 Audio Smith 不会运行其中提到的代码、工具或脚本。完整说明见 [Skill 规范](docs/SKILLS.md)和[可复制示例](Examples/Skills)。

## 隐私

- 模型安装后，语音完全在本地处理。
- 音频只存在于内存中，完成或取消后释放。
- Audio Smith 不保存音频、转写历史或遥测。
- 日志不得包含音频或转写正文。
- 除模型下载和未来明确启用的更新器外，核心流程不依赖网络。

安全问题请按 [SECURITY.md](SECURITY.md) 中的方式私下报告，不要创建公开 Issue。

## 实测性能

当前开发机（M1 Pro、32GB）的记录：

| 测量项 | 结果 | 范围 |
|---|---:|---|
| Python/MLX 推理 30 秒音频 | 1.88 秒（RTF 0.063） | 离线推理测试 |
| Python 进程峰值 footprint | 4.43GB | 离线推理测试 |
| Swift Debug 加载并静音预热 | 峰值 3.40GB，稳定后 2.43GB | 仅启动阶段 |

这些结果不能替代五分钟长上下文听写或 24GB 机器的发布测试。运行时在 4.7GB 发出诊断警告，任何超过 5.0GB 的结果都会阻止二进制发布。方法、已知缺口、延迟和准确率目标在[基准文档](docs/BENCHMARKS.md)中严格分开。

## 开发

运行仓库校验和当前 20 个单元测试：

```bash
python3 scripts/validate_skills.py
python3 scripts/validate_docs.py
./scripts/test.sh
```

生成的 Xcode 工程和 `Package.resolved` 都会提交。MLXAudio Swift 固定在 commit `4266f988d170a83017d1e82e2e4654602f277f1d`。[`scripts/quantize_qwen3_asr.sh`](scripts/quantize_qwen3_asr.sh) 提供可复现的 8-bit/group-size-64 转换；Audio Smith 不使用 TorchAO FP8。

## 路线图

- 在 M1 Pro 32GB 和至少一台 24GB Apple Silicon Mac 上完成五分钟滑动窗口听写与 5GB footprint 门禁。
- 公开中文、英文和中英混说相对 BF16 的准确率对比。
- 完成辅助功能、安全输入框、多显示器、全屏、睡眠唤醒及目标应用测试。
- 完成应用图标、第三方许可证终审、Developer ID 签名、公证和可验证 DMG。

完整发布矩阵见[测试与发布门禁](docs/TESTING.md)。[发布说明](docs/PUBLISHING.md)将源码公开与未来二进制发布视为两个独立里程碑。

## 参与贡献

欢迎贡献和可复现的测试报告。创建 Issue 或 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，绝不要提交模型权重、录音、私人转写、证书或凭据。

## 许可证

Audio Smith 应用代码使用 [MIT License](LICENSE)。Qwen3-ASR 使用 Apache-2.0；MLXAudio Swift 和 MLX Swift 使用 MIT。归属和模型条款见[第三方声明](THIRD_PARTY_NOTICES.md)。
