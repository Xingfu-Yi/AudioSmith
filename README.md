# Audio Smith

[简体中文](README.zh-CN.md)

[![CI](https://github.com/Xingfu-Yi/AudioSmith/actions/workflows/ci.yml/badge.svg)](https://github.com/Xingfu-Yi/AudioSmith/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-111111?logo=apple)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Developer Preview](https://img.shields.io/badge/status-Developer%20Preview-orange)

**Private, on-device, skill-aware dictation for Apple Silicon.** Hold the configurable push-to-talk key (`Fn` by default) while a discreet waveform confirms capture. Release it to transcribe the complete utterance with long-range context and paste the result into the app you were using.

> A real, privacy-reviewed workflow recording will be added before the first binary release. This source preview intentionally does not use a fabricated UI demo.

## Developer Preview

Audio Smith is an early source preview, not a finished binary release. It is designed around Qwen3-ASR-1.7B, MLX 8-bit affine weights, mixed Chinese/English speech, a strict 5GB memory release gate, and standard Markdown Skills for specialist terminology.

The source builds and the core unit tests pass on the development Mac. The project has not yet completed its 24GB-device, five-minute long-context, public accuracy, signing, or notarization gates. There is therefore no download button, tag, or DMG yet, and this README does not claim accuracy that the public benchmark has not established.

## Requirements

Runtime requirements:

- Apple Silicon Mac
- macOS 14 or later
- At least 24GB of physical unified memory (enforced at launch)
- Microphone, Input Monitoring, and Accessibility permissions
- Approximately 2.46GB for the pinned model, plus installation headroom

16GB Macs are intentionally unsupported in v1; the app does not offer a lower-precision fallback.

Verified build environment:

- Xcode 26.6 with Swift 6.3
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Xcode Metal Toolchain

These are the versions verified by the project, not claimed minimum build-tool versions.

## Quick Start from Source

```bash
git clone git@github.com:Xingfu-Yi/AudioSmith.git
cd AudioSmith
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
./scripts/install_dev.sh
```

On first launch, grant the requested permissions and let Audio Smith download and verify the pinned [mlx-community/Qwen3-ASR-1.7B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit) model. The download is approximately 2.46GB. Model weights are never stored in this Git repository.

The installer builds, signs, and launches the stable `/Applications/DictateAgent.app` path. The `AudioSmith` repository keeps this historical internal app path, bundle identifier, and data directory so existing models, Skills, and macOS permissions do not require migration. When an Apple Development identity is available, the build script detects and applies it to the final app, including the Hardened Runtime audio-input entitlement. Test hosts use a separate `.TestHost` bundle identifier, and the installer verifies that the launched process is the `/Applications` copy. Without a development identity, signing falls back to ad hoc and macOS may require permission again after binary changes.

For development, an existing model directory can be reused:

```bash
DICTATE_AGENT_MODEL_PATH=/absolute/path/to/Qwen3-ASR-1.7B-8bit \
  /Applications/DictateAgent.app/Contents/MacOS/DictateAgent
```

## How It Works

1. Pressing the selected push-to-talk key snapshots the foreground app and all selected Skills, then starts 16kHz mono capture. The overlay shows only a waveform and elapsed time, so provisional text cannot distract the speaker.
2. Qwen keeps its native approximately eight-second encoder blocks. Audio Smith decodes a 16-second rolling refinement window in the background. Its nominal 25% overlap gives a 12-second stride, but completed windows may advance to a nearby punctuation-guided acoustic pause in the latter half while retaining at least two seconds of overlap. If no reliable pause exists, the stride remains exactly 12 seconds. Only the waveform is shown.
3. Requests up to 16 seconds run one whole-request final pass. Extremely short inputs receive trailing silence only up to the model's 0.5-second minimum; their real duration is unchanged. Longer requests decode only the final overlapping tail when the key is released, while a low-confidence seam falls back to one safe whole-utterance pass.
4. Deterministic terminology and punctuation cleanup runs once. The final transcript stays on the clipboard and is pasted back only when the original target is safe and still valid.

`Esc` cancels a recording. The default is `Fn`; right Option, right Control, and right Command are also available. Combining `Fn` with F1–F12, or combining another selected modifier with a key, cancels dictation and leaves the original shortcut available. Audio and encoder state are bounded so a longer session does not intentionally accumulate an unbounded history. See [Architecture](docs/ARCHITECTURE.md) for the data flow, state machine, windowing, and memory gates.

## Skills

A Skill is a folder containing one standard `SKILL.md`; no companion JSON is required:

```markdown
---
name: aigc
description: Improve mixed Chinese and English AIGC dictation.
---

# AIGC Vocabulary and Transcription

## Dictation context

The speaker discusses LLMs, diffusion models, and video generation.

## Transcription guidance

- Preserve English technical terms inside Chinese sentences.
- Use a long rolling context and the selected Skills to disambiguate similar sounds.

## Vocabulary

- `Diffusion Models`: `diffusion models`
- `epsilon`: `艾普西龙`
```

User Skills live at `~/Library/Application Support/DictateAgent/Skills/<name>/SKILL.md`. On the first launch of this version, Audio Smith copies one editable `aigc/SKILL.md` starter into that directory. The user copy overrides the bundled fallback, and edits are discovered before the next dictation without restarting the app. System Settings shows discovered Skills; the menu-bar menu stays limited to shortcut selection, System Settings, and Quit.

The single starter Skill is **AIGC Vocabulary and Transcription**. It contains ASR-oriented vocabulary for LLMs, diffusion architectures, image/video generation, training, inference, and commonly misheard framework or model names. Users can keep it simple, edit it directly, or add their own Skill directories later.

All body sections except `Vocabulary` become bounded ASR context, so `Transcription guidance`, examples, project background, and personal style preferences can influence decoding. `Vocabulary` is parsed separately into preferred spellings and safe aliases. Selected content is captured in one immutable request snapshot capped at 8,000 prompt characters and 300 unique terms; selecting nothing uses general dictation.

Skills are text context, not executable plugins: Markdown guidance can bias ASR output, but Audio Smith never runs code, tools, or scripts referenced by a Skill. See the [complete Skill specification](docs/SKILLS.md) and the [copyable examples](Examples/Skills).

## Privacy

- Speech is processed locally after model installation.
- Audio remains in memory and is released after completion or cancellation.
- Audio Smith does not store audio, transcript history, or telemetry.
- Logs must not contain audio or transcript text.
- Apart from model download and a future explicitly enabled updater, the core workflow does not require a network connection.

Please report security issues through the process in [SECURITY.md](SECURITY.md), not a public issue.

## Measured Performance

Current measurements on the development machine (M1 Pro, 32GB):

| Measurement | Result | Scope |
|---|---:|---|
| Python/MLX inference on 30s audio | 1.88s (RTF 0.063) | Offline inference harness |
| Python process peak footprint | 4.43GB | Offline inference harness |
| Swift Debug load + silent prewarm | 3.40GB peak, 2.43GB settled | Startup only |

These measurements do not prove the five-minute long-context or 24GB-device release gates. The runtime warns at 4.7GB, and any result above 5.0GB blocks a binary release. Methodology, known gaps, and latency/accuracy targets are separated in [Benchmarks](docs/BENCHMARKS.md).

## Development

Run repository validation and the 20 current unit tests with:

```bash
python3 scripts/validate_skills.py
python3 scripts/validate_docs.py
./scripts/test.sh
```

The generated Xcode project and `Package.resolved` are committed. MLXAudio Swift is pinned to commit `4266f988d170a83017d1e82e2e4654602f277f1d`. A reproducible 8-bit/group-size-64 conversion script is available at [`scripts/quantize_qwen3_asr.sh`](scripts/quantize_qwen3_asr.sh); Audio Smith does not use TorchAO FP8.

## Roadmap

- Validate five-minute rolling-window dictation and the 5GB footprint gate on M1 Pro 32GB and at least one 24GB Apple Silicon Mac.
- Publish Chinese, English, and code-switched accuracy comparisons against BF16.
- Complete accessibility, secure-field, multi-display, full-screen, sleep/wake, and target-app testing.
- Finish iconography, third-party license review, Developer ID signing, notarization, and a verified DMG.

The detailed release matrix is in [Testing and release gates](docs/TESTING.md). Source publication and future binary release remain separate milestones in [Publishing](docs/PUBLISHING.md).

## Contributing

Contributions and reproducible test reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request, and never commit model weights, recordings, private transcripts, certificates, or credentials.

## License

Audio Smith application code is released under the [MIT License](LICENSE). Qwen3-ASR is Apache-2.0; MLXAudio Swift and MLX Swift are MIT. See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for attribution and model terms.
