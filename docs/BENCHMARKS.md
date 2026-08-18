# Benchmarks

This document separates observed results, current product configuration, and release targets. The new dual-model design has no completed public performance or accuracy result yet.

## Current test subject

- ASR: `mlx-community/Qwen3-ASR-0.6B-8bit`, revision `89e96d92ba34aca20b3e29fb10cc284097d1219f`
- Professional refiner: `Qwen/Qwen3-1.7B-MLX-4bit`, revision `21457c6f51ed54a7c16e988c0844db973815c137`
- ASR decode: greedy, natural-pause segmentation with a 30-second safety limit
- Refiner: thinking disabled, one whole-transcript call after release
- Development hardware: M1 Pro with 32GB unified memory

Audio Smith does not use TorchAO FP8. Model weights are not stored in this repository.

## Legacy observations

These rows measured the previous 1.7B 8-bit ASR-only path. They are retained for provenance and must not be presented as results for the current dual-model configuration.

| Status | Runtime and workload | Elapsed | Peak process footprint |
|---|---|---:|---:|
| Legacy measured baseline | Python/MLX, one 30-second input, 1.7B ASR 8-bit | 1.88s; RTF 0.063 | 4.43GB |
| Legacy measured baseline | Swift Debug load + silent prewarm, 1.7B ASR 8-bit | Not a request-latency test | 3.40GB peak; 2.43GB settled |

## Current configuration, not measurements

- Fast mode: 0.6B ASR and generic deterministic cleanup; refiner memory is unloaded.
- Professional mode: 0.6B ASR followed by one 1.7B whole-transcript refinement with selected Skills.
- Short audio and final tails: true length; input below the model minimum pads only to 0.5 seconds; one empty-result retry adds 250ms silence.
- Long audio: 1.2-second natural-pause boundaries after at least 1.5 seconds of voice, with 400ms boundary overlap; uninterrupted speech has a 30-second safety limit.
- Local seam recovery: only safety-limit speech overlaps may invoke it, at most 12 seconds; no whole-recording re-decode.
- UI: waveform while recording; time-driven progress ring after release; no live transcript.
- Session limit: five minutes.
- Warning: 4.7GB physical footprint; release blocker: over 5.0GB.

## Binary-release targets

These are gates, not achieved claims:

| Gate | Fast | Professional | Required coverage |
|---|---:|---:|---|
| Release-to-paste, 1–8s request | p95 ≤1s | p95 ≤2s | Real microphone and supported target apps |
| Release-to-paste, 30s request | Record | p95 ≤5s | Chinese, English, and mixed speech |
| Five-minute refinement | N/A | complete or safe fallback ≤45s | One continuous session |
| Peak process footprint | Refiner absent | ≤5.0GB | M1 Pro 32GB and at least one 24GB Mac |
| Waveform after key press | p95 ≤150ms | p95 ≤150ms | Real overlay rendering |
| ASR real-time factor | ≤0.25 | ≤0.25 before refinement | Published corpus |

## Accuracy gates

- Professional mixed-language token error rate may be at most 0.3 percentage points worse than the previous 1.7B-ASR baseline.
- AIGC terminology accuracy must improve by at least five percentage points.
- Semantic expansion, summarization, translation, and protected number mutation must remain zero in the release corpus.

The report must publish hardware, macOS, source-audio description, corpus provenance, model revisions, all generation parameters, per-mode metrics, and privacy-safe aggregate results.

## Measurement protocol

1. Install and verify both models, disable network access, and wait for prewarm.
2. Record settled baseline footprint separately for Fast and Professional modes.
3. Run 1–8s, 30s, two-minute, and five-minute requests in Chinese, English, and code-switched sets.
4. Record every ASR pass, seam repair, the single refiner call count, timeout/fallback reason, p50/p95/max latency, and process footprint.
5. Confirm Fast mode retains no 1.7B model memory and Professional mode never calls the text model during recording.
6. Exercise `Esc` during refinement and verify ASR fallback paste begins within 500ms once the tail text exists.
7. Repeat after sleep/wake, microphone changes, and thermal load.

See [Testing and release gates](TESTING.md) for the functional matrix.
