# Changelog

All notable changes to Audio Smith will be documented here. The project follows [Semantic Versioning](https://semver.org/) for Git tags; the macOS bundle uses the numeric core version.

## [Unreleased]

### Changed

- Replaced the 1.7B ASR-only path with Qwen3-ASR-0.6B 8-bit recognition plus an optional Qwen3-1.7B MLX 4-bit whole-transcript refiner.
- Added persistent Professional and Fast modes. Professional uses one post-release refinement with all selected Skills; Fast unloads the refiner and performs generic cleanup only.
- Unified the application target, executable, module, bundle identifier, support directory, log subsystem, documentation, and installation path under the Audio Smith identity.
- Replaced the legacy 1.7B ASR override key with `AUDIO_SMITH_ASR_MODEL_PATH` so old development environments cannot be mistaken for the new 0.6B model.
- Isolated the Xcode unit-test host under a `.TestHost` bundle identifier and made the development installer verify the launched `/Applications` executable.
- Set ASR to eight-second windows with nominal two-second overlap, six-second stride, pause-aware boundaries, and at most twelve-second local seam repair.
- Made 0.5–8 second audio use its true length; shorter voiced input pads only to 0.5 seconds and an empty result receives one 250ms-silence retry.
- Added a continuously time-driven Professional-refinement spinner and `Esc` fallback to complete ASR text.
- Removed the rectangular AppKit window shadow and translucent material backing from the recording overlay so only the solid capsule is visible.
- Added strict refiner candidate validation for length, normalized edit distance, protocol output, numbers, URLs, and email addresses.

### Added

- Native Apple Silicon menu-bar application with a configurable hold-to-dictate key and a non-activating waveform-only overlay.
- Branded menu-bar header with three concise actions for shortcut selection, System Settings, and Quit.
- Local Qwen3-ASR-0.6B MLX 8-bit inference and Qwen3-1.7B MLX 4-bit professional refinement.
- Resumable, revision-pinned and SHA-256-verified installation from automatically selected or manually chosen ModelScope and Hugging Face mirrors.
- Standard single-file `SKILL.md` support with bounded Markdown guidance, parsed vocabulary aliases, and optional multi-selection for advanced users.
- One focused, editable AIGC starter Skill with classified LLM/Transformer, Diffusion, Flow Matching, DiT, and runtime domain maps, plus context-aware Mandarin pronunciation guidance and a copyable medical-dictation example.
- Memory diagnostics, privacy safeguards, unit tests, CI and notarized DMG release automation.

## [0.1.0] - Unreleased

First public development release. It must not be tagged until every required gate in `docs/TESTING.md` has passed.
