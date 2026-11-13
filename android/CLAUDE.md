# Carrier Wave Android

Jetpack Compose app consuming the shared Rust core (`rust/cw-core`) via UniFFI
Kotlin bindings. Build from `android/` with `./gradlew :app:assembleDebug`
(JDK 17; `buildRustCore` cross-compiles cw-ffi and regenerates the bindings).

## Release Signing

Release APKs (`./gradlew :app:assembleRelease`) are signed with a local
keystore that is **not** in git:

- `android/carrierwave-release.jks` — the release keystore (alias
  `carrierwave`). This is the app's permanent identity: every update must be
  signed with it, and it becomes the Play upload key if the app is ever
  published. **Losing it means users must uninstall to update (wiping their
  on-device logbook).** Keep an offline backup of both files.
- `android/keystore.properties` — `storeFile` / `storePassword` / `keyAlias` /
  `keyPassword` consumed by `app/build.gradle.kts`. Also gitignored.

**Current release key (since 0.7.0, 2026-10-14):** certificate SHA-256
`7dbc092af0fb9360d97234401276c481eb39bc97b90f73c502bd27f586c989e1`. The
original key that signed 0.4.0–0.6.2 (`116bd19a…0f827ff`) was lost, so 0.7.0
required every tester to uninstall and reinstall. Don't let that happen twice:
keep an offline backup of the `.jks` and `keystore.properties`.

On a machine without these files, debug builds work normally and
`assembleRelease` produces an *unsigned* (uninstallable) APK — copy both files
from a backup to sign.

To regenerate from scratch (new identity — only for a fresh start, never to
"replace" a lost keystore mid-distribution):

```bash
keytool -genkeypair -v -keystore carrierwave-release.jks \
  -alias carrierwave -keyalg RSA -keysize 2048 -validity 10000
# then write keystore.properties with the matching values
```

Verify a built APK's signature:

```bash
$ANDROID_HOME/build-tools/<ver>/apksigner verify --print-certs \
  app/build/outputs/apk/release/app-release.apk
```

Signed output lands at `app/build/outputs/apk/release/app-release.apk`.
Distribute that file directly (sideload); debug and release signatures differ,
so one cannot install over the other without an uninstall.

## Versioning & Changelog

The Android app has **its own version line** (0.1, 0.2, …), independent of the
iOS/macOS `MARKETING_VERSION`. Bump `versionCode` (+1) and `versionName` in
`android/app/build.gradle.kts` for each release.

Record Android changes in the `# Android` section at the end of the repo-root
`CHANGELOG.md`, and mirror them in the `Android` track of
`website/changelog.html` (the public changelog has a platform toggle). See
[docs/RELEASING.md](../docs/RELEASING.md#changelog-conventions) for the full
convention.
