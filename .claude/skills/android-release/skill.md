---
name: android-release
description: Use when releasing a new version of the Carrier Wave Android app. Bumps versionCode/versionName, updates the Android changelog, builds and signs the release APK, uploads it to carrierwave.app/android/ (same hosting as the CW Sweep DMG), deploys the website, and verifies the live download. The Android app has its own version line (0.x), independent of iOS/macOS.
user-invocable: true
---

# Carrier Wave Android Release

End-to-end release for the Carrier Wave **Android** app: version bump, changelog,
signed APK build, hosting on `carrierwave.app/android/`, website deploy, and
verification. There is **no Play Store / CI pipeline** — distribution mirrors the
macOS CW Sweep DMG: a signed artifact scp'd to the server behind a gated download
page (`/android.html`).

## Prerequisites

- Working directory: `~/projects/carrier_wave` (main checkout, clean tree on `main`)
- **Release keystore present** (gitignored, local only): `android/carrierwave-release.jks`
  + `android/keystore.properties`. Without them `assembleRelease` produces an
  **unsigned, uninstallable** APK. This keystore is the app's permanent identity —
  never regenerate it to "replace" a lost one (users would have to uninstall).
- Build env: `JAVA_HOME=/opt/homebrew/opt/openjdk@17`,
  `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools`
- SSH to the server: host `activities.carrierwave.app` (user `root`), web root
  `/var/www/carrierwave.app`. On the Mac mini `~/.ssh/config` already maps that host
  to its key (`id_hetzner_cw_mini`), so plain `ssh`/`scp` authenticate — do not pass
  `-i`; a key named `id_hetzner_github` does not exist on this machine.
- For the local website deploy: `~/ansible_pass` (vault password) + `ansible-playbook`

## Steps

### 1. Preconditions

```bash
git -C ~/projects/carrier_wave branch --show-current   # main
git -C ~/projects/carrier_wave status --short           # clean
grep -nE 'versionCode|versionName' ~/projects/carrier_wave/android/app/build.gradle.kts
```

### 2. Decide the version bump

Android version is **independent** of iOS. Read the `# Android` → `## [Unreleased]`
section of `CHANGELOG.md` and pick patch/minor per scope. Confirm with the user if
unclear.

### 3. Bump the version

Edit `android/app/build.gradle.kts`: `versionCode` +1, `versionName` to the new value.

### 4. Update the changelog(s)

- **`CHANGELOG.md` → `# Android` section**: rename `## [Unreleased]` to
  `## [X.Y.Z] - YYYY-MM-DD`, add a fresh empty `## [Unreleased]` above it. Marquee
  Android features are often written in the top (iOS/shared) section during
  development — surface the user-facing ones here too so the Android entry is
  representative.
- **`website/changelog.html` → Android track** (`#track-android`): add an
  `Android X.Y` version block at the top, concise user-facing bullets.

### 5. Build the signed release APK

```bash
cd ~/projects/carrier_wave/android
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=/opt/homebrew/share/android-commandlinetools \
./gradlew :app:assembleRelease
```

Output: `android/app/build/outputs/apk/release/app-release.apk` (~40 MB). The
`buildRustCore` task cross-compiles cw-ffi first (slow). `BUILD SUCCESSFUL` = done.

### 6. Verify the signature

