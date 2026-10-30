# REMEDIATION ROADMAP & ENGINEERING ACTION PLAN

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1`  
**Audit Date:** 2026-10-26  
**Auditor:** Principal Software Architect & Release Manager  

---

## 1. Remediation Phases Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│  Phase R0: Critical Security, Financial & Release Blockers (Immediate) │
│  Estimated: 14 - 18 Hours                                              │
├────────────────────────────────────────────────────────────────────────┤
│  Phase R1: Core Functional Gaps & Hardware Printing (Near-Term)        │
│  Estimated: 16 - 22 Hours                                              │
├────────────────────────────────────────────────────────────────────────┤
│  Phase R2: Reliability, Platform Compatibility & Performance (Mid-Term)│
│  Estimated: 12 - 16 Hours                                              │
├────────────────────────────────────────────────────────────────────────┤
│  Phase R3: Polish, Observability & Secondary PRD Extensions (Post-Rel) │
│  Estimated: 16 - 24 Hours                                              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Phase R0: Immediate Release Blockers

### Task R0-1: Harden Cloud Firestore Security Rules
- **Task ID:** `TASK-R0-1`
- **Related Findings:** `SEC-001`
- **Components / Files Affected:** [`firestore.rules`](file:///home/ammar/PIE/firestore.rules)
- **Proposed Change:** Restrict write permissions on `approvals`, `cashSessions`, `inventoryItems`, and `stockMovements` strictly to `isPrivileged()`. Add update validations on `orders` and `payments` to prevent unauthorized role escalation or client amount tampering.
- **Dependencies:** None.
- **Regression Tests:** Create Firestore unit test suite verifying that cashier and driver tokens are denied when updating `approvals` or `cashSessions`.
- **Acceptance Criteria:** Unprivileged users receive `permission-denied` when mutating financial and approval collections via direct SDK.
- **Estimated Effort:** 4 - 6 hours.
- **Priority Order:** 1 (Highest).

---

### Task R0-2: Eliminate Fallback Manager PIN & Enforce Rate Limiting
- **Task ID:** `TASK-R0-2`
- **Related Findings:** `SEC-002`
- **Components / Files Affected:** [`lib/src/data/services/pin_service.dart`](file:///home/ammar/PIE/lib/src/data/services/pin_service.dart)
- **Proposed Change:** Remove the `pin.trim() == '1234'` fallback. Return `false` (fail closed) if the manager PIN document is unconfigured or unreachable. Introduce a progressive in-memory lockout timer (3 wrong attempts = 30s lock, 5 wrong attempts = 5m lock).
- **Dependencies:** None.
- **Regression Tests:** Add unit tests in `test/pin_service_test.dart` asserting that `'1234'` returns `false` on cache miss and verify lockout delay.
- **Acceptance Criteria:** Unset or unreachable PIN refuses authorization; rapid incorrect entries trigger lockout.
- **Estimated Effort:** 2 - 3 hours.
- **Priority Order:** 2.

---

### Task R0-3: Connect Drawer Settlement Drops to Cash Session Ledger
- **Task ID:** `TASK-R0-3`
- **Related Findings:** `FIN-001`
- **Components / Files Affected:** [`lib/src/features/accounting/drawer_settlement_dialog.dart`](file:///home/ammar/PIE/lib/src/features/accounting/drawer_settlement_dialog.dart), [`lib/src/data/repositories/local_cash_session_repository.dart`](file:///home/ammar/PIE/lib/src/data/repositories/local_cash_session_repository.dart), [`lib/src/domain/models/cash_session.dart`](file:///home/ammar/PIE/lib/src/domain/models/cash_session.dart)
- **Proposed Change:** Add `recordCashDrop` to `CashSessionRepository`. Persist dropped cash in `cash_drops` store, update `CashSession.droppedCash`, and deduct from `expectedCash`.
- **Dependencies:** None.
- **Regression Tests:** Add test in `test/cash_session_test.dart` verifying that `expectedCash` drops proportionally after settlement.
- **Acceptance Criteria:** Z-Report calculates `expectedCash = float + sales + collections - drops`, eliminating false shortages.
- **Estimated Effort:** 3 - 4 hours.
- **Priority Order:** 3.

---

### Task R0-4: Fix Stale Test Assertions in Driver Delivery Flow
- **Task ID:** `TASK-R0-4`
- **Related Findings:** `TEST-001`
- **Components / Files Affected:** [`test/ui/driver_delivery_flow_test.dart`](file:///home/ammar/PIE/test/ui/driver_delivery_flow_test.dart)
- **Proposed Change:** Update button label finder to `'عرض البون 🧾'` on line 62. Remove the deleted simulation play button assertion on line 341.
- **Dependencies:** None.
- **Regression Tests:** Run `flutter test test/ui/driver_delivery_flow_test.dart`.
- **Acceptance Criteria:** Suite passes 6/6 tests without failure.
- **Estimated Effort:** 1 hour.
- **Priority Order:** 4.

---

## 3. Phase R1: Core Functional Gaps & Printing

### Task R1-1: ESC/POS Arabic Shaping & Raster Printing
- **Task ID:** `TASK-R1-1`
- **Related Findings:** `COMPAT-001`
- **Components / Files Affected:** [`lib/src/domain/services/network_esc_pos_adapter.dart`](file:///home/ammar/PIE/lib/src/domain/services/network_esc_pos_adapter.dart)
- **Proposed Change:** Implement off-screen raster bitmap conversion for thermal receipt tickets, printing via ESC/POS `GS v 0` commands, or integrate an Arabic shaping and BiDi reordering pipeline with CP864 code-page encoding.
- **Dependencies:** None.
- **Regression Tests:** ESC/POS byte-level assertion test verifying connected Arabic glyph encoding.
- **Acceptance Criteria:** Standard thermal network receipt printers output legible, right-to-left connected Arabic text.
- **Estimated Effort:** 6 - 8 hours.
- **Priority Order:** 5.

---

### Task R1-2: Mirror Audit Log Entries to Cloud Firestore
- **Task ID:** `TASK-R1-2`
- **Related Findings:** `DATA-001`
- **Components / Files Affected:** [`lib/src/data/sync/record_mirror.dart`](file:///home/ammar/PIE/lib/src/data/sync/record_mirror.dart), [`firestore.rules`](file:///home/ammar/PIE/firestore.rules)
- **Proposed Change:** Add `'auditEntry' => 'audit_entries'` in `mirrorCollectionFor`. Add append-only rule for `audit_entries` in `firestore.rules`.
- **Dependencies:** Task R0-1.
- **Regression Tests:** Unit test asserting audit entry mirror push to Firestore.
- **Acceptance Criteria:** Local audit entries are mirrored to cloud and visible across manager consoles.
- **Estimated Effort:** 3 - 4 hours.
- **Priority Order:** 6.

---

### Task R1-3: Enforce Strict Two-Phase Blind Cash Count
- **Task ID:** `TASK-R1-3`
- **Related Findings:** `FIN-002`
- **Components / Files Affected:** [`lib/src/features/accounting/z_report_screen.dart`](file:///home/ammar/PIE/lib/src/features/accounting/z_report_screen.dart)
- **Proposed Change:** Hide `expectedCash` and `variance` during initial denomination entry. Reveal discrepancy only after the count has been submitted.
- **Dependencies:** None.
- **Regression Tests:** Widget test verifying expected cash is not visible during active denomination input.
- **Acceptance Criteria:** Cashiers cannot see the expected drawer total while counting banknotes.
- **Estimated Effort:** 3 - 4 hours.
- **Priority Order:** 7.

---

### Task R1-4: Recipe & BOM Inventory Depletion on POS Checkout
- **Task ID:** `TASK-R1-4`
- **Related Findings:** `GAP-002`
- **Components / Files Affected:** [`lib/src/domain/models/menu_item.dart`](file:///home/ammar/PIE/lib/src/domain/models/menu_item.dart), [`lib/src/data/repositories/local_order_repository.dart`](file:///home/ammar/PIE/lib/src/data/repositories/local_order_repository.dart), [`lib/src/features/pos/pos_checkout_dialog.dart`](file:///home/ammar/PIE/lib/src/features/pos/pos_checkout_dialog.dart)
- **Proposed Change:** Add recipe ingredient list to `MenuItemModel`. On POS order commit, automatically invoke `LocalInventoryRepository.recordMovement` with reason `StockMovementReason.sale`.
- **Dependencies:** None.
- **Regression Tests:** End-to-end checkout test asserting ingredient stock depletion.
- **Acceptance Criteria:** Stock levels on hand decrement automatically upon order finalization.
- **Estimated Effort:** 6 - 8 hours.
- **Priority Order:** 8.

---

## 4. Phase R2: Platform Compatibility & Performance

### Task R2-1: Configure Android Foreground Service for Background GPS Tracking
- **Task ID:** `TASK-R2-1`
- **Related Findings:** `COMPAT-002`
- **Components / Files Affected:** [`android/app/src/main/AndroidManifest.xml`](file:///home/ammar/PIE/android/app/src/main/AndroidManifest.xml), [`lib/src/domain/navigation/driver_location_service.dart`](file:///home/ammar/PIE/lib/src/domain/navigation/driver_location_service.dart)
- **Proposed Change:** Add `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` permissions. Configure a continuous location tracking notification for Android couriers during active delivery trips.
- **Dependencies:** None.
- **Regression Tests:** Verify manifest permissions and test background service lifecycle.
- **Acceptance Criteria:** Courier location updates continue streaming to dispatch when the phone screen is locked.
- **Estimated Effort:** 4 - 6 hours.
- **Priority Order:** 9.

---

### Task R2-2: Stream-Based Checksum Calculation in Artifact Verifier
- **Task ID:** `TASK-R2-2`
- **Related Findings:** `PERF-001`
- **Components / Files Affected:** [`lib/src/domain/update/artifact_verifier.dart`](file:///home/ammar/PIE/lib/src/domain/update/artifact_verifier.dart)
- **Proposed Change:** Refactor `ArtifactVerifier` to use `File.openRead().transform(sha256)` chunked streaming rather than loading the entire APK into memory.
- **Dependencies:** None.
- **Regression Tests:** Test artifact verifier with chunked stream simulator.
- **Acceptance Criteria:** Memory overhead remains under 5MB regardless of downloaded file size.
- **Estimated Effort:** 2 - 3 hours.
- **Priority Order:** 10.

---

### Task R2-3: Add Monotonic LWW Timestamp Checks in Inbound Sync
- **Task ID:** `TASK-R2-3`
- **Related Findings:** `SYNC-001`
- **Components / Files Affected:** [`lib/src/data/sync/inbound_sync_service.dart`](file:///home/ammar/PIE/lib/src/data/sync/inbound_sync_service.dart)
- **Proposed Change:** Compare `record['lastModifiedAt']` with local record timestamp before applying remote updates.
- **Dependencies:** None.
- **Regression Tests:** Inbound sync unit test testing out-of-order snapshot rejection.
- **Acceptance Criteria:** Stale remote snapshots do not overwrite newer local records.
- **Estimated Effort:** 2 - 3 hours.
- **Priority Order:** 11.

---

## 5. Phase R3: Polish & Secondary PRD Extensions

- **Task R3-1 (GAP-001):** Wire real cryptographically generated supervisor delegation OTP codes with 60-minute expiry (4 hours).
- **Task R3-2 (GAP-003):** Wire real cross-branch emergency order rerouting in `TriageScreen` (4 hours).
- **Task R3-3 (RELIAB-001):** Add HTTP ETag caching for GitHub release queries to avoid IP rate-limiting (2 hours).
- **Task R3-4 (CRM-002):** Implement customer loyalty point balance and credit ledger (6 hours).
