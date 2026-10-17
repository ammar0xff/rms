# Setting up releases

Two things must be supplied by the repository owner before a device can be
updated in the wild: a Firebase service account so releases can be published,
and signing keys so an update is recognised as the same app.

Both are secrets. **Never commit them, never paste them into chat.** Each step
below ends with adding a value through GitHub's UI, which stores it encrypted.

---

## 1. Android signing key

Android identifies an install by the pair **(application id, signing key)**.
Together they decide whether a new APK may replace an installed one. The
application id is already fixed at `dev.rms.app` — treat both as permanent.

### Create the keystore

Run once, on a machine you control and trust:

```bash
PASS="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)"

keytool -genkeypair \
  -alias rms-release \
  -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
  -validity 10000 \
  -storetype PKCS12 \
  -keystore android/app/rms-release.keystore \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=RMS Release, OU=Engineering, O=RMS, C=US"
```

Two deliberate choices:

- **PKCS12 forces one password for both store and key.** Passing different
  `-storepass` and `-keypass` values makes keytool warn and silently ignore the
  key password, so you would believe you had two when you had one. If you want
  them genuinely separate, use `-storetype JKS`.
- **Alphanumeric passwords only.** A password containing `=` or `:` has to be
  escaped in `android/key.properties`, and getting that wrong fails the build in
  a way that reads like a corrupt keystore.

10,000 days from creation expires in 2054, comfortably past the 2033 floor
Google Play enforces on certificate validity.

Back the keystore up somewhere durable **outside this repository**, along with
the password. GitHub secrets are not a backup: they cannot be read back out, so
if the local copy is lost the key is unrecoverable and every existing install is
stranded permanently on whatever version it is running.

### Verify the key

```bash
keytool -list -v -alias rms-release \
  -keystore android/app/rms-release.keystore -storepass "$PASS"
```

Use `-list -v`, not `-printcert`: `-printcert` reads a certificate from a stream
or file and fails with `Empty input` when pointed at an alias inside a keystore.

The SHA-256 fingerprint of the certificate is the value worth recording. Pin it
here so "which key signed this build?" stays answerable offline, long after the
console is gone:

**Release key** (`rms-release`, generated 2026-10-17):

```
sha256 Fingerprint=A4:BC:D5:A5:79:44:3A:06:CE:61:A3:9B:4E:E2:E1:2D:03:6C:2B:B8:8A:7C:3E:82:08:EF:3C:66:0B:68:9E:ED
```

**Debug key** — what v0.21.0 through v0.26.0 were signed with, because no
release key was configured yet. Any APK carrying this fingerprint is a
pre-release build and must not ship to customers:

```
sha256 Fingerprint=03:B0:F1:8C:3F:6C:27:1C:38:ED:EB:7D:BE:2E:6F:5A:59:C4:89:07:DD:EC:17:50:B8:43:16:28:FA:9B:EF:9C
```

If a published artifact ever reports the debug fingerprint, the release
secrets went missing at build time — the workflow prints "No signing key
configured" and carries on rather than failing the build. Check the run log
before trusting any artifact.

To confirm the password genuinely works for signing — rather than that keytool
merely parses the file — sign and verify a throwaway archive:

```bash
jarsigner -keystore android/app/rms-release.keystore -storepass "$PASS" \
  probe.jar rms-release && jarsigner -verify probe.jar
```

### Configure it locally

Create `android/key.properties` (already gitignored):

```properties
storePassword=<store password>
keyPassword=<store password>
keyAlias=rms-release
storeFile=rms-release.keystore
```

`storeFile` is resolved relative to `android/app/`, which is where the release
workflow puts the keystore too — so a local build and a CI build are signed by
the same key. Then `flutter build apk --release` produces a signed build.
Without the file the build still works, signed with the debug key.

### Add the CI secrets

```bash
base64 -w0 android/app/rms-release.keystore | gh secret set ANDROID_KEYSTORE_BASE64
printf '%s' "$PASS"                  | gh secret set ANDROID_KEYSTORE_PASSWORD
printf '%s' "$PASS"                  | gh secret set ANDROID_KEY_PASSWORD
printf '%s' 'rms-release'            | gh secret set ANDROID_KEY_ALIAS
```

