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
    data/
      local/            # local DB + transactional outbox
      repositories/
      sync/             # sync engine, retry, conflict resolver
    domain/
      models/
      offline/          # offline capability policy
    features/           # pos, kitchen, delivery, manager, accounting
docs/
test/
```

## Getting started
Requires the Flutter SDK (not yet installed on this machine; on Garuda/Arch install via AUR).

```bash
flutter pub get
flutter run
flutter test
```

Planned dependencies (Phase 0): `drift`, `sqlite3_flutter_libs`, `uuid`, `connectivity_plus`, `firebase_core`, `cloud_firestore`, `firebase_auth`, `flutter_local_notifications` (or platform print adapter).
