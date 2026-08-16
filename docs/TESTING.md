# Testing and release gates

## Functional matrix

- default Fn and every alternate shortcut press/release, persistence, accidental short press, Esc cancel, and shortcut-chord pass-through
- sleep/wake and microphone-device changes
- multiple displays, full-screen applications, Spaces
- Notes, Chrome, VS Code, Terminal, WeChat and secure text fields
- permission denial, revocation and re-grant

## Rolling-inference invariants

- recording shows only waveform and elapsed time; no transcript is emitted before shortcut release
- the base encoder window is 8 seconds and the default refinement window is 32 seconds
- overlap is derived as 25% of the refinement window; the default is 8 seconds with a 24-second stride
- completed checkpoints run serially and never block microphone capture on the audio callback
- final text has no duplicate or lost content across rolling-window seams
- a low-confidence overlap seam falls back to a safe whole-utterance pass
- five-minute sessions do not show monotonically growing footprint
- cancellation releases captured in-memory audio

## Model installation

- network interruption and HTTP Range resume
- checksum failure and corrupt-install quarantine
- insufficient disk space
- revision upgrade and atomic install
- offline launch after a verified install

## Skills

- discover a single standard `SKILL.md` without companion JSON
- seed one editable AIGC starter into an empty user Skills directory without overwriting user edits
- reject missing frontmatter, invalid names, folder-name mismatches and more than 200 terms
- pass non-Vocabulary Markdown sections as bounded ASR context and parse `Vocabulary` separately without executing code or tools
- display every discovered Skill and persist any valid multi-selection
- combine selections deterministically, deduplicate terms, and preserve the 8,000-character / 300-term request bounds
- rescan before every dictation request so saved changes apply without restart
- keep the request-start Skill snapshot stable if its file changes during recording

## Performance gates

Test on an M1 Pro 32GB and at least one 24GB Apple Silicon Mac:

- macOS peak physical footprint ≤ 5.0GB
- post-warm waveform appearance p95 ≤ 150ms
- shortcut release to paste p95 ≤ 2.0 seconds for a 30-second request in the General Skill
- real-time factor ≤ 0.25

4.7GB is the diagnostic warning threshold. A result above 5.0GB blocks release.

## Accuracy gates

Maintain Chinese, English and code-switched dictation sets. Compare the 8-bit checkpoint with BF16 using the same greedy configuration. Mixed token error rate may increase by no more than 0.5 percentage points. Publish the hardware, corpus description, model revisions, quantization parameters and raw aggregate results.

## Privacy checks

- run the complete core flow with network disabled after model installation
- inspect logs for transcript or audio content
- verify no audio, transcript history or telemetry files are created
