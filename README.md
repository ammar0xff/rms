# RMS — Restaurant Management System

[![CI](https://github.com/ammar0xff/rms/actions/workflows/ci.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/ci.yml)
[![Deploy web](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/ammar0xff/rms/actions/workflows/deploy-pages.yml)
[![Live demo](https://img.shields.io/badge/demo-ammar0xff.github.io%2Frms-F5A524)](https://ammar0xff.github.io/rms/)

Cross-platform, **offline-first** restaurant management system.
Flutter frontend, Firebase backend, local-first persistence with transactional outbox and idempotent synchronization.

> Status: **Phase 0 — Technical Foundation** (in progress). Flutter architecture, build-time
> Firebase configuration, authentication, version/diagnostics, and the **local-first persistence
> layer (document store + transactional outbox + idempotent sync engine)** are in place; screens
> still render mock data until repositories are wired to the UI. Source of truth for behavior is
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
- `InMemorySyncTransport` dedupes on `idempotencyKey`, proving retries never duplicate.
- `test/offline_sync_test.dart` covers: create offline → restart (reopen the same file) → reconnect →
  sync → replay without duplicates.

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
      local/            # transactional outbox models
      mock/             # mock data used by the UI (demo mode)
      repositories/     # auth repository (Firebase + demo)
      sync/             # sync engine, retry, conflict resolver
    domain/
      models/           # order, app user, ...
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
- **POS** — menu grid, cart, order types, offline banner, local-first save
- **Kitchen (KDS)** — queued / preparing / ready columns, local tickets
- **Delivery** — deliveries, drivers, offline collections, settlement queue
- **Accounting** — cash session, approvals, append-only ledger
- **Menu / Inventory / Customers** — management tables
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

Dependencies: `firebase_core`, `firebase_auth`, `cloud_firestore`, `connectivity_plus`, `uuid`.
Still planned for later phases: `drift` + `sqlite3_flutter_libs` (local persistence), `flutter_local_notifications` (or platform print adapter).
