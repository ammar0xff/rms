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

Every artifact is currently unsigned, so no update is distributable.

- [ ] **Generate the Android keystore** — `docs/release-setup.md`
- [ ] **Back it up outside the repository.** Losing it makes every future
      update a different app, forcing reinstalls and losing all local data
- [ ] Add `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` as repository secrets
- [ ] Verify: `keytool -printcert -jarfile app-release.apk | grep -i owner`
      must show your alias, not `Android Debug`
- [ ] Publish a **signed** release (Phase 1 again)
- [ ] Windows Authenticode certificate — later, when a Windows installer exists
- [ ] macOS Developer ID + notarisation — later

`dev.rms.app` is fixed permanently. Changing the package name or the signing key
after a release forces an uninstall and discards local data.

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

Fifteen files hold real logic with no direct test. Ordered by risk:

- [ ] `firestore_sync_transport.dart` — the backend sync path: idempotency,
      canonical order numbers, best-effort counters
- [ ] `firebase_auth_repository.dart` — authentication
- [ ] `artifact_downloader_io.dart` — a 403 bug hid here; the transfer and
      verification path is unproven
- [ ] `local_schema_migrator.dart` — runs during updates
- [ ] `local_health_checker.dart` — decides rollback
- [ ] `update_acknowledgement_store.dart` — persistence
- [ ] `firestore_update_source.dart` — reads published manifests
- [ ] `app_bootstrap.dart` — wiring
- [ ] Add `fake_cloud_firestore` as a dev dependency (approved, never added)
- [ ] `offline_capability.dart` — pure, cheap
- [ ] Optional: widget tests for the remaining feature screens

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