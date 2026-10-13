# Architecture

Offline-first, role-based, multi-device, multi-branch.

## Layers

```
Flutter App (POS | Kitchen | Delivery | Manager | Accounting)
        │
Feature Logic / Domain Rules / Permissions
        │
Repository Layer
        │
Local Database + Transactional Outbox
        │
Sync Engine / Conflict Resolver / Retry Policy
        │
Connectivity Available
        │
Firebase Auth / Cloud Functions ──> Cloud Firestore

Local Print Adapter ──> Local / Network Printer
```

## Principles
1. **Local-first** — eligible operations read/write the local DB first.
2. **Transactional outbox** — a business change and its sync command commit atomically.
3. **Idempotent sync** — every command carries a stable idempotency key; backend refuses duplicates.
4. **Explicit state** — local-only vs server-confirmed is always distinguishable.
5. **Independent statuses** — business, payment, settlement, print and sync status are separate.
6. **Conflict-aware** — financial conflicts are reviewed, never last-write-wins.
7. **Safe migration & rollout** — schema migrations preserve pending transactions; backend ships Expand → Migrate → Contract.

## Bootstrap & configuration
`main.dart` → `bootstrapApp()` resolves `AppServices` and hands them to `RmsApp`, which exposes them
through an `AppScope` inherited widget.

- **Config** — `core/config/firebase_config.dart` reads `FIREBASE_*` values from `--dart-define`.
  No keys are committed. `APP_ENV` selects the environment (dev/prod → separate Firebase projects).
- **Graceful degradation** — if Firebase is unconfigured or init fails, the app uses
  `DemoAuthRepository` and mock data so builds, tests and the live demo keep working.
- **Auth** — `data/repositories/auth_repository.dart` defines the boundary; `FirebaseAuthRepository`
  (backend) and `DemoAuthRepository` (local) implement it. `AuthGate` gates the shell and shows
  `SignInScreen` when signed out.
- **Version/diagnostics** — `core/config/app_version.dart` and `core/logging/app_logger.dart`
  provide version metadata and non-secret logging; surfaced in Settings.
- **Local store** — `data/local/local_database.dart` opens a sembast database (file on native via
  `path_provider`, IndexedDB on web); `platform/db_factory_*.dart` is selected by conditional import
  and falls back to an in-memory store. Opening is independent of Firebase and never blocks startup.
- **Order repository** — `data/repositories/local_order_repository.dart` writes an order and its
  outbox entry in a single transaction and exposes `applySynced` for the sync engine's completion
  callback.

> Note: the PRD names SQLite/Drift. Phase 0 uses **sembast** to avoid a code-generation step
> (`build_runner`) that cannot run in this environment; the transactional-outbox contract is
> unchanged. Swapping the store later only touches `data/local/`.


## Key local entities
- `localOrders`
- `outboxOperations`
- `syncConflicts`
- `localPrintJobs`
- `localAppMetadata`
- `deliveries` / `drivers` / `collections` (Phase 2)
- `cashSessions` / `approvals` / `audit` / `meta` / `config` (Phase 3)
- `inventory` / `stockMovements` / `suppliers` / `purchases` (Phase 4)
- `branches` / `branchAggregates` (Phase 4)

## Phase 3 — accounting, administration & controlled upgrades
- **Cash sessions** — `data/repositories/local_cash_session_repository.dart` derives the expected
  drawer total from cash payments + cash collections in the session window and queues
  `openCashSession` / `closeCashSession` commands; a session is synced only on acknowledgement.
- **Approvals** — `data/repositories/local_approval_repository.dart` queues refund requests without
  moving money; approval writes the correcting negative payment in the same transaction as the
  decision and is idempotent, so a retried decision can never double-post.
- **Audit** — `data/local/audit_log.dart` is append-only and receives rows through the caller's
  transaction, so financial operations and their audit events commit together.
- **Migrations** — `data/local/migrations/` implements forward-only steps; each step and its version
  bump (`meta.schemaVersion`) commit in one transaction, and the outbox is never touched, so pending
  offline work survives a release upgrade.
- **Feature flags** — `data/repositories/local_feature_flag_repository.dart` caches the last
  server-provided `ReleaseManifest`; flags gate optional workflows but never override a backend
  capability check.

## Phase 4 — inventory & advanced operations
- **Stock ledger** — `data/repositories/local_inventory_repository.dart` appends signed movements in
  one transaction with the cached balance, the outbox command and the audit row. Because relative
  movements commute, on-hand stays consistent under concurrent offline edits.
