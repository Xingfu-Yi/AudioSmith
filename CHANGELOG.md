# Changelog

All notable changes to Audio Smith are documented here. The project follows [Semantic Versioning](https://semver.org/) for Git tags; the macOS bundle uses the numeric core version.

## [Unreleased]

The current source preview builds Audio Smith `0.1.7 (8)`. A downloadable DMG will be published only after Developer ID signing and Apple notarization are configured and the binary release gates pass.

### Changed

- Unified the application, source tree, test target, bundle identity, support directory, documentation and installation path under the Audio Smith name.
- Simplified inference to one resident `Qwen3-ASR-1.7B-8bit` MLX model; removed the 0.6B ASR path, the separate text refiner and the Professional/Fast mode split.
- Replaced fixed short-window transcription with pause-aware segmentation: 1.2 seconds of confirmed silence closes a voiced phrase, 400 milliseconds of audio overlap protects boundaries and 30 seconds is the safety ceiling.
- Made short utterances use their real duration. Voiced input below 0.5 seconds is padded only to the model minimum, and an empty result receives one 250-millisecond tail-silence retry.
- Reduced Skill input to a compact, bounded pronunciation dictionary. At most 40 selected canonical terms and spoken forms enter each ASR request; free-form Skill documentation remains local.
- Finalization now completes only the remaining ASR phrase, stitches the full transcript, applies deterministic cleanup and pastes it. No second LLM pass runs after the shortcut is released.
- Added exact migration for the retired `qwen3-asr-0.6b-8bit` and `qwen3-1.7b-4bit-refiner` caches without changing user settings or Skills.
- Kept the recording overlay waveform-only and the finalization state as a continuously animated progress ring in a single solid capsule.
- Made the recording capsule reliably join the active application's full-screen Space, reassert its ordering during Space transitions, and follow the focused window across multi-display layouts.
- Made the capsule temporarily draggable without activating Audio Smith. A new request returns it to bottom center, while in-request Space refreshes preserve the user's temporary position.
- Removed both window and SwiftUI shadows so the transparent panel does not produce a clipped gray rectangle over light content.
- Stabilized macOS permission identity by installing and launching only `/Applications/Audio Smith.app`, and made the Settings window return to the front after opening System Settings.

### Added

- Native Apple Silicon menu-bar app with configurable hold-to-dictate shortcuts, a non-activating overlay, automatic clipboard insertion and secure-field fallback.
- Revision-pinned, SHA-256-verified and resumable model installation with automatic or manual ModelScope/Hugging Face source selection.
- Standard single-file `SKILL.md` support, multi-selection and an editable AIGC pronunciation starter Skill.
- Offline-first privacy safeguards, memory diagnostics, 58 unit tests, documentation validation, CI and signed/notarized DMG release automation.

### Release status

- Source, tests and arm64 Release builds are ready for a public Developer Preview.
- Model weights, audio, transcripts, certificates and secrets are never committed to Git.
- The GitHub DMG workflow remains intentionally blocked until its Developer ID and notarization secrets are configured.
