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

Audio Smith is an early source preview, not a finished binary release. It uses Qwen3-ASR-0.6B 8-bit for pause-segmented recognition and, by default, one Qwen3-1.7B MLX 4-bit whole-transcript refinement pass. The goals are mixed Chinese/English speech, a strict 5GB memory release gate, and standard Markdown Skills for specialist terminology.

The source builds and the core unit tests pass on the development Mac. The project has not yet completed its 24GB-device, five-minute long-context, public accuracy, signing, or notarization gates. There is therefore no download button, tag, or DMG yet, and this README does not claim accuracy that the public benchmark has not established.

## Requirements

Runtime requirements:

- Apple Silicon Mac
- macOS 14 or later
- At least 24GB of physical unified memory (enforced at launch)
- Microphone and Accessibility permissions (Accessibility also enables global shortcut monitoring)
- Approximately 1.01GB in Fast mode or 1.93GB in Professional mode, plus installation headroom

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

On first launch, grant the requested permissions and let Audio Smith download and verify [Qwen3-ASR-0.6B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit). Professional mode, which is enabled by default, also installs [Qwen3-1.7B-MLX-4bit](https://huggingface.co/Qwen/Qwen3-1.7B-MLX-4bit). Automatic source selection races the manifest-verified `config.json` from Hugging Face and ModelScope; it does not use IP geolocation. Model weights are never stored in this Git repository.

The installer builds the optimized Release configuration by default, signs it, and launches the stable `/Applications/Audio Smith.app` path. The application target, executable, module, bundle identifier, support directory, and log subsystem all use the Audio Smith identity. Pass `Debug` explicitly only for development. When an Apple Development identity is available, the build script detects and applies it to the final app, including the Hardened Runtime audio-input entitlement. Test hosts use a separate `.TestHost` bundle identifier, and the installer verifies that the launched process is the `/Applications` copy. Without a development identity, signing falls back to ad hoc and macOS may require permission again after binary changes.

For development, an existing model directory can be reused:

```bash
AUDIO_SMITH_ASR_MODEL_PATH=/absolute/path/to/Qwen3-ASR-0.6B-8bit \
AUDIO_SMITH_REFINER_MODEL_PATH=/absolute/path/to/Qwen3-1.7B-MLX-4bit \
  "/Applications/Audio Smith.app/Contents/MacOS/AudioSmith"
```

## How It Works

1. Pressing the selected push-to-talk key snapshots the foreground app, mode, and selected Skills, then starts 16kHz mono capture. The overlay shows only a waveform and elapsed time, so provisional text cannot distract the speaker.
2. Qwen3-ASR-0.6B closes a phrase after about 1.2 seconds of measured silence, once that phrase contains at least 1.5 seconds of voiced audio. A 400ms boundary overlap protects phonemes. Completed phrases are decoded serially and invisibly while recording; no LLM refinement runs at that stage.
3. Brief pauses do not split a phrase. Uninterrupted speech uses a 30-second safety limit and cuts near the lowest-energy point in the final five seconds. On release, every unfinished voiced tail uses its real duration; input below the model minimum is padded only to 0.5 seconds. Empty voiced output is retried once with 250ms of trailing silence, while weak speech-overlap seams use at most a 12-second local recovery decode.
4. On release, Professional mode sends the complete stitched ASR transcript and the immutable Skill snapshot to Qwen3-1.7B exactly once. The result is accepted only after fidelity, edit-distance, number, URL, and email checks; otherwise the complete ASR text is used. Fast mode skips both the refiner and Skills.
5. Deterministic spacing and punctuation cleanup runs once. The final transcript stays on the clipboard and is pasted back only when the original target is safe and still valid.

`Esc` cancels a recording. During Professional finalization it skips the LLM and immediately falls back to the complete ASR transcript as soon as the tail is ready. The default is `Fn`; right Option, right Control, and right Command are also available. Combining `Fn` with F1–F12, or combining another selected modifier with a key, cancels dictation and leaves the original shortcut available. See [Architecture](docs/ARCHITECTURE.md) for the data flow, state machine, pause segmentation, and memory gates.

## Skills

A Skill is a folder containing one standard `SKILL.md`; no companion JSON is required:

```markdown
---
name: aigc
description: Improve mixed Chinese and English AIGC dictation.
---

# AIGC Pronunciation Dictionary

## Pronunciation dictionary

| Canonical spelling | Spoken form or common ASR error |
|---|---|
| Qwen-Image-Edit | 千问 Image Edit |
| token | 偷啃 |
```

User Skills live at `~/Library/Application Support/AudioSmith/Skills/<name>/SKILL.md`. On the first launch of this version, Audio Smith copies one editable `aigc/SKILL.md` starter into that directory. The user copy overrides the bundled fallback, and edits are discovered before the next dictation without restarting the app. System Settings shows discovered Skills; the menu-bar menu stays limited to shortcut selection, System Settings, and Quit.

The single starter Skill is **AIGC Pronunciation Dictionary**. Its compact tables map canonical spellings to spoken forms or common ASR errors for LLMs, diffusion architectures, image/video generation, training, inference, and model names. Users can edit the tables directly or add their own Skill directories later.

Professional mode parses bounded guidance and pronunciation tables, then captures all selected Skills in one immutable request snapshot. The snapshot never enters ASR; it is supplied only to the single whole-transcript 1.7B pass after release. Pronunciations are contextual hints rather than unconditional replacements. At most 300 unique terms and 8,000 prompt characters are active. Fast mode ignores Skills while preserving the user's checkboxes.

Skills are terminology data, not executable plugins. Audio Smith never runs code, tools, scripts, or linked resources referenced by a Skill. See the [complete Skill specification](docs/SKILLS.md) and the [copyable examples](Examples/Skills).

## Privacy

- Speech is processed locally after model installation.
- Audio remains in memory and is released after completion or cancellation.
- Audio Smith does not store audio, transcript history, or telemetry.
- Logs must not contain audio or transcript text.
- Apart from model download and a future explicitly enabled updater, the core workflow does not require a network connection.

Please report security issues through the process in [SECURITY.md](SECURITY.md), not a public issue.

## Measured Performance

The only published measurements predate the new dual-model path and remain a legacy 1.7B-ASR baseline on the development machine (M1 Pro, 32GB):

| Measurement | Result | Scope |
|---|---:|---|
| Python/MLX inference on 30s audio | 1.88s (RTF 0.063) | Offline inference harness |
| Python process peak footprint | 4.43GB | Offline inference harness |
| Swift Debug load + silent prewarm | 3.40GB peak, 2.43GB settled | Startup only |

They do not measure the current 0.6B ASR + 1.7B refiner configuration and cannot be used as its performance claim. The runtime warns at 4.7GB, and any result above 5.0GB blocks a binary release. Current targets and known gaps are separated in [Benchmarks](docs/BENCHMARKS.md).

## Development

Run repository validation and the current unit tests with:

```bash
python3 scripts/validate_skills.py
python3 scripts/validate_docs.py
./scripts/test.sh
```

The generated Xcode project and `Package.resolved` are committed. MLXAudio Swift is pinned to commit `4266f988d170a83017d1e82e2e4654602f277f1d`; MLX Swift LM and Swift Transformers are pinned by revision as well. The legacy conversion utility remains at [`scripts/quantize_qwen3_asr.sh`](scripts/quantize_qwen3_asr.sh). Audio Smith does not use TorchAO FP8.

## Roadmap

- Validate five-minute pause-segmented dictation and the 5GB footprint gate on M1 Pro 32GB and at least one 24GB Apple Silicon Mac.
- Publish Chinese, English, and code-switched accuracy comparisons against BF16.
- Complete accessibility, secure-field, multi-display, full-screen, sleep/wake, and target-app testing.
- Finish iconography, third-party license review, Developer ID signing, notarization, and a verified DMG.

The detailed release matrix is in [Testing and release gates](docs/TESTING.md). Source publication and future binary release remain separate milestones in [Publishing](docs/PUBLISHING.md).

## Contributing

Contributions and reproducible test reports are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request, and never commit model weights, recordings, private transcripts, certificates, or credentials.

## License

Audio Smith application code is released under the [MIT License](LICENSE). Qwen3-ASR is Apache-2.0; MLXAudio Swift and MLX Swift are MIT. See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for attribution and model terms.