apksigner needs Java on PATH:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17; export PATH="$JAVA_HOME/bin:$PATH"
APKSIGNER=$(ls $ANDROID_HOME/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs \
  ~/projects/carrier_wave/android/app/build/outputs/apk/release/app-release.apk
```

Expect `Signer #1 certificate DN: CN=Carrier Wave, O=CarrierWaveApp` **and**
`Signer #1 certificate SHA-256 digest: 7dbc092af0fb9360d97234401276c481eb39bc97b90f73c502bd27f586c989e1`
(the release key since 0.7.0). A missing-Java error, a debug/other DN, or a
different digest means the wrong keystore — **stop**. A regenerated key with the
same DN still breaks updates for every installed copy.

### 7. Upload the APK to the server

The remote filename **must** match the nginx regex `CarrierWave-X.Y.Z.apk`
(no `android` in the name), plus a `-latest.apk` alias — mirroring the DMG flow.

```bash
T=root@activities.carrierwave.app
D=/var/www/carrierwave.app/android; V=X.Y.Z
LOCAL=~/projects/carrier_wave/android/app/build/outputs/apk/release/app-release.apk
ssh -o StrictHostKeyChecking=accept-new $T "mkdir -p $D"
scp -o StrictHostKeyChecking=accept-new "$LOCAL" "$T:$D/CarrierWave-$V.apk"
ssh -o StrictHostKeyChecking=accept-new $T \
  "cp -f $D/CarrierWave-$V.apk $D/CarrierWave-latest.apk && \
   chown www-data:www-data $D/CarrierWave-$V.apk $D/CarrierWave-latest.apk && \
   chmod 0644 $D/CarrierWave-$V.apk $D/CarrierWave-latest.apk && ls -la $D"
```

The download page (`website/android.html`), the nginx `/android/` location blocks
(`infra/ansible/roles/website/templates/nginx.conf.j2`), the site nav links, and the
ansible "ensure `/android` dir" task already exist — only new here for a first-time
setup. The download page is **password-gated with the same hash as the CW Sweep
page** (`PW_HASH` in `android.html`); reuse the same password.

### 8. Commit and push

```bash
git add android/app/build.gradle.kts CHANGELOG.md website/changelog.html
git commit -m "Android: bump to X.Y.Z (versionCode N)"
git push origin main
```

Pushing `website/**` changes triggers the `deploy-website` GitHub Action.

### 9. Deploy the website

The push in step 8 normally auto-deploys. **If GitHub Actions is failing** (e.g. a
billing/spending-limit block — check `gh run list --workflow=deploy-website.yml`),
deploy locally instead:

```bash
cd ~/projects/carrier_wave-private/infra/ansible
ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook site.yml \
  --vault-password-file ~/ansible_pass --tags website
```

`failed=0` in the PLAY RECAP = success. This applies the nginx APK blocks + reloads,
syncs `android.html`, ensures `/android` exists, and rebuilds the Hugo manual.
(APKs are scp'd out-of-band, so the deploy never touches them.)

### 10. Tag (optional, informational)

```bash
git tag -a android-vX.Y.Z -m "Carrier Wave Android X.Y.Z (versionCode N)"
git push origin android-vX.Y.Z
```

Tag prefix is `android-v` (not `v`) to avoid colliding with iOS tags. Nothing is
wired to build it — it's a marker only.

### 11. Verify live

```bash
curl -sI https://carrierwave.app/android.html                          # 200
curl -sI https://carrierwave.app/android/CarrierWave-latest.apk \
  | grep -iE 'content-type|cache-control|content-length'
# expect: application/vnd.android.package-archive, no-cache, ~38 MB
curl -sI https://carrierwave.app/android/CarrierWave-X.Y.Z.apk          # 200
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `assembleRelease` produces unsigned APK | `keystore.properties` / `.jks` missing — copy from backup |
| apksigner "Unable to locate a Java Runtime" | `export JAVA_HOME=/opt/homebrew/opt/openjdk@17; PATH=$JAVA_HOME/bin:$PATH` |
| APK URL serves `application/octet-stream` | nginx `/android/` block not deployed yet — run step 9 |
| `deploy-website` GH Action fails instantly | GitHub Actions billing/spending-limit block — use the local ansible deploy (step 9) |
| `android.html` 404 after push | website deploy hasn't run — step 9 |
| APK 404 despite upload | remote filename must be `CarrierWave-X.Y.Z.apk` (matches nginx regex) |

## Important Notes

- Release from `~/projects/carrier_wave` (main checkout), not a worktree.
- The APK is scp'd to the server **out-of-band**, like the CW Sweep DMG — it is not
  committed to git and not synced by ansible (which only ensures the directory).
- A quick alternative distribution channel (used before the website route existed):
  `rclone copy <apk> gdrive:CarrierWave-releases/ && rclone link gdrive:CarrierWave-releases/<apk>`.
- Related skills: `carrier-wave-release` (iOS), `cw-sweep-release` (macOS DMG — the
  hosting pattern this mirrors).
