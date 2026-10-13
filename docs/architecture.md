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
  `receipt` movement per line through the ledger in the same transaction that marks the order
  received, so a retried receive is idempotent and can never double the stock.
- **Suppliers** — `data/repositories/local_supplier_repository.dart` is a local-first directory that
  carries the running amount owed.
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
  consistent offline and marks stale/missing branches instead of counting them as zero.
- **Migrations** — v3 `stock-ledger` introduces the ledger; v4 `purchasing` introduces suppliers and
  purchase orders; v5 `multi-branch` introduces the branch directory and consolidation aggregates.
  Each stamps defaults on pre-existing records and never touches the outbox.

## Sync engine responsibilities
- Detect connectivity and confirm reachability.
- Process pending operations in dependency order.
- Retry transient failures with exponential backoff + jitter.
- Enforce idempotency; record acknowledgments.
- Detect conflicts; resume after restart; surface permanent failures.
