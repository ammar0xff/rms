# Roadmap

Ordered by what unblocks the most downstream work. Items marked **blocked** need
something only the owner can supply.

## 1. Make the published manifest reachable

- [ ] **Fetch the release manifest from Firestore.** The release pipeline writes
      `releases/{releaseId}` and points `activeReleases/{platform}` at it, but no
      client code reads either. Today the only manifest the app ever sees is the
      hardcoded demo seed in `_primeUpdateManifest`, so a published release is
      invisible to every device.
- [ ] Prefer the existing cached document when offline; never let a failed fetch
      clear a good cache.
- [ ] Reject a malformed or newer-schema document rather than half-honouring it.

## 2. Run the lifecycle

- [ ] **An update service that orchestrates the flow.** `UpdateLifecycleCoordinator`
      is never constructed anywhere. Discovery, decision and readiness all exist
      and are tested; nothing sequences them.
- [ ] Wire `HttpArtifactDownloader` and `AndroidUpdateInstaller` into DI — both
      are implemented and currently unused.
- [ ] Persist the terminal status and append audit events around each run.

## 3. Tell the user about it

- [ ] **Update prompt UI.** Blocking screen for mandatory releases, dismissible
      dialog for optional and recommended. Includes download progress and the
      failure/rollback state.

## 4. Remaining platforms

- [ ] **Windows installer.** Download the bundle, launch it, relaunch.
- [ ] **macOS installer.** Same shape.
- [x] **Linux** — no auto-update, by decision. The app points at a download.

## 5. Printing

- [ ] **ESC/POS adapter.** `PrintService` is currently a stub; `LocalPrintAdapter`
      collects jobs in memory and never touches a printer. Network and USB
      ESC/POS, behind the existing `PrintAdapter` seam.

## Blocked — needs the owner

- [ ] **`FIREBASE_SERVICE_ACCOUNT` and `FIREBASE_PROJECT_ID`.** The release
      workflow refuses to run without them, so nothing can be published yet.
- [ ] **Signing keys.** Android release keystore, Windows Authenticode
      certificate, macOS Apple Developer identity. Every artifact currently builds
      unsigned, so no update is distributable. The package name (`dev.rms.app`)
      and Android signing key together identify an install — changing either now
      that a release exists would force an uninstall and discard all local data.

## Test gaps

- [ ] `LocalUpdateAcknowledgementStore` has no direct test (only its interface is
      covered, via a fake).
- [ ] `FirestoreSyncTransport` — needs `fake_cloud_firestore`, approved but not
      yet added.
- [ ] `FirebaseAuthRepository` — same dependency.
- [ ] `offline_capability.dart` is pure and untested.

## Verified working

Four platform builds, green on every push: Android APK, Linux bundle, Windows
bundle, macOS bundle, plus web deploy and the analysis/test gate.

## Not verified without hardware

The download-to-install path has never run on a device. CI proves the Kotlin
compiles and the APK builds, but the system install prompt, FileProvider URI
resolution, and the user's accept/decline path are unproven.