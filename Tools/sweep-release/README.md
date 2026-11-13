# sweep-release

Tooling for the Sparkle auto-update side of CW Sweep releases. Lives next to the `cw-sweep-release` skill workflow — the skill builds + notarizes the DMG, this script publishes it.

## What's here

| File | Purpose |
|------|---------|
| `sign-and-publish.sh` | Signs a notarized DMG, prepends a new `<item>` to `website/sweep/appcast.xml`, scp's the DMG + appcast to the website server. |

## Usage

After `cw-sweep-release` produces a notarized + stapled DMG:

```bash
cd ~/projects/carrier_wave
Tools/sweep-release/sign-and-publish.sh \
  --version 0.11.0 \
  --dmg ~/Desktop/CWSweep-0.11.0.dmg
```

Then commit the appcast change:

```bash
git add website/sweep/appcast.xml
git commit -m "Sparkle: publish CW Sweep 0.11.0"
git push origin main
```

Run with `--help` for the full flag list (notes HTML override, dry-run, alternate SSH host, etc.).

## How it knows where to publish

- **DMG host**: `activities.carrierwave.app:/var/www/carrierwave.app/sweep/` over `~/.ssh/id_hetzner_github` (the Hetzner key already used by ansible).
- **Appcast URL**: `https://carrierwave.app/sweep/appcast.xml` (matches `SUFeedURL` in `swift/macos/CWSweep/Info.plist`).
- **Sparkle private key**: macOS login keychain, item `ed25519` under "Sparkle". Generated once via `generate_keys`; the matching public key is committed in `Info.plist`. **Never re-run `generate_keys` on a working release machine** — it would invalidate every signature in the appcast.

Override any of these with env vars: `SWEEP_SSH_HOST`, `SWEEP_SSH_USER`, `SWEEP_SSH_KEY`, `SWEEP_REMOTE_DIR`, `SPARKLE_VERSION`.

## Sparkle CLI tools

The script downloads the official Sparkle release tarball on first use to `~/.cache/sparkle-tools/<version>/` and reuses the cached copy thereafter. No system-wide install needed.

## See also

- `cw-sweep-release` skill — full release flow (version bump, archive, notarize, publish).
- `swift/macos/CLAUDE.md` § Distribution — keychain & key-rotation rules.
- `infra/ansible/roles/website/` — server-side `/sweep/` directory + nginx caching.
