# Architecture

Audio Smith is a menu-bar macOS application. AppKit owns global keyboard monitoring, the non-activating overlay, target restoration, and paste safety; AVAudioEngine captures audio; MLXAudio Swift runs Qwen3-ASR; MLX Swift LM runs the optional text refiner; SwiftUI provides settings and status views.

## Request data flow

```mermaid
flowchart LR
    Down["Push-to-talk down"] --> Snap["Target + mode + selected Skills snapshot"]
    Snap --> Capture["16kHz mono Float32 capture"]
    Capture --> Panel["Waveform-only NSPanel"]
    Capture --> ASR["0.6B ASR: 8s windows, 2s overlap"]
    ASR --> Ledger["Whole raw transcript ledger"]
    Up["Push-to-talk up"] --> Tail["Finish real-length ASR tail"]
    ASR --> Tail
    Tail --> Mode{"Request snapshot mode"}
    Mode -->|"Fast"| Clean["Generic deterministic cleanup"]
    Mode -->|"Professional"| LLM["One whole-text 1.7B refinement"]
    Snap --> LLM
    LLM --> Validate["Fidelity + protected-data validation"]
    Validate -->|"accepted"| Clean
    Validate -->|"failure / timeout / Esc"| Raw["Complete ASR fallback"]
    Raw --> Clean
    Clean --> Paste["Clipboard + safe paste to original target"]
```

The panel never shows provisional text. Release changes the state to `finalizing` before any model await, freezes and dims the waveform, and starts a time-driven progress ring. Professional mode labels the operation and allows `Esc` to bypass the LLM.

## State machine

```text
downloading → loading → ready → recording → finalizing → ready
     │           │         │          │            │
     └───────────┴─────────┴──────────┴────────────┴──→ error
```

- `downloading`: missing model files are fetched, verified, and atomically installed.
- `loading`: required models are loaded and silently prewarmed in series.
- `ready`: a request can snapshot the current mode and Skills.
- `recording`: only 0.6B ASR work runs; no text LLM is invoked.
- `finalizing`: the ASR tail completes, then Professional mode makes exactly one full-transcript LLM request. Fast mode goes directly to cleanup.
- `error`: permission, model, microphone, inference, or disk failures are surfaced without persisting speech.

Changing settings during a request does not mutate its snapshot. Turning Professional mode off unloads the refiner after the current request. Re-enabling it downloads, verifies, loads, and prewarms the model before the app returns to `ready`.

## Shortcut, cancellation, and paste safety

An event tap observes the selected physical modifier key. `Fn` is the default; right Option, right Control, and right Command persist across launches. Function-key or modifier chords cancel dictation without consuming the original shortcut.

During recording, `Esc` cancels the entire request. During Professional finalization it marks the generation result unusable and pastes the complete ASR fallback as soon as the ASR tail is available; a late model result is ignored through the request UUID. Secure fields and invalid targets never receive simulated paste, but the final text remains on the clipboard.

## ASR windows and short audio

The ASR model is the pinned `mlx-community/Qwen3-ASR-0.6B-8bit`. Audio is processed in eight-second windows with a nominal two-second overlap and six-second stride. After a completed window, punctuation provides only a coarse semantic hint. The actual boundary is selected from a measured low-energy pause of at least 120ms in the 50–87.5% search region near the 75% checkpoint. If no defensible pause exists, the stride remains exactly six seconds.

All MLX ASR calls run serially on a dedicated queue. The realtime microphone callback only appends samples. Adjacent hypotheses use lexical longest-suffix/longest-prefix stitching that ignores case, spacing, and punctuation. A recovery decode is bounded to at most 12 seconds; the application does not re-run a complete long recording merely because a local seam is weak.

For 0.5–8 seconds, ASR receives the true request length. A shorter voiced request is padded with trailing zeros only to the model's 0.5-second minimum. If voiced audio produces empty text, one and only one retry appends 250ms of silence. Pure silence is rejected without inference. Reported duration and stitch locations always use unpadded audio time.

The five-minute request limit bounds capture. At 16kHz Float32, retaining a five-minute waveform for tail and local recovery is about 19.2MB. It is released after completion or cancellation.

## Whole-transcript professional refinement

The optional refiner is the pinned `Qwen/Qwen3-1.7B-MLX-4bit`. It is never called for a segment or during recording. After ASR finishes, the complete raw transcript and the request's Skill snapshot are submitted once with thinking disabled and strict copy-editing instructions: only homophones, terminology, capitalization, duplicate fragments, spacing, and punctuation may change.

Input is limited to 24K tokens while reserving at least 8K tokens for output. Skill context is trimmed before transcript text; if the complete transcript itself cannot fit, the request safely uses the ASR fallback. The output budget is `original tokens × 1.25 + 32`, capped at 8K. Timeout is `2 seconds + budget / 20 tokens/s`, clamped to 3–45 seconds.

The candidate must be nonempty and free of thinking, role, and protocol text; stay within the configured length and normalized edit-distance bounds; and preserve every number sequence, URL, and email address. Any exception, timeout, cancellation, or validation failure uses the complete ASR text. The refiner is not allowed to answer, summarize, translate, or expand the speaker.

## Skill snapshot

Before every accepted key press, Audio Smith rescans:

```text
~/Library/Application Support/AudioSmith/Skills/<name>/SKILL.md
```

The checked set is sorted, deduplicated, bounded, and captured as one immutable `DomainSkill`. Up to 300 preferred terms and 8,000 prompt characters are available. Skills never enter ASR. They enter only the single Professional-mode refinement prompt and the final safe alias cleanup. Fast mode uses the General snapshot and ignores domain replacements. Skill documents are data and never execute code, tools, scripts, or linked resources. See [Skills](SKILLS.md).

## Model installation and source selection

Separate manifests pin the ASR and refiner repositories, immutable Hugging Face revisions, file sizes, and SHA-256 digests. The same content manifest validates ModelScope. Automatic mode races only the two mirrors' small `config.json` files and accepts the first response whose size and SHA-256 match; no third-party IP-location service is used.

Downloads support HTTP Range resume. Three consecutive failures switch to the other mirror; already verified files remain, while the current incomplete file is discarded before switching. Installation uses a staging directory and atomic move. Once installed, startup and dictation do not probe the network.

## MLX serialization and memory gate

ASR checkpoints, ASR finalization, refiner loading, prewarm, and generation are sequenced so the two resident models do not infer concurrently. Professional mode keeps both models resident for warm first use. Fast mode unloads the 1.7B container and clears eligible MLX caches while leaving verified weights on disk.

- 4.7GB process footprint: runtime diagnostic warning
- 5.0GB process footprint: Professional-mode binary-release blocker

These limits cover the complete process. Passing requires live five-minute testing on the M1 Pro 32GB development machine and at least one 24GB Apple Silicon Mac. Current evidence is documented in [Benchmarks](BENCHMARKS.md).
