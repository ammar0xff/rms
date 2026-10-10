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
