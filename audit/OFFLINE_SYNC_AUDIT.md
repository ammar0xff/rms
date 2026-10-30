# OFFLINE-FIRST & DISTRIBUTED SYNCHRONIZATION AUDIT REPORT

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1` (Section 6: Offline Architecture & Distributed Sync)  
**Audit Date:** 2026-10-26  
**Auditor:** Distributed Systems & Offline Storage Engineer  

---

## 1. Executive Offline Architecture Evaluation

PIE Operations implements a genuine **offline-first local-master architecture**. Unlike applications that rely on HTTP caching or temporary retry queues, PIE Operations commits all state changes directly to an embedded local database (Sembast) in atomic transactions. A dedicated background Transactional Outbox engine manages asynchronous propagation and acknowledgement fold-back with Cloud Firestore.

The offline architecture is highly robust, but contains specific edge-case risks in inbound snapshot ordering and sequence numbering under extended multi-day partitions.

---

## 2. Core Architecture Topology

```
┌────────────────────────────────────────────────────────┐
│                   LOCAL CLIENT TERMINAL                │
│                                                        │
│  ┌─────────────────┐       ┌────────────────────────┐  │
│  │   UI Feature    │ ────> │ Local Repository       │  │
│  │   (POS / Shift) │       │ (LocalOrderRepository) │  │
│  └─────────────────┘       └────────────────────────┘  │
│                                      │                 │
│              ┌───────────────────────┴───────────────┐ │
│              ▼                                       ▼ │
│  ┌────────────────────────┐         ┌───────────────┐│ │
│  │ Sembast Domain Store   │         │ Outbox Store  ││ │
│  │ (orders, payments, …)  │         │ (Pending Ops) ││ │
│  └────────────────────────┘         └───────────────┘│ │
│              ▲                               │       │ │
│              │ Inbound Snapshot              │ Drain │ │
│              │ (Guarded by Outbox)           ▼       │ │
│  ┌────────────────────────┐         ┌───────────────┐│ │
│  │ InboundSyncService     │         │ SyncEngine    ││ │
│  └────────────────────────┘         └───────────────┘│ │
└──────────────────▲───────────────────────────│─────────┘
                   │                           │
                   │ WebSocket Listeners       │ Batch Push
                   ▼                           ▼
┌────────────────────────────────────────────────────────┐
│                   CLOUD FIRESTORE                      │
│                                                        │
│   orders/     payments/     cashSessions/     counters/│
└────────────────────────────────────────────────────────┘
```

---

## 3. Transactional Outbox & State Guarantees

### 3.1 Two-Phase Local Write (Atomic Commit)
- **Implementation:** [`lib/src/data/repositories/local_order_repository.dart#L100-L150`](file:///home/ammar/PIE/lib/src/data/repositories/local_order_repository.dart#L100-L150).
- **Contract:** When an order is created, Sembast executes an atomic transaction `_db.transaction((txn) async { ... })`:
  1. The domain entity (`Order`) is saved to `LocalStores.orders`.
  2. The synchronization command (`OutboxEntry`) is saved to `LocalStores.outbox` with status `pending`.
- **Crash Recovery:** If the device loses power or the process is terminated mid-execution, either both records exist or neither exists. An order can never be committed without its corresponding outbox sync task.
- **Audit Verdict:** **PASS.**

