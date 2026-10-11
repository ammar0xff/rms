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

## Sync engine responsibilities
- Detect connectivity and confirm reachability.
- Process pending operations in dependency order.
- Retry transient failures with exponential backoff + jitter.
- Enforce idempotency; record acknowledgments.
- Detect conflicts; resume after restart; surface permanent failures.
