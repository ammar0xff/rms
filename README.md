# RMS — Restaurant Management System

Cross-platform, **offline-first** restaurant management system.
Flutter frontend, Firebase backend, local-first persistence with transactional outbox and idempotent synchronization.

> Status: early scaffold (Phase 0). Source of truth for behavior is `docs/Restaurant_Management_System_PRD_v1.1.pdf`.

## Docs
- `docs/Restaurant_Management_System_PRD_v1.1.pdf` — full PRD v1.1
- `docs/Restaurant_Management_System_PRD_v1.1.xmind` — mind map of the PRD
- `docs/architecture.md` — architecture overview
- `docs/offline-capability-matrix.md` — what works offline

## Stack
| Area | Choice |
| --- | --- |
| Frontend | Flutter / Dart |
| Backend | Firebase Auth, Cloud Firestore, Cloud Functions, FCM, Cloud Storage |
| Local persistence | SQLite via Drift (or equivalent) |
| Platforms | Windows, macOS, Linux, Android, iOS, Web |

## Layout
```
lib/
  main.dart
  src/
    app.dart
    core/
      state/            # sync monitor
      theme/            # colors, text, spacing, Material theme
      widgets/          # app shell, table, stat cards, charts, primitives
    data/
      local/            # local DB + transactional outbox (models)
      mock/             # mock data used by the UI
      sync/             # sync engine, retry, conflict resolver
    domain/
      models/           # order, ...
      offline/          # offline capability policy
    features/
      dashboard/ pos/ kitchen/ delivery/
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
Tokens live in `lib/src/core/theme/`.

## Getting started
Requires the Flutter SDK (not yet installed on this machine; on Garuda/Arch install via AUR).

```bash
flutter pub get
flutter run
flutter test
```

Planned dependencies (Phase 0): `drift`, `sqlite3_flutter_libs`, `uuid`, `connectivity_plus`, `firebase_core`, `cloud_firestore`, `firebase_auth`, `flutter_local_notifications` (or platform print adapter).
