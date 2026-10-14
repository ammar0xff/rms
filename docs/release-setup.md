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
keytool -genkey -v \
  -keystore ~/rms-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias rms
```

It prompts for a store password and a key password. Pick your own — they are
not interchangeable, and neither can be recovered if lost.

Back this file up somewhere durable and outside this repository. **There is no
recovery if it is lost:** every future update becomes a different app and users
must reinstall, losing their local data.

### Configure it locally

Create `android/key.properties` (already gitignored):

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=rms
storeFile=/absolute/path/to/rms-release.jks
```

Put the keystore at that path, then `flutter build apk --release` produces a
signed build. Without the file the build still works, signed with the debug key.

### Add the CI secrets

Convert the keystore to one line of text:

```bash
base64 -w0 ~/rms-release.jks > ~/rms-release.jks.b64
```

Then add four repository secrets under
**Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contents of `rms-release.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `rms` |
| `ANDROID_KEY_PASSWORD` | the key password |

Both workflows detect these and switch to real signing automatically. Until then
they keep producing debug-signed builds, which is why CI never fails for want of
a key.

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

After adding the Android secrets, run **Build native artifacts** and confirm the
APK reports the release key rather than the debug key:

```bash
keytool -printcert -jarfile app-release.apk | grep -i "owner"
```

The owner must be your alias, not `Android Debug`.