### 3.2 Idempotency and Merge Semantics
- **Push Transport:** [`lib/src/data/sync/firestore_sync_transport.dart`](file:///home/ammar/PIE/lib/src/data/sync/firestore_sync_transport.dart).
- **Mechanism:** Every outbox mutation carries a client-generated UUID `localId`. Push operations write to Firestore documents matching this ID with `SetOptions(merge: true)`.
- **Result:** Network retransmissions, disconnections during ACK receipt, and repeated push attempts are completely idempotent.
- **Audit Verdict:** **PASS.**

### 3.3 Poison Message Isolation & Retry Backoff
- **Implementation:** [`lib/src/data/sync/retry_policy.dart`](file:///home/ammar/PIE/lib/src/data/sync/retry_policy.dart) & [`sync_engine.dart`](file:///home/ammar/PIE/lib/src/data/sync/sync_engine.dart).
- **Backoff:** Failed mutations execute exponential backoff with jitter (initial: 1s, max: 60s).
- **Poison Isolation:** After 5 consecutive unrecoverable failures (e.g. schema or permission error), the mutation is marked `poisoned` and quarantined to avoid blocking the outbox queue.
- **Audit Verdict:** **PASS.**

---

## 4. Inbound Synchronization & Conflict Analysis

### 4.1 Protection of Local Unpushed Mutations
- **Implementation:** [`lib/src/data/sync/inbound_sync_service.dart#L126-L132`](file:///home/ammar/PIE/lib/src/data/sync/inbound_sync_service.dart#L126-L132).
- **Mechanism:**
  ```dart
  final hasLocalPending = await _outbox.hasOutstandingFor(
    entityType: entityType,
    entityId: entityId,
  );
  if (hasLocalPending) continue; // Skip overwrite!
  ```
- **Result:** Remote inbound updates from other terminals never overwrite local edits that have not yet synced to the cloud.
- **Audit Verdict:** **PASS.**

### 4.2 Inbound Snapshot Ordering Risk (Finding SYNC-001)
- **Defect:** When an entity has *no* pending local mutation, incoming Firestore snapshots are applied unconditionally:
  ```dart
  await store.record(entityId).put(_db.db, record);
  ```
- **Vulnerability:** Firestore snapshots received over erratic wireless links can arrive out of order. If an older snapshot is delivered after a newer snapshot, the older state will overwrite the newer state because there is no timestamp or monotonic version check (`updatedAt` comparison).
- **Audit Verdict:** **PARTIAL.** Requires Last-Write-Wins (LWW) timestamp check before applying inbound updates.

---

## 5. 72-Hour Offline Operational Resilience Evaluation

The PRD mandates that a branch terminal must sustain normal operations through an extended 72-hour internet outage without data loss.

| Capability / Workflow | Operational Status Offline | Failure Mode / Risk Under Extended Outage |
| :--- | :--- | :--- |
| **POS Order Creation** | **FULLY FUNCTIONAL** | Orders save to Sembast and outbox queue queues mutations. |
| **Cash Drawer Gating & Shifts** | **FULLY FUNCTIONAL** | Cash sessions, floats, and Z-close operate locally. |
| **Kitchen Printing** | **FULLY FUNCTIONAL** | Local LAN raw socket printing does not require WAN/Internet. |
| **Customer Phone Directory** | **FULLY FUNCTIONAL** | Existing customer database is queried from local Sembast. |
| **Order Sequence Numbering** | **DEGRADES TO PROVISIONAL** | Uses `PROV-{terminalId}-{seq}`. Canonical numbers assigned upon reconnect. |
| **Manager PIN Verification** | **VULNERABLE (SEC-002)** | If cache miss occurs, falls back to `'1234'`. |
| **Courier GPS Navigation** | **PARTIALLY FUNCTIONAL** | GPS hardware works; map tiles require cached OSM tiles. OSRM fallback to straight line if server unreachable. |
| **Audit Log Persistence** | **VULNERABLE (DATA-001)** | Written to local disk; unmirrored to cloud. |

---

## 6. Recommendations for Offline Hardening

1. **Enforce Monotonic LWW in Inbound Sync:** In `InboundSyncService`, compare `record['lastModifiedAt']` against local record timestamp before applying `store.put`.
2. **Offline Tile Pre-Caching:** Bundle offline vector/raster map tiles for the branch delivery radius (15km) to prevent blank map tiles during delivery outages.
3. **Persist Canonical PIN Hash Locally:** Cache the manager PIN hash in secure hardware storage (`flutter_secure_storage`) rather than relying on Firestore cache.
