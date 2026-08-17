# Releasing

The `release.yml` workflow builds only from `v*` tags and expects these GitHub Actions secrets:

- `APPLE_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate and private key
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`
- `APPLE_SIGNING_IDENTITY`: full Developer ID Application identity
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_ID`: notarization Apple ID
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization

Before tagging:

1. Complete every gate in `docs/TESTING.md`.
2. Confirm the pinned model manifest and dependency lock file.
3. Update version/build numbers and `CHANGELOG.md`.
4. Confirm the app makes no unplanned network requests.
5. Run `scripts/verify_release_version.sh v0.1.1`.
6. Push an annotated tag such as `v0.1.1`.

The workflow tests, archives, exports with Developer ID, creates a DMG, submits it to Apple notary service, staples the ticket, verifies Gatekeeper acceptance, and publishes the DMG plus SHA-256 checksum. It never uploads model weights.

Tags with a suffix, such as `v0.1.1-alpha.1`, must share the numeric core with `MARKETING_VERSION` and are automatically published as GitHub prereleases. See `docs/PUBLISHING.md` for the complete source and binary readiness checklists.