- **Conflict-aware counts** — a physical count carries the item revision it was based on; a stale
  count is flagged (`conflict` item status + a `stockCountConflict` outbox entry) and never
  overwrites a newer balance.
- **Sync reconciliation** — an acknowledged movement is marked synced and its item synced only once
  no movements remain pending.
- **Purchasing** — `data/repositories/local_purchase_repository.dart` receives an order by posting one
  `receipt` movement per line through the ledger and adding the order total to the supplier's payable in
  the same transaction that marks the order received, so a retried receive is idempotent and can never
  double the stock. An open order can also be cancelled, which closes the intent locally without
  touching stock; a received order cannot be cancelled.
- **Suppliers** — `data/repositories/local_supplier_repository.dart` is a local-first directory that
  carries the running amount owed: receiving a purchase raises it and `recordSupplierPayment` lowers it.
  Payments refuse to exceed the outstanding payable, and each receipt or payment queues an outbox
  command plus an audit row.
- **Reporting** — `data/repositories/local_reports_repository.dart` composes the local repositories
  into one pure `ReportsSnapshot` (`domain/models/report.dart`). It reads the outbox for freshness
  and exports CSV; because every source is append-only, a report stays consistent under concurrent
  offline operations and long connectivity gaps.
- **Automated delivery assignment** — `domain/assignment/delivery_assignment.dart` is a pure,
  deterministic planner (least-loaded *available* courier, ties broken by name). When the cached
  `delivery_auto_assign` flag permits it, `LocalDeliveryRepository.autoAssignWaiting` applies the
  whole plan in one transaction; the assignment stays provisional and the backend remains
  authoritative, so a stale reassignment is flagged rather than overwritten.
- **Multi-branch consolidation** — `data/repositories/local_branch_repository.dart` owns the branch
  directory and the cached per-branch aggregates, and folds them with the device's live report
  read-model into one `ConsolidationSnapshot` (`domain/models/branch.dart`). The merge is a pure
  function, so the same inputs always produce the same totals; the device's branch is read live and
  other branches fall back to their last synced aggregate, which keeps cross-branch reporting
  consistent offline and marks stale/missing branches instead of counting them as zero. The
  dashboard's branch-status card reads this same snapshot, so the home screen shows the live
  own-branch plus cached-peers picture without any hardcoded figures.
- **Migrations** — v3 `stock-ledger` introduces the ledger; v4 `purchasing` introduces suppliers and
  purchase orders; v5 `multi-branch` introduces the branch directory and consolidation aggregates.
  Each stamps defaults on pre-existing records and never touches the outbox.

## Phase 5 — Firebase update delivery
The v1.2 addendum turns Firebase into the release control plane: it publishes the manifest,
distributes or references the artifact, and records rollout state. The first slice is the pure client
half, so the eligibility rules are verifiable without touching Firebase, secrets or installers.

- **Release-manifest contract** — `domain/models/update_manifest.dart` models one immutable release
  per platform/channel/version: the artifact reference, size and SHA-256 (plus optional signature); a
  rollout percentage; `draft/staged/active/paused/revoked` status; `optional/recommended/mandatory`
  severity with a `forceAfter` deadline; optional cohort scoping by branch or device group; and the
  compatibility ranges (backend version, local schema, required migration). It is parsed defensively:
  a malformed or newer-schema document yields a `ManifestParseError` rather than a half-populated
  manifest. It is distinct from the cached capability manifest, which only carries feature flags and
  never gates artifact delivery.
- **Update decision engine** — `domain/update/update_decision.dart` is a pure function of the cached
  manifest and the device context. It reports `upToDate`, `optional`, `recommended`, `mandatory`, or
  `ineligible` with the first failed gate (`platformMismatch`, `expired`, `alreadyInstalled`,
  `rolloutExcluded`, `backendIncompatible`, `schemaIncompatible`, …). Partial rollouts use a
  deterministic cross-platform Jenkins hash of the device/branch seed, so a device always lands in the
  same bucket; a passed `forceAfter` escalates an optional release to mandatory.
