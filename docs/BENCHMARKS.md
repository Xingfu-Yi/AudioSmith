# Benchmarks

This document separates observed results, current product configuration, and release targets. The single-model pause-segmented application path has not yet completed a public end-to-end performance or accuracy report.

## Current test subject

- Model: `mlx-community/Qwen3-ASR-1.7B-8bit`, revision `a8379a2e2f9e313c9292cdf1af4055ab56d50d55`
- Decode: greedy, natural-pause segmentation with a 30-second safety limit
- Skill context: at most 40 pronunciation entries and 1,000 characters per request
- Postprocessing: canonical spelling plus deterministic spacing and punctuation cleanup; no text LLM
- Development hardware: M1 Pro with 32GB unified memory

Audio Smith does not use TorchAO FP8. Model weights are not stored in this repository.

## Observed 1.7B baseline

These measurements use the same 1.7B 8-bit ASR family as the current app, but they predate the current pause-segmented end-to-end workflow. They are retained for provenance and must not be presented as complete product results.

| Status | Runtime and workload | Elapsed | Peak process footprint |
|---|---|---:|---:|
| Measured baseline | Python/MLX, one 30-second input | 1.88s; RTF 0.063 | 4.43GB |
| Measured baseline | Swift Debug load + silent prewarm | Not a request-latency test | 3.40GB peak; 2.43GB settled |

## Current configuration, not measurements

- Short audio and final tails use their true length. Input below the model minimum pads only to 0.5 seconds; one empty-result retry adds 250ms silence.
- Long audio uses 1.2-second natural-pause boundaries after at least 1.5 seconds of voice, with 400ms boundary overlap. Uninterrupted speech has a 30-second safety limit.
- Only safety-limit speech overlaps may invoke local seam recovery, capped at 12 seconds. The whole recording is never re-decoded at release.
- The UI shows a waveform while recording and a time-driven progress ring while the final tail completes; it never shows provisional text.
- The session limit is five minutes.
- The runtime warns at 4.7GB physical footprint; over 5.0GB blocks binary release.

## Binary-release targets

These are gates, not achieved claims:

| Gate | Target | Required coverage |
|---|---:|---|
| Release-to-paste, 1–8s request | p95 ≤2s | Real microphone and supported target apps |
| Release-to-paste, 30s request | p95 ≤3s | Chinese, English, and mixed speech |
| Five-minute request | Final tail completes safely | One continuous session |
| Peak process footprint | ≤5.0GB | M1 Pro 32GB and at least one 24GB Mac |
| Waveform after key press | p95 ≤150ms | Real overlay rendering |
| ASR real-time factor | ≤0.25 | Published corpus |

## Accuracy gates

- The current 1.7B 8-bit path may be at most 0.5 percentage points worse than its BF16 reference on the mixed-language token error rate.
- AIGC pronunciation context must improve terminology accuracy without degrading the general set by more than 0.2 percentage points.
- Numbers, URLs, email addresses, and dictated wording must not be rewritten by a second language model because no such model exists in this architecture.

The report must publish hardware, macOS, source-audio description, corpus provenance, model revision, generation parameters, segmentation metrics, and privacy-safe aggregate results.

## Measurement protocol

1. Install and verify the model, disable network access, and wait for prewarm.
2. Record settled baseline footprint.
3. Run 1–8s, 30s, two-minute, and five-minute requests in Chinese, English, and code-switched sets.
4. Record every ASR phrase pass, seam repair, final-tail latency, p50/p95/max latency, and process footprint.
5. Confirm the number of ASR passes matches the natural boundaries and that release never triggers a whole-recording re-decode.
6. Repeat after sleep/wake, microphone changes, and thermal load.

See [Testing and release gates](TESTING.md) for the functional matrix.
