# Benchmarks

This document keeps observed measurements separate from product configuration and release targets. A result is not promoted to a release claim until its hardware, model revision, workload, and measurement method are recorded here.

## Test subject

- Application: Audio Smith Developer Preview
- Model: `mlx-community/Qwen3-ASR-1.7B-8bit`
- Model revision: `a8379a2e2f9e313c9292cdf1af4055ab56d50d55`
- Quantization: MLX 8-bit affine, group size 64
- Decode policy: greedy
- Development hardware: M1 Pro with 32GB unified memory

Audio Smith does not use TorchAO FP8. The repository contains a reproducible conversion script but does not contain model weights.

## Observed results

| Date/status | Runtime and workload | Elapsed or latency | Peak physical footprint | What this proves |
|---|---|---:|---:|---|
| Measured on development machine | Python/MLX, one 30-second audio input | 1.88s; RTF 0.063 | 4.43GB | The pinned 8-bit model can run substantially faster than real time in this offline harness. |
| Measured on development machine | Swift Debug app, model load followed by silent prewarm | Not a streaming latency test | 3.40GB peak; 2.43GB settled | The Swift app can load and prewarm the model below the 5GB gate on this machine. |

The two rows use different processes and workloads. Their memory values must not be combined or treated as a complete live-dictation result.

## Product configuration, not measurements

- Capture UI: waveform and elapsed time only; no provisional transcript
- Base encoder window: Qwen's native approximately eight-second blocks
- Refinement window: 32 seconds with a derived 25% overlap (8-second overlap, 24-second stride)
- During capture: serial background checkpoints over the rolling window; the UI remains waveform-only
- Release-time transcription: only the final overlapping tail window, unless a low-confidence seam requires the safe full-pass fallback
- Combined Skill snapshot: at most 8,000 prompt characters and 300 unique preferred terms
- Session limit: 5 minutes
- Runtime diagnostic warning: 4.7GB physical footprint
- Binary-release blocker: more than 5.0GB physical footprint

These values describe the current configuration, not measured end-to-end p95 latency claims. The design intentionally trades live captions for a calmer recording UI while moving most long-request decoding into bounded background checkpoints. Release-to-paste latency must be measured again before a binary release.

## Binary-release targets

The following remain gates, not achieved results:

| Gate | Target | Required coverage |
|---|---:|---|
| Peak physical footprint | ≤5.0GB | M1 Pro 32GB and at least one 24GB Apple Silicon Mac, including a five-minute live session |
| Waveform visible after shortcut press | p95 ≤150ms | Real microphone input and overlay rendering |
| Shortcut release to paste | p95 ≤2.0s for 30s speech | General Skill and supported target applications |
| Real-time factor | ≤0.25 | Recorded Chinese, English, and mixed-language sets |
| 8-bit mixed token error rate delta versus BF16 | ≤0.5 percentage points | Same corpus and greedy-decode configuration |

## Accuracy protocol

The public accuracy report must include three separately summarized sets: Chinese, English, and Chinese/English code switching. It must publish:

- hardware and macOS version;
- microphone or source-audio description;
- corpus provenance and licensing description;
- BF16 and 8-bit model revisions;
- quantization mode, bit width, and group size;
- identical decoding parameters;
- aggregate error metrics and raw per-utterance results that contain no private speech.

No “high accuracy” claim should be made before these results are available. A terminology Skill comparison should be reported separately from the base-model comparison because deterministic alias replacement changes the final text.

## Streaming and memory protocol

1. Launch after a verified model installation and wait for silent prewarm to finish.
2. Record baseline physical footprint after memory settles.
3. Run at least 30 mixed-duration requests, including one continuous five-minute request.
4. Sample physical footprint throughout capture, rolling checkpoint decoding, final-tail decoding, fallback decoding, and cleanup.
5. Verify the waveform stays responsive and the final text covers the complete utterance without duplicate or lost text across 25%-overlap seams.
6. Report p50, p95, maximum, thermal state, and whether the Mac was on battery power.
7. Repeat after sleep/wake and after changing the active microphone.

See [Testing and release gates](TESTING.md) for the complete functional and privacy matrix.
