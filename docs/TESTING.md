# Testing and release gates

## Functional matrix

- default Fn and alternate shortcut press/release, persistence, accidental short press, chord pass-through
- recording `Esc` cancellation and Professional-finalizing `Esc` fallback
- sleep/wake, microphone changes, displays, full-screen apps, and Spaces
- Notes, Chrome, VS Code, Terminal, WeChat, and secure fields
- permission denial, revocation, and re-grant
- Professional/Fast switching before, during, and after a request

## ASR invariants

- recording displays only waveform and elapsed time
- 0.6B ASR closes normal segments only after 1.2 seconds of measured silence and at least 1.5 seconds of voiced audio
- pauses shorter than 1.2 seconds do not split a phrase; natural boundaries retain 400ms of guard overlap
- uninterrupted speech uses a 30-second safety limit and the lowest-energy run in the final five seconds
- every unfinished voiced tail uses its true length; input below the model minimum pads only to 0.5 seconds
- releasing during silence after a completed phrase does not decode or duplicate a silent tail
- voiced empty output receives exactly one retry with 250ms trailing silence
- all MLX passes are serialized and the audio callback never performs inference
- natural-pause clauses join directly; safety-limit overlap seams neither duplicate nor lose words, and repair audio is capped at 12 seconds
- five-minute sessions do not grow process footprint monotonically

## Professional refinement invariants

- LLM calls during recording: zero
- LLM calls per completed Professional request: exactly one
- Fast requests never load or call the refiner and never apply Skills
- the one prompt contains the complete ASR transcript, bounded context, and all selected Skill vocabulary
- thinking is disabled and output is limited by the documented token and timeout policy
- empty, protocol-bearing, over-edited, summarized, expanded, or protected-data-changing candidates fall back to complete ASR text
- mode and Skill snapshots remain immutable while settings changes affect only the next request
- progress ring appears within 100ms of key release and continues independently of inference callbacks

## Model installation

- Auto mode races manifest-verified `config.json` from ModelScope and Hugging Face without geolocation
- manual ModelScope and Hugging Face selection
- network timeout, three-failure source switch, Range resume, and partial-file discard on switch
- shared file-size/SHA-256 manifest, checksum failure, corrupt quarantine, and atomic installation
- insufficient disk, revision upgrade, and fully offline startup after installation

Run the fast manifest-backed mirror probe during development:

```bash
python3 scripts/verify_model_mirrors.py --probe-only
```

Before a binary release, stream and hash every file from both mirrors. This
downloads the bytes for verification but does not retain another model copy:

```bash
python3 scripts/verify_model_mirrors.py
```

## Skills

- discover standard single-file `SKILL.md` directories and seed the editable AIGC starter
- persist multi-selection and combine selected Skills deterministically
- enforce 4,000 characters per Skill, 8,000 combined prompt characters, and 300 deduplicated terms
- rescan before every request and keep its snapshot immutable
- never execute code or resources mentioned by a Skill
- send Skills only to Professional whole-transcript refinement, never ASR or Fast mode

## Performance gates

Test on an M1 Pro 32GB and at least one 24GB Apple Silicon Mac:

- Fast 1–8s release-to-paste p95 ≤1 second
- Professional 1–8s release-to-paste p95 ≤2 seconds
- Professional 30s release-to-paste p95 ≤5 seconds
- five-minute Professional refinement completes or safely falls back within 45 seconds
- post-warm waveform appearance p95 ≤150ms
- Professional process footprint ≤5.0GB; Fast retains no 1.7B model memory

4.7GB is the diagnostic warning. More than 5.0GB blocks binary release.

Generate the arm64 optimized application used for release-gate inspection:

```bash
./scripts/build.sh Release
```

## Accuracy gates

Maintain Chinese, English, and code-switched sets. Professional mixed token error rate may be at most 0.3 percentage points worse than the previous 1.7B-ASR baseline; AIGC term accuracy must improve by at least five percentage points; semantic expansion, summarization, translation, and number mutation must be zero.

## Privacy checks

- run the core flow offline after model installation
- inspect logs for transcript or audio content
- verify no audio, transcript history, telemetry, certificate, or secret files are created