- **Local-work readiness gate** — `domain/update/update_readiness.dart` implements AC-35. A pure
  `LocalWorkSnapshot` (pending, in-progress, retryable, conflict, user-action and rejected counts)
  feeds `UpdateReadinessEngine`, which withholds an install while any work is outstanding: it reports
  `awaitingSync` when online, `offlineBacklog` when offline, `needsAcknowledgement` for work the
  backend rejected, and `ready` only when nothing would be dropped. A mandatory release installs as
  soon as, but not before, the backlog clears; nothing here downloads, installs or mutates the outbox.
- **Cached and surfaced** — `data/repositories/local_update_repository.dart` stores the document in the
  config store, so wiring it in needs no schema migration; the settings screen resolves the device
  platform/channel/branch through `core/config/device_update_context.dart`, classifies the cached
  release and renders the verdict, the failed gate and the rollout bucket.
- **Platform delivery is not implemented** — the decision, readiness and lifecycle layers above are
  complete, but there is no `ArtifactDownloader` or `UpdateInstaller` for any platform. The settings
  screen states this rather than implying a download will happen. Web deliberately does **not** take
  artifact updates: it ships through GitHub Pages deploys on its own cadence, so the manifest's
  artifact, checksum and rollback fields go unused there. Delivery is mobile/desktop only, behind the
  existing interfaces. A Flutter web install has no real mechanism short of a service worker, and the
  migration and health-check steps that follow an install could not run in the same session after a
  plain reload — so implementing the web path as-is would produce something that looks finished and
  is not.
- **Acknowledgement** — `domain/update/update_acknowledgement.dart` lets an operator sign off on
  stuck work (conflicts, user-action and permanently-rejected records) that can never sync. It is
  scoped to the count reviewed, so work appearing later re-blocks the install rather than riding a
  stale sign-off, and it never waives unsynced work, which can still reach the backend.
- **Store contracts** — the settings screen depends on `UpdateStatusStore`, `ReleaseAuditTrail` and
  `UpdateAcknowledgementStore` (interfaces in `data/local/update_store_contracts.dart`) plus
  `OutboxAccess`, rather than the Sembast implementations. A `testWidgets` case driving a real
  Sembast database does not settle under the widget-test binding and hangs the suite instead of
  failing, so store-backed UI is tested against in-memory fakes.

## Releases and platform delivery

Two update paths publish the same manifest shape, so a client cannot tell them apart:

- **Build on demand** — `.github/workflows/release.yml`, dispatched by hand. It builds the current
  repository, hashes the artifact, uploads it to Cloud Storage and writes the manifest document.
  Manual on purpose: publishing changes what every enrolled device is offered, so it must not run
  on every push, and a missing secret must never break the normal build.
- **Bring your own artifact** — the same publisher, `tool/publish_release.mjs`, invoked with
  `--reference` against an artifact already in Storage. Nothing is uploaded; only the manifest is
  written.

The publisher derives the next `buildNumber` from what is already published rather than trusting the
caller. Android refuses an update whose version code is not strictly higher than the installed one,
so a re-run must always produce something installable.

`tool/publish_release.mjs` emits exactly `UpdateManifest.toRecord()`. The two must stay in step: the
client treats a document it cannot parse as absent, so a field rename would silently stop every
device being offered updates rather than fail loudly.

### Required secrets

None of these exist yet; the release workflow fails with a clear message until they are added.

| Secret | Purpose |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Service-account JSON with Storage **write** and Firestore **write** access. Without it nothing can be published. |
| `FIREBASE_PROJECT_ID` | Target project, used for the default bucket and Admin SDK initialisation. |

### Signing

Every artifact currently builds unsigned — Android with the debug key, desktop and macOS without an
identity. A real update requires stable signing:

- **Android** — a release keystore. The package name (`dev.rms.app`) and signing key together
  identify an install. Changing either after a release forces an uninstall that discards all local
  data, so both are fixed now, before the first release.
- **Windows** — an Authenticode certificate, or SmartScreen will warn on every update.
- **macOS** — an Apple Developer identity and notarisation, or Gatekeeper will block it.

Signing keys must live in CI secrets, never in the repository.
- Tests: `semantic_version_test.dart`, `update_manifest_test.dart`, `update_decision_test.dart`,
  `update_readiness_test.dart`, `update_repository_test.dart`, `settings_update_test.dart`.


## Sync engine responsibilities
- Detect connectivity and confirm reachability.
- Process pending operations in dependency order.
- Retry transient failures with exponential backoff + jitter.
- Enforce idempotency; record acknowledgments.
- Detect conflicts; resume after restart; surface permanent failures.
