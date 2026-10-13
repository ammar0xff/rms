# RMS — Restaurant Management System

[![CI](https://github.com/ammar0xff/rms/actions/workflows/ci.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/ci.yml)
[![Deploy web](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml)
[![Live demo](https://img.shields.io/badge/demo-ammar0xff.github.io%2Frms-F5A524)](https://ammar0xff.github.io/rms/)

Cross-platform, **offline-first** restaurant management system.
Flutter frontend, Firebase backend, local-first persistence with transactional outbox and idempotent synchronization.

> Status: **Phase 4 — Inventory and Advanced Operations**. Phase 0 (local-first
> persistence: document store + transactional outbox + idempotent sync engine) and Phase 1
> (POS, menu cache, kitchen KDS, local printing, sync monitoring) are in place, together with
> conflicts, settings and server-assigned order identity. Phase 2 adds offline delivery events,
> an append-only collection log, conflict-aware reassignment, and an outstanding settlement queue
> that is finalized only on a server acknowledgement. Phase 3 adds cashier drawer sessions,
> refund/payment approvals, an append-only audit trail, forward-only local schema migrations, and
> cached release manifests with server-controlled feature flags. Phase 4 begins with an offline
> stock ledger: append-only movements whose sum is the on-hand balance, and conflict-aware physical
> counts that are flagged for review rather than overwriting a newer balance; purchasing raises and
> receives supplier orders that post straight into that ledger; reporting builds offline read-model
> snapshots from those append-only stores with freshness and CSV export; automated delivery
> assignment provisionally assigns waiting jobs to the least-loaded courier when a server flag
> permits it; and multi-branch consolidation merges the device's live figures with every other
> branch's last synced aggregate, so cross-branch reporting keeps working offline. Phase 5 begins the
> v1.2 update-delivery work with a pure release-manifest contract and a client update decision engine
> that classifies a cached release — offline — as optional, recommended, mandatory or ineligible
> before any artifact is fetched. Source of truth for behavior is
> `docs/Restaurant_Management_System_PRD_v1.1.pdf`.
>
> **Live demo:** https://ammar0xff.github.io/rms/ (built and deployed from `main` via GitHub Actions).

## Docs
- `docs/Restaurant_Management_System_PRD_v1.1.pdf` — full PRD v1.1
- `docs/Restaurant_Management_System_PRD_v1.1.xmind` — mind map of the PRD
- `docs/architecture.md` — architecture overview
- `docs/offline-capability-matrix.md` — what works offline

## Stack
| Area | Choice | Status |
| --- | --- | --- |
| Frontend | Flutter / Dart | implemented |
| Backend | Firebase Auth, Cloud Firestore | wired, config via `--dart-define` |
| Local persistence | sembast document store (IndexedDB on web, file on native) | implemented (Phase 0) |
| Platforms | Windows, macOS, Linux, Android, iOS, Web | web deployed |

## Firebase configuration
The app never ships committed project keys. Configuration is injected at build time and the app
falls back to a fully working **demo mode** (mock data + local sessions) when it is absent:

```bash
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_APP_ID=...
```

The GitHub Pages deploy reads the same keys from repository **Secrets** (`FIREBASE_*`); until they
are set the live site stays in demo mode. Required console setup: enable **Email/Password** auth,
create a **Firestore** database, and authorize the `ammar0xff.github.io` domain.


## Local persistence & sync (Phase 0)
The PRD specifies SQLite/Drift; this phase uses **sembast** instead — a schemaless document store that
needs **no code generation** (`build_runner`), so the app builds and tests on any machine and on the
web (IndexedDB). The outbox/transaction semantics the PRD requires are preserved:

- `LocalOrderRepository.createOrder` commits the order record **and** its outbox entry in one
  `db.transaction`, so a crash cannot leave an unsynced order without its sync command.
- `SyncEngine` drains pending outbox entries; `SyncCoordinator` guards against concurrent passes.
- `SyncService` auto-syncs on connectivity changes (reconnect trigger + catch-up on start).
- `FirestoreSyncTransport` writes to `sync_operations` with **doc id = `idempotencyKey`** for deduplication.
- `InMemorySyncTransport` dedupes on `idempotencyKey`, proving retries never duplicate.
- Tests: `offline_sync_test.dart`, `sync_test.dart`, `sync_service_test.dart`, `connectivity_monitor_test.dart`.
- `test/offline_sync_test.dart` covers: create offline → restart (reopen the same file) → reconnect →
  sync → replay without duplicates.

## Accounting, administration & controlled upgrades (Phase 3)
All Phase 3 writes follow the same rule as the rest of the app: the business record, its outbox
command and its audit row are committed in **one** transaction, so money never moves without a
trace and pending offline work is never lost by an upgrade.

- **Cash sessions** (`LocalCashSessionRepository`) — opening a drawer queues `openCashSession`;
  closing counts the drawer and queues `closeCashSession`. Expected cash = opening float + cash
  payments + cash collections in the session window; variance = counted − expected. A session is
  only marked synced once the backend acknowledges its command.
- **Approvals** (`LocalApprovalRepository`) — a refund request posts **nothing**; it writes an
  approval row, an outbox command and an audit event. Approval writes the correcting negative
  payment (and its own `recordPayment` command) atomically and is **idempotent** (a decided
  request is returned unchanged, so a retry can never double-post).
- **Audit log** (`AuditLog`) — append-only, keyed by event id, written in the same transaction as
  the operation it describes (`payments`, `collections`, reassignment conflicts, settlements).
- **Local migrations** (`LocalMigrationRunner`) — forward-only steps that each run in a
  transaction together with their own version bump (stored in `LocalStores.meta` under
  `schemaVersion`); a failure rolls the step back and keeps the prior version. Migrations never
  touch the outbox, so pending operations survive a schema upgrade.
- **Release manifest & feature flags** (`LocalFeatureFlagRepository`) — the last manifest is cached
  locally and read offline; flags gate optional workflows but never override a backend capability
  check. `ReleaseManifest` also carries the update channel, minimum supported version and rollout.
- Tests: `migration_test.dart`, `audit_log_test.dart`, `cash_session_test.dart`,
  `approval_repository_test.dart`, `feature_flags_test.dart`, `release_upgrade_test.dart` (the last
  one proves pending offline delivery work survives a schema upgrade).

## Inventory & advanced operations (Phase 4)
The stock ledger follows the same offline-first contract as the rest of the app: a movement, its
outbox command and its audit row commit in **one** transaction, and on-hand is always the sum of the
ledger.

- **Stock ledger** (`LocalInventoryRepository`) — `recordMovement` appends a signed movement and
  updates the cached balance atomically. Relative movements commute, so concurrent offline edits
  from several devices can never corrupt the total.
- **Conflict-aware counts** (`adjustToCount`) — a physical count carries the item revision it was
  based on; a stale count is kept for explicit review (item marked `conflict`, a `stockCountConflict`
  outbox entry, a `stockConflict` audit row) instead of silently overwriting a newer balance.
- **Sync reconciliation** — on acknowledgement a movement is stamped synced and its item is marked
  synced only once no movements for it remain pending.
- **Purchasing** (`LocalPurchaseRepository`) — raise an order against a cached supplier, receive it
  offline, or cancel it while it is still open. Receiving posts one `receipt` movement per line through
  the stock ledger and adds the order total to the supplier's payable in the **same** transaction that
  marks the order received, so a retried receive can never double the stock; cancelling an open order
  only closes the intent locally and never touches stock.
- **Suppliers** (`LocalSupplierRepository`) — local-first directory carrying the running amount owed:
  it rises when a purchase is received and falls when `recordSupplierPayment` is called, which refuses
  to overpay. Both the receipt and the payment queue an outbox command and an audit row.
- **Reporting** (`LocalReportsRepository`) — folds the append-only sources (orders, payments,
  collections, cash sessions, stock ledger, purchases, suppliers) into one self-consistent
  `ReportsSnapshot`; it reads the outbox for freshness (last acknowledgement plus
  pending/failed/conflict counts) and exports a flat CSV.
- **Automated delivery assignment** (`DeliveryAssignmentPolicy` +
  `LocalDeliveryRepository.autoAssignWaiting`) — when the cached `delivery_auto_assign` flag
  permits it, the device picks the least-loaded *available* courier for every waiting job, oldest
  first, and applies the batch in one transaction. The plan is a pure function of the cached roster
  and open jobs, so two offline terminals agree; the backend stays authoritative, and a stale
  reassignment is still flagged rather than silently overwritten.
- **Multi-branch consolidation** (`LocalBranchRepository` + `ConsolidationSnapshot`) — the device's
  own branch is read **live** from the append-only stores, while every other branch contributes its
  last synced aggregate; the pure `ConsolidationSnapshot.from` merges the two in a deterministic
  order and sums the network totals. Branches with a stale or missing aggregate are marked, never
  counted as zero, so the consolidated view stays consistent through an outage and only its
  *freshness* degrades.
- **Migrations** — v3 (`stock-ledger`) introduces the ledger; v4 (`purchasing`) introduces suppliers
  and purchase orders; v5 (`multi-branch`) introduces the branch directory and the consolidation
  aggregates. Each stamps defaults on pre-existing records and never touches the outbox, so pending
  offline work survives the upgrade.
- Tests: `inventory_repository_test.dart`, `purchasing_repository_test.dart`, `reports_test.dart`,
  `reports_repository_test.dart` (proves reporting stays consistent after a concurrent offline
  movement), `delivery_assignment_test.dart` and `delivery_auto_assign_test.dart` (deterministic,
  conflict-aware offline auto-assignment), `consolidation_test.dart` and `branch_repository_test.dart`
  (live-plus-cached cross-branch consolidation), plus the v3/v4/v5 cases in `migration_test.dart` and
  `release_upgrade_test.dart`.

## Firebase update delivery (Phase 5)
Firebase becomes the release control plane: it publishes the manifest and references the verified
artifact. The first slice is the pure client half, so the rules are testable without Firebase,
secrets or installers.

- **Release-manifest contract** (`domain/models/update_manifest.dart`) — one immutable release per
  platform/channel/version, carrying the artifact reference, size and SHA-256, rollout percentage,
  lifecycle status, severity and the backend/schema compatibility ranges. It is parsed defensively: a
  malformed or newer-schema document is rejected instead of partially honoured.
- **Update decision engine** (`domain/update/update_decision.dart`) — a pure function of the cached
  manifest and the device context. It returns `upToDate`, `optional`, `recommended`, `mandatory` or
  `ineligible` with the first failed gate, and places partial rollouts with a deterministic
  cross-platform cohort bucket. Installing is out of scope for this slice; the engine only classifies
  and flags whether a migration is required.
- **Local-work readiness gate** (`domain/update/update_readiness.dart`) — the install gate for AC-35. A
  pure `LocalWorkSnapshot` (pending, in-progress, retryable, conflict, user-action and rejected counts)
  feeds `UpdateReadinessEngine`, which withholds an install while any work is outstanding: it reports
  `awaitingSync` when online, `offlineBacklog` when offline, `needsAcknowledgement` for work the
  backend rejected, and `ready` only when nothing would be dropped. A mandatory release never bypasses
  it — it installs as soon as, but not before, the backlog clears.
- **Cached and surfaced** — `LocalUpdateRepository` keeps the manifest in the local config store (no
  new schema), and the Settings screen resolves the device platform/channel/branch, classifies the
  cached release and renders the verdict plus, when blocked, the failed gate. Downloading and
  installing the verified artifact is the next slice.
- Tests: `semantic_version_test.dart`, `update_manifest_test.dart`, `update_decision_test.dart`,
  `update_readiness_test.dart`, `update_repository_test.dart`, `settings_update_test.dart`.

## Layout
```
lib/
  main.dart
  src/
    app.dart
    core/
      config/           # build-time config (Firebase) + version metadata
      di/               # AppServices container + bootstrap
      logging/          # structured logger
      state/            # sync monitor
      theme/            # colors, text, spacing, Material theme
      widgets/          # app shell, table, stat cards, charts, primitives
    data/
      local/            # document store, outbox models, audit log, migrations/
      mock/             # mock data used by the UI (demo mode)
      repositories/     # auth repository (Firebase + demo)
      sync/             # sync engine, retry, conflict resolver
    domain/
      models/           # order, payment, delivery, cash session, approval, stock, ...
      offline/          # offline capability policy
      assignment/       # pure delivery-assignment planner
      update/           # pure release/update decision engine
    features/
      auth/ dashboard/ pos/ kitchen/ delivery/
      accounting/ menu/ inventory/ purchasing/ customers/ reports/
      sync/ conflicts/ settings/ common/
docs/
test/
```

## Screens
- **Dashboard** — hero KPI, sales-by-hour, alerts, sync health, branch status
- **POS** — menu grid from the local cache, cart, order types, offline banner, local-first save
- **Kitchen (KDS)** — queued / preparing / ready columns, local tickets routed from POS orders
- **Delivery** — deliveries, drivers, flag-gated auto-assignment, offline collections, settlement queue
- **Accounting** — cash session, approvals, append-only ledger
- **Menu** — cached catalog with offline reads · **Inventory** — offline stock ledger, movements
  and conflict-aware counts · **Purchasing** — suppliers and offline purchase orders that post to the
  ledger on receipt, with cancel for open orders and supplier payments against the running payable ·
  **Customers** — management tables
- **Reports** — offline read-model: sales window trend, payment mix, inventory, purchasing and cash
  reconciliation, freshness vs. last sync, and CSV export
- **Branches** — multi-branch consolidation: network KPIs and a per-branch table showing each
  branch's orders, sales, collection, stock and freshness, with live/cached sourcing and CSV export
- **Sync Center** — outbox operations, sync order, idempotency/retry policy
- **Conflicts** — detected conflicts and per-entity resolution strategy
- **Settings** — version visibility, updates, migrations, flags, offline policy

## Design
Dense, dark, professional dashboard UI (Vercel/Linear influence):
three-tier elevation, 1px borders, no glass/gradient/glow, tabular numerals,
small type scale, dot-based statuses, warm amber accent (domain-matched).
Tokens live in `lib/src/core/theme/` and every rule is documented, with its
source reference, in `docs/DESIGN.md`.

## Getting started
Requires the Flutter SDK (not yet installed on this machine; on Garuda/Arch install via AUR).

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```

Dependencies: `firebase_core`, `firebase_auth`, `cloud_firestore`, `connectivity_plus`, `uuid`, `sembast`, `sembast_web`, `path`, `path_provider`.
Outbox/sync: `SyncEngine`, `SyncCoordinator`, `SyncService`, `FirestoreSyncTransport`, `InMemorySyncTransport`.
