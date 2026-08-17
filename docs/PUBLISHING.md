# Publishing the GitHub repository

The source repository and the signed macOS binary have separate readiness levels. Source may be published once the repository checks pass. A downloadable DMG must also pass every runtime, accuracy, signing and license gate.

## Create the remote repository

Choose the GitHub owner and visibility before creating anything. Create an empty repository named `AudioSmith` without an auto-generated README, license or `.gitignore`, then connect this existing checkout:

```bash
git remote add origin git@github.com:<owner>/AudioSmith.git
git push -u origin main
```

Recommended repository description:

> Private, on-device push-to-dictate for Apple Silicon, powered by Qwen3-ASR and standard terminology Skills.

Recommended topics: `macos`, `apple-silicon`, `speech-to-text`, `asr`, `qwen3-asr`, `mlx`, `swift`, `dictation`, `privacy`, `skills`.

## Repository settings

After the first push:

1. Enable Issues and private vulnerability reporting.
2. Require the `CI / test` check on `main` before merging.
3. Prevent force pushes and branch deletion on `main`.
4. Allow GitHub Actions read access by default; `release.yml` requests write access only for tagged releases.
5. Add a social preview and application icon after final branding is approved.
6. Add a private maintainer contact before adopting a formal Code of Conduct.

## Source-publication checklist

- [ ] `./scripts/validate_skills.py`
- [ ] `./scripts/validate_docs.py`
- [ ] `./scripts/test.sh`
- [ ] `git diff --check`
- [ ] No model weights, recordings, transcripts, signing material or credentials
- [ ] README, MIT license, security policy, contribution guide, support guide and changelog are present
- [ ] Issue forms and pull-request template render correctly on GitHub
- [ ] Repository owner, visibility, description and topics are confirmed

## Binary-release checklist

- [ ] Every gate in `docs/TESTING.md` has passed on the required hardware
- [ ] Application icon and release screenshots are final
- [ ] Third-party notices are present in the app bundle and reviewed
- [ ] Apple Developer ID and notarization secrets from `docs/RELEASING.md` are configured
- [ ] Bundle identifier belongs to the signing team
- [ ] Version and build numbers are updated
- [ ] `scripts/verify_release_version.sh v<version>` passes
- [ ] A release candidate DMG passes Gatekeeper on a clean Mac

Prerelease tags such as `v0.1.3-alpha.1` are marked as GitHub prereleases automatically. Do not publish `v0.1.3` as stable until the release gates are complete.
