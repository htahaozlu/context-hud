# Releasing ContextHUD

This document describes how ContextHUD releases are produced. It targets project maintainers; contributors do not need any of the credentials below to build the app locally.

## Artifact

Every release ships a single primary artifact: `ContextHUD.dmg`.

For the DMG to install cleanly on a stock macOS machine (no "unidentified developer" or "damaged app" warnings), it must be:

1. Code-signed with a **Developer ID Application** certificate
2. Built with the **hardened runtime** and a secure timestamp
3. Submitted to Apple's notary service and the resulting ticket **stapled** to the DMG

Without these, macOS Gatekeeper will block the app on first launch.

## Local build (no credentials required)

```bash
scripts/create-macos-dmg.sh
```

If no `Developer ID Application` identity is present in the keychain, the script falls back to an ad-hoc signature. The resulting DMG is fine for local testing but will trip Gatekeeper on a fresh machine.

## Maintainer release (signed + notarized)

The build script auto-detects a `Developer ID Application: ...` identity from the login keychain. To produce a release-grade DMG you need:

### One-time setup

1. **Developer ID Application certificate** in the keychain.
   - Apple Developer portal → Certificates → "+" → "Developer ID Application" → upload a CSR → download `.cer` → double-click to install.
   - Verify with: `security find-identity -v -p codesigning | grep "Developer ID Application"`
2. **Notary API key** stored as a keychain profile.
   - App Store Connect → Users and Access → Integrations → Team Keys → generate a key. Note the Issuer ID and Key ID. Download the `.p8` (one-time).
   - Store the credentials:
     ```bash
     xcrun notarytool store-credentials contexthud-notary \
       --key /path/to/AuthKey_XXXXXXXXXX.p8 \
       --key-id XXXXXXXXXX \
       --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     ```

### Cut a release

```bash
scripts/create-macos-dmg.sh
```

The script will:

- Sign the bundle with the first `Developer ID Application` identity it finds (override with `DEVELOPER_ID_IDENTITY`)
- Apply the hardened runtime and a secure timestamp using `packaging/macos/ContextHUD.entitlements`
- Build the DMG and submit it to Apple's notary service (override the profile with `NOTARY_PROFILE`)
- Staple the notarization ticket to the DMG when the submission is accepted

Verify a notarized DMG:

```bash
spctl -a -t open --context context:primary-signature -v dist/ContextHUD.dmg
xcrun stapler validate dist/ContextHUD.dmg
```

Both commands should report `accepted` / `valid`.

## CI release

`.github/workflows/release.yml` produces a DMG on every `v*` tag. The job picks up signing credentials from GitHub Actions secrets when available, and falls back to an unsigned build otherwise.

Required secrets for a fully signed + notarized CI release:

| Secret | Description |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` export of the Developer ID Application certificate **and** its private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `MACOS_NOTARY_API_KEY_BASE64` | Base64-encoded `.p8` notary API key |
| `MACOS_NOTARY_API_KEY_ID` | Notary key ID (10 characters) |
| `MACOS_NOTARY_API_ISSUER` | Notary issuer UUID |

Exporting the `.p12`:

```bash
# In Keychain Access, select both the "Developer ID Application: ..." certificate
# and its matching private key, then File → Export Items → .p12.
base64 -i DeveloperID.p12 -o DeveloperID.p12.b64
```

Encoding the `.p8`:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 -o AuthKey.p8.b64
```

Paste the contents of each `.b64` file into the matching GitHub Actions secret. The CI workflow creates a temporary keychain, imports the certificate, and stores the notary profile before invoking the build script — exactly mirroring the local flow.

## Forks

Forks cannot reproduce signed releases without their own Apple Developer Program enrollment. The build scripts work without any credentials and will emit an ad-hoc signed DMG suitable for development. Users who install an ad-hoc DMG need to right-click → Open on first launch.

## Security

Never commit any of the following to the repository:

- `AuthKey_*.p8`
- `*.cer`
- `*.certSigningRequest`
- `.p12` exports
- `.notary-env` or similar credential files

The repository's `.gitignore` already excludes these patterns.
