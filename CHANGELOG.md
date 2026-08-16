# Changelog

All notable changes to Audio Smith will be documented here. The project follows [Semantic Versioning](https://semver.org/) for Git tags; the macOS bundle uses the numeric core version.

## [Unreleased]

### Changed

- Renamed the user-facing product from Dictate Agent to Audio Smith while preserving the existing bundle identity and data paths for permission compatibility.
- Isolated the Xcode unit-test host under a `.TestHost` bundle identifier and made the development installer verify the launched `/Applications` executable.

### Added

- Native Apple Silicon menu-bar application with a configurable hold-to-dictate key and a non-activating waveform-only overlay.
- Branded menu-bar header with three concise actions for shortcut selection, System Settings, and Quit.
- Local Qwen3-ASR-1.7B MLX 8-bit inference with an 8-second native encoder window, a 32-second rolling refinement window, derived 25% overlap, and tail-only finalization after shortcut release.
- Resumable, revision-pinned and SHA-256-verified model installation.
- Standard single-file `SKILL.md` support with bounded Markdown guidance, parsed vocabulary aliases, and optional multi-selection for advanced users.
- One focused, editable AIGC starter Skill with classified LLM/Transformer, Diffusion, Flow Matching, DiT, and runtime domain maps, plus context-aware Mandarin pronunciation guidance and a copyable medical-dictation example.
- Memory diagnostics, privacy safeguards, unit tests, CI and notarized DMG release automation.

## [0.1.0] - Unreleased

First public development release. It must not be tagged until every required gate in `docs/TESTING.md` has passed.