Or add them by hand under
**Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0` of the keystore |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `rms-release` |
| `ANDROID_KEY_PASSWORD` | the key password |

Both workflows detect these and switch to real signing automatically. Until then
they keep producing debug-signed builds, which is why CI never fails for want of
a key.

### A release signed with a new key cannot update an old one

The app identity is *(application id, signing key)*. If a build is published
under one key and a later one under another, Android rejects the upgrade and the
user must uninstall first — discarding their local database. If you ever need to
change keys, do it before any release has shipped; afterwards the options are
Play App Signing, or a new application id.

---

## 2. Firebase service account

Needed by the release workflow to upload the artifact to Cloud Storage and write
the manifest document. Without it the workflow stops with an explicit message.

The project is `teletunnal` (bucket `teletunnal.firebasestorage.app`).

### Create it

1. Open the project in the
   [Google Cloud console](https://console.cloud.google.com/) → **IAM & Admin** →
   **Service Accounts** → **Create service account**.
2. Name it something like `rms-release-publisher`.
3. Grant it, directly on the service account:
   - **Firebase Rules Admin** — or more narrowly, *Cloud Datastore User* on the project
   - **Storage Admin** — or *Cloud Storage Object Admin* on the bucket only
4. Create a JSON key and download it.

Prefer granting access on the bucket rather than the whole project: the workflow
only needs to write objects.

### Add the CI secrets

| Secret | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | the entire downloaded JSON file, pasted as-is |
| `FIREBASE_PROJECT_ID` | `teletunnal` |

The JSON is multiline; the workflow reads it from the environment, so no escaping
is needed. Once both are set, the **Release** workflow becomes dispatchable for
real.

---

## 3. Windows (later)

SmartScreen will warn on every unsigned installer, and updates are only accepted
when signed with the same certificate.

1. Buy or create an Authenticode code-signing certificate.
2. Export it as a `.pfx` with a password.
3. Add `WINDOWS_CERT_PFX_BASE64` and `WINDOWS_CERT_PASSWORD` as secrets, and
   sign `build/windows/x64/runner/Release/rms.exe` in the workflow.

No desktop installer has been written yet, so this can wait until one exists.

---

## 4. macOS (later)

Requires a paid Apple Developer membership, plus notarisation, or Gatekeeper
blocks the app on any recent macOS.

1. Enrol in the [Apple Developer Program](https://developer.apple.com/programs/).
2. Create an installer certificate and a **Developer ID Application** identity.
3. Export it as a `.p12` with a password.
4. Add `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD` and `MACOS_SIGN_IDENTITY`
   as secrets.

Unsigned builds are fine for proving the target compiles, which CI already does.

---

## Verifying it worked

After adding the Android secrets, run **Build native artifacts**, download the
APK, and confirm it reports the release key rather than the debug key. The check
that matters is matching the fingerprint pinned earlier:

```bash
apksigner verify --print-certs app-release.apk   # from Android SDK build-tools
```

```
Signer #1 certificate DN: CN=RMS Release, OU=Engineering, O=RMS, C=US
Signer #1 certificate SHA-256 digest:
  03b0f18c3f6c271c38edeb7dbe2e6f5a59c48907ddec1750b8431628fa9bef9c
```

A debug-signed APK instead reports `CN=Android Debug`. Compare case-insensitively
and ignoring the colons.

If `apksigner` is not installed, `keytool -printcert -jarfile app-release.apk`
is a fallback, but it only reads v1 (JAR) signatures. A build signed with v2/v3
alone carries no `META-INF/*.SF`, so the command prints nothing and its silence
does not mean the APK is unsigned — prefer `apksigner`.

When neither is available, the signer can be read straight out of the APK
Signing Block: it sits immediately before the central directory, is terminated
by the magic `APK Sig Block 42`, and holds one entry per scheme
(`0x7109871a` for v2, `0xf05368c0` for v3). The v2 entry's signed-data record
carries the certificate as a length-prefixed DER sequence. Note that
`AndroidManifest.xml` is deflated inside the APK, so searching the raw file for
the version string finds nothing — inflate it first.

Then confirm CI agreed, by checking the workflow log:

```
No signing key configured — building with the debug key.
```

That message means the secrets were not found and the artifact is *not*
distributable. Its absence is the signal that signing took effect.