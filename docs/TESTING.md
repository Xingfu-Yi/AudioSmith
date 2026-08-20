# Testing and release gates

## Functional matrix

- default Fn and alternate shortcut press/release, persistence, accidental short press, chord pass-through
- recording and finalizing `Esc` cancellation
- sleep/wake, microphone changes, displays, full-screen apps, and Spaces
- overlay appears in another application's full-screen Space and survives rapid consecutive requests without a stale hide race
- overlay targets the focused window's display, preserves a temporary drag during the request, resets on the next request, and recovers from an off-screen frame
- overlay remains a single black capsule over light content, with no rectangular window or clipped SwiftUI shadow
- Notes, Chrome, VS Code, Terminal, WeChat, and secure fields
- permission denial, revocation, and re-grant
- Skill selection and edits before, during, and after a request

## ASR invariants

- recording displays only waveform and elapsed time
- Qwen3-ASR-1.7B closes normal segments only after 1.2 seconds of measured silence and at least 1.5 seconds of voiced audio
- pauses shorter than 1.2 seconds do not split a phrase; natural boundaries retain 400ms of guard overlap
- uninterrupted speech uses a 30-second safety limit and the lowest-energy run in the final five seconds
- every unfinished voiced tail uses its true length; input below the model minimum pads only to 0.5 seconds
- releasing during silence after a completed phrase does not decode or duplicate a silent tail
- voiced empty output receives exactly one retry with 250ms trailing silence
- all MLX passes are serialized and the audio callback never performs inference
- natural-pause clauses join directly; safety-limit overlap seams neither duplicate nor lose words, and repair audio is capped at 12 seconds
- release never re-decodes the complete recording and five-minute sessions do not grow process footprint monotonically
- final cleanup cannot summarize, translate, or expand speech because it is deterministic and does not call a text LLM

## Model installation

- Auto mode races manifest-verified `config.json` from ModelScope and Hugging Face without geolocation
- manual ModelScope and Hugging Face selection
- network timeout, three-failure source switch, Range resume, and partial-file discard on switch
- shared file-size/SHA-256 manifest, checksum failure, corrupt quarantine, and atomic installation
- insufficient disk, revision upgrade, exact retired-cache migration, and fully offline startup after installation

Run the fast manifest-backed mirror probe during development:

```bash
python3 scripts/verify_model_mirrors.py --probe-only
```

Before a binary release, stream and hash every file from both mirrors. This downloads the bytes for verification but does not retain another model copy:

```bash
python3 scripts/verify_model_mirrors.py
```

## Skills

- discover standard single-file `SKILL.md` directories and seed the editable AIGC starter
- persist multi-selection and combine selected Skills deterministically
- enforce 4,000 stored characters per Skill and 300 deduplicated terms in the immutable snapshot
- send at most 40 pronunciation entries and 1,000 characters of compact context to ASR
- exclude free-form Markdown from model input
- rescan before every request and keep its snapshot immutable
- never execute code or resources mentioned by a Skill

## Performance gates

Test on an M1 Pro 32GB and at least one 24GB Apple Silicon Mac:

- 1–8s release-to-paste p95 ≤2 seconds
- 30s release-to-paste p95 ≤3 seconds
- five-minute request finishes from its final tail without a whole-recording pass
- post-warm waveform appearance p95 ≤150ms
- process footprint ≤5.0GB

4.7GB is the diagnostic warning. More than 5.0GB blocks binary release.

Generate the arm64 optimized application used for release-gate inspection:

```bash
./scripts/build.sh Release
```

## Accuracy gates

Maintain Chinese, English, and code-switched sets. The 1.7B 8-bit mixed token error rate may be at most 0.5 percentage points worse than BF16. Compact AIGC pronunciation context must improve terminology accuracy without degrading the general set by more than 0.2 percentage points.

## Privacy checks

- run the core flow offline after model installation
- inspect logs for transcript or audio content
- verify no audio, transcript history, telemetry, certificate, or secret files are created
