# Android App Links — assetlinks.json

Served at `https://vamo.world/.well-known/assetlinks.json`.

- `package_name` must match `applicationId` in `app/android/app/build.gradle.kts`
  (currently `app.vamo`, must match `applicationId` in `app/android/app/build.gradle.kts`).
- `sha256_cert_fingerprints`: replace `DEBUG_FINGERPRINT` with the **upload key**
  SHA-256 for local/debug builds, then **add** the Play App Signing certificate
  fingerprint at store setup — Google Play rewrites release signatures; both
  fingerprints may be required during transition.
- Optional env override for CI preview: set `ANDROID_ASSETLINKS_FINGERPRINT` in
  Vercel and generate the file at build time when we wire that up.
