# Production readiness

Every step between the current state and running in a restaurant. Ordered so
each phase is verifiable before the next begins.

Status markers: `[ ]` not started · `[~]` built but not wired or unproven ·
`[x]` done and verified.

---

## Where we are

| | |
|---|---|
| Version | `0.8.0+1` |
| Tests | 362 passing |
| CI | analysis + tests, green on every push |
| Builds | Android APK, Linux, Windows, macOS, web — all green |
| Phases | PRD 0–5 implemented |

Every platform build is **unsigned** and **no release has ever been published**.
The update pipeline is written but not connected to the running app.

---

## Phase 1 — Prove the pipeline works

Nothing below is trustworthy until this passes end to end. It costs about four
minutes and exercises every piece at once.

- [ ] **Dispatch a release** — Actions → *Release* → Run workflow,
      `version: 0.9.0`, `platform: android`, `rollout: 10`
- [ ] **Confirm the job log prints** `Published release android-0.9.0-1`
- [ ] **Confirm the manifest landed** in Firestore → https://console.firebase.google.com/project/teletunnal/firestore
      (`releases` and `activeReleases` collections)
- [ ] **Confirm the asset is downloadable** —
      https://github.com/ammar0xff/rms/releases

**Why first:** the Firebase service account has never been exercised. If it
cannot write to Firestore, every later step is blocked on a permission rather
than on code, and finding that out after creating a keystore wastes the setup.

> The APK will be debug-signed. Fine for proving the pipeline; not installable
> over a real release.

---

## Phase 2 — Connect the update flow

Six components exist and **none are wired into dependency injection**:

| Component | Built | In DI |
|---|---|---|
| `UpdateService` | yes | **no** |
| `HttpArtifactDownloader` | yes | **no** |
| `AndroidUpdateInstaller` | yes | **no** |
| `LocalSchemaMigrator` | yes | **no** |
| `LocalHealthChecker` | yes | **no** |
| `UpdatePrompt` / `UpdateController` | yes | **no** |

Until this is done the app tells an operator an update is ready, and pressing
the button does nothing.

- [ ] Construct all six in `lib/src/core/di/app_bootstrap.dart`
- [ ] Build the device context from branch and cohort seed
      (`core/config/device_update_context.dart`)
- [ ] Refresh the manifest on start (`UpdateRefreshService`) and on demand
- [ ] Mount `UpdatePrompt` in the app shell — blocking screen for mandatory,
      dialog for optional
- [ ] Replace the Settings string that says download is "not enabled"
- [ ] Add a widget test for the mounted prompt

**AC-35 must survive this.** A mandatory release installs only after the
unsynced backlog clears. The existing tests cover `UpdateService`; a mounted
prompt must not reopen a path around the gate.

---

## Phase 3 — Signing

Every artifact was previously unsigned, so no update was distributable.

- [x] **Generate the Android keystore** — `docs/release-setup.md`.
      RSA 4096 / SHA256withRSA, PKCS12, alias `rms-release`, valid to 2054.
      Certificate SHA-256 pinned in `docs/release-setup.md`.
- [x] **Back it up outside the repository.** Copy of the keystore and its
      password at `~/.local/share/rms-signing/` (mode 600).
      *GitHub secrets are not a backup — they cannot be read back out.*
- [x] Add `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` as repository secrets
- [x] Confirm the password really signs, via a `jarsigner` sign-and-verify
      round-trip, and that a wrong password is rejected
- [x] Publish a **signed** release and confirm the APK's fingerprint matches the
      pin above — `v0.10.0`, signer `03:B0:F1:8C:…:9C`, `notBefore` matching the
      keystore creation time. The workflow log did **not** print the debug-key
      fallback line, and the published sha256 matches the downloaded artifact.
- [ ] Reconcile `buildNumber`: the APK's real `versionCode` is `6`, but the
      manifest published `2`, and `UpdatePrompt` shows the manifest's value to
      the operator. Two counters are in play — `GITHUB_RUN_NUMBER` in the build
      step, a Firestore sequence in `tool/publish_release.mjs`. Harmless for
      install ordering, since Android compares `versionCode` and the decision
      engine compares version strings, but it misreports the build.
- [ ] Windows Authenticode certificate — later, when a Windows installer exists
- [ ] macOS Developer ID + notarisation — later

`dev.rms.app` is fixed permanently. Changing the package name or the signing key
after a release forces an uninstall and discards local data.

One consequence of doing this after `v0.9.0` was already published: that release
is debug-signed, so it cannot be updated in place by the newly signed build. It
has never been installed on a device, so nothing is stranded — but it is a
reminder that the first published artifact fixes the identity forever.

---

## Phase 4 — Real device verification

**Nothing has ever run on a device.** CI proves code compiles; it cannot prove
behaviour. Every step below needs physical hardware.

- [ ] Install the APK on an Android device
- [ ] Sign in, confirm the account-scoped content is correct
- [ ] Confirm the update prompt appears for a published release
- [ ] Confirm the download progress is real and reaches 100%
- [ ] Confirm SHA-256 verification rejects a corrupted file
- [ ] Confirm the system install prompt appears and accepts
- [ ] **Confirm the new build still launches and the data survived**
- [ ] Confirm a mandatory release blocks, and optional does not
- [ ] Confirm an update refuses to install while local work is unsynced
      *(AC-35 on a real device — the single most important check in this list)*
- [ ] Repeat the install-path checks on Windows and macOS

---

## Phase 5 — Test coverage of what runs in production

Ordered by risk. Six closed; the rest remain.

