# Contributing

Thank you for helping improve Audio Smith.

1. Discuss substantial product, model, privacy, or Skill schema changes in an issue first.
2. Keep core transcription fully local and do not add telemetry, audio persistence, or a second local LLM without explicit project agreement.
3. Run `python3 scripts/validate_skills.py`, `python3 scripts/validate_docs.py`, and `./scripts/test.sh` before opening a pull request.
4. Follow [the benchmark protocol](docs/BENCHMARKS.md), including hardware, macOS version, model revision, peak footprint, latency, and the relevant audio-set description, for performance or accuracy claims.
5. Never commit model weights, recordings, private transcripts, signing certificates, or Apple credentials.

Skill contributions must be data-only and follow [the Skill guide](docs/SKILLS.md). Use a standard `SKILL.md` with `name` and `description` frontmatter. Put ASR guidance under `## Dictation context` and backtick-delimited preferred spellings and aliases under `## Vocabulary`. Document the source and license of any non-trivial terminology list, and avoid aggressive aliases that could rewrite ordinary speech incorrectly.
