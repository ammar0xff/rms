# RMS — Restaurant Management System

[![CI](https://github.com/ammar0xff/rms/actions/workflows/ci.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/ci.yml)
[![Deploy web](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml)
[![Live demo](https://img.shields.io/badge/demo-ammar0xff.github.io%2Frms-F5A524)](https://ammar0xff.github.io/rms/)

Cross-platform, **offline-first** restaurant management system.
Flutter frontend, Firebase backend, local-first persistence with transactional outbox and idempotent synchronization.

> Status: **Phase 3 — Accounting, Administration and Controlled Upgrades**. Phase 0 (local-first
> persistence: document store + transactional outbox + idempotent sync engine) and Phase 1
> (POS, menu cache, kitchen KDS, local printing, sync monitoring) are in place, together with
> conflicts, settings and server-assigned order identity. Phase 2 adds offline delivery events,
> an append-only collection log, conflict-aware reassignment, and an outstanding settlement queue
> that is finalized only on a server acknowledgement. Phase 3 adds cashier drawer sessions,
> refund/payment approvals, an append-only audit trail, forward-only local schema migrations, and
> cached release manifests with server-controlled feature flags. Source of truth for behavior is
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
      models/           # order, payment, delivery, cash session, approval, ...
      offline/          # offline capability policy
    features/
      auth/ dashboard/ pos/ kitchen/ delivery/
      accounting/ menu/ inventory/ customers/ reports/
      sync/ conflicts/ settings/ common/
docs/
test/
```

## Screens
- **Dashboard** — hero KPI, sales-by-hour, alerts, sync health, branch status
- **POS** — menu grid from the local cache, cart, order types, offline banner, local-first save
- **Kitchen (KDS)** — queued / preparing / ready columns, local tickets routed from POS orders
- **Delivery** — deliveries, drivers, offline collections, settlement queue
- **Accounting** — cash session, approvals, append-only ledger
- **Menu** — cached catalog with offline reads · **Inventory / Customers** — management tables
- **Reports** — sales trend, category breakdown, payment mix
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