- [x] `firestore_sync_transport.dart` — covered through `SyncAck`, the
      acknowledgement contract now shared with the in-memory transport. The
      finding was that both had been assembling their own ack map, so a contract
      change passed every test and still failed against Firestore.
- [x] `artifact_downloader_io.dart` — **found two defects that made updates
      non-functional**, see below. Covered end to end against a loopback HTTP
      server and the real file on disk.
- [x] `artifact_verifier.dart` — the SHA-256 was hand-rolled and the test held
      a third copy of it, so the tests confirmed the copy agreed with itself.
      Now `package:crypto` (already a dependency, never imported) pinned against
      FIPS 180-4 vectors.
- [x] `local_health_checker.dart` — decides rollback; now covered, including the
      fail-closed `inconclusive` path
- [x] `update_acknowledgement_store.dart` — persistence; found a cast that
      could throw a corrupt row out of the sync loop
- [x] `local_schema_migrator.dart` — runs between install and the health
      check, so its failure modes decide whether an upgrade is rolled back
- [x] `firestore_update_source.dart` — covered through a
      `ManifestDocumentReader` seam; both the Firestore and test paths now share
      one `_resolve`
- [x] `firebase_auth_repository.dart` — covered behind an `AuthBackend`
      interface, since `FirebaseAuth` cannot be constructed without a configured
      Firebase app
- [ ] `app_bootstrap.dart` — **deliberately not unit-tested.** It is 934 lines
      behind three things a unit test cannot supply: a `path_provider` platform
      channel, a configured Firebase app, and live Auth. A test here would assert
      almost nothing. Its wiring is exercised by every widget test that boots the
      app, and properly by Phase 4 on a device.
- [ ] Add `fake_cloud_firestore` as a dev dependency (approved, never added).
      No longer blocking: every file it would have served is now covered through
      a seam. It would only add value for the transaction semantics inside
      `firestore_sync_transport.dart` itself.
- [ ] `offline_capability.dart` — pure, cheap
- [ ] Optional: widget tests for the remaining feature screens

### The pattern the closed items share

Where a class was untestable because a third-party SDK sat directly underneath
it, the fix was a narrow interface in domain terms, with the SDK confined to a
private adapter: `ArtifactFileReader`, `ManifestDocumentReader`, `AuthBackend`,
plus `tempDirectory` on the downloader. Each one also removed a place where the
production path and the test path could have drifted apart — which is how the
sync ack contract ended up duplicated in the first place.

### Defects found by writing the downloader test

Both mean the update flow could never have completed on a device. Neither was
reachable by a unit test, and neither would have surfaced without hardware:

1. **`ArtifactVerifier` could not read a file.** It held a private `_File` whose
   methods threw `UnimplementedError`; the surrounding catch turned that into a
   null, `verify` returned `notFound`, and the downloader reported failure after
   a completely successful download. Every unit test passed `bytes:` and so
   never entered that branch.
2. **`cancel()` did not cancel.** `HttpClient.close()` without `force` leaves
   the in-flight response draining, so a cancelled transfer kept pulling bytes
   off the socket and writing them to disk until the server chose to stop — and
   emitted no terminal state at all while parked on a chunk that never came.

The lesson worth carrying: the download path had four hundred tests' worth of
neighbouring coverage and was still incapable of installing an update. Coverage
of *units* is not coverage of *paths*.

---

## Phase 6 — Printing

`PrintService` is constructed in two places but only ever collects jobs in
memory. No printer is contacted.

- [ ] Decide the transport: ESC/POS over network was agreed
- [ ] Implement `PrintAdapter` for ESC/POS behind the existing interface
- [ ] Configuration screen: printer IP, port, receipt width
- [ ] Reconnect and retry handling for a printer that is offline
- [ ] Test against a real printer

---

## Phase 7 — Operational readiness

- [ ] **Rotate the Firebase service account key.** It was pasted into chat and
      is therefore compromised. `docs/release-setup.md`
- [ ] Decide whether release assets stay public. They are, because the repo is
      public and Cloud Storage needs a billing account
- [ ] Backup and restore drill for the local database
- [ ] Decide who can dispatch a release, and whether to require approval
- [ ] Rollout policy written down: who sets severity, who can hold back
- [ ] Monitoring: release publish failures, update failure rate
- [ ] First-run experience on a real device
- [ ] App icon and name per platform (currently the generated default)
- [ ] Confirm **RTL** is enabled. The locale is `ar`, but `Directionality` is
      not explicitly set — check Arabic rendering on a real screen

---

## Decisions to revisit

| Decision | Why it may change |
|---|---|
| No Linux auto-update | Revisit if Linux terminals become common |
| Web takes no artifact updates | Fine while web deploys on its own cadence |
| Public release assets | Change if APK privacy matters |
| `sembast` instead of Drift | Only touches `data/local/`; low priority |
| No rollback implementation | `requiresRollback` is recorded but nothing acts on it |

---

## Explicitly not done

- Windows and macOS **installers**. Both platforms download an artifact; neither
  can install it. Windows needs Authenticode; macOS needs Developer ID.
- Rollback. The manifest carries `rollbackTargetVersion` and the coordinator
  sets `requiresRollback`, but nothing performs a rollback.
- Web artifact updates, deliberately excluded.

---

## The one invariant that outranks everything

**Unsynced local work must never be dropped.** Orders, payments, kitchen,
delivery and settlement records that have not reached the backend must survive
any update.

This is enforced in code (`UpdateReadinessEngine`), tested in the domain, tested
in the UI, and re-tested after the update flow is wired. Keep it that way: if a
future change ever lets a mandatory update install over unsynced work, that is a
regression regardless of how well everything else passes.