# FINANCIAL INTEGRITY & ACCOUNTING AUDIT REPORT

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1` (Section 8: Cash, Shifts & Financial Accounting; Section 9: Delivery Dispatch & Custody)  
**Audit Date:** 2026-10-26  
**Auditor:** Restaurant POS & Financial Accounting Domain Expert  

---

## 1. Executive Accounting Evaluation

The financial engine of PIE Operations demonstrates good foundation in double-entry alignment between orders, payments, and cash sessions. The local-first Sembast persistence layer ensures that sales operations remain operational during network outages.

However, the audit identified **two significant financial accounting defects** that undermine drawer reconciliation and fraud prevention:
1. **Unrecorded Drawer Settlements (FIN-001):** Mid-shift cash drops to the main safe bypass the cash session ledger, causing false drawer shortages on shift close reports.
2. **Breach of Blind Cash Count (FIN-002):** The Z-Report counting screen displays the calculated drawer balance and live variance while the cashier is actively counting banknotes, facilitating pocketed cash concealment.

---

## 2. Shift & Drawer Lifecycle Analysis

```
┌──────────────────┐       ┌──────────────────────┐       ┌───────────────────────┐
│   Open Shift     │ ────> │   Trading & Sales    │ ────> │   Z-Report Cash Count │
│  (Opening Float) │       │ (Cash, Card, Drops)  │       │  (Counted vs Expected)│
└──────────────────┘       └──────────────────────┘       └───────────────────────┘
                                       │                              │
                                       ▼                              ▼
                             ┌──────────────────┐           ┌───────────────────┐
                             │ Drawer Drop      │           │ Variance Report   │
                             │ (Main Safe Drop) │           │ (Shortage/Surplus)│
                             └──────────────────┘           └───────────────────┘
```

### 2.1 Opening Float Gating
- **Implementation:** [`lib/src/features/shift/open_shift_dialog.dart`](file:///home/ammar/PIE/lib/src/features/shift/open_shift_dialog.dart) & [`lib/src/domain/models/cash_session.dart`](file:///home/ammar/PIE/lib/src/domain/models/cash_session.dart).
- **Rule Verification:** Sales operations on the POS are blocked until an active cash session is opened with an explicit opening float (default: 500.00 EGP).
- **Audit Verdict:** **PASS.** The session guard reliably locks the POS checkout button if no shift is open.

### 2.2 Mid-Shift Drawer Settlement Drops (Finding FIN-001)
- **Implementation:** [`lib/src/features/accounting/drawer_settlement_dialog.dart#L108-L135`](file:///home/ammar/PIE/lib/src/features/accounting/drawer_settlement_dialog.dart#L108-L135).
- **Mechanism:** When cash in the drawer exceeds safe thresholds (e.g., > 10,000 EGP), cashiers perform a cash drop to the main safe.
- **Defect:** The dialog only creates an `AuditEntry`:
  ```dart
  services.audit?.record(AuditEntry(
    action: AuditAction.closeCashSession, // Incorrect action type used
    entityType: 'drawer_settlement',
    amount: amount,
    ...
  ));
  ```
  It **never reduces `expectedCash`** on the active `CashSession` or writes a `cash_movements` record.
- **Financial Consequence:** If a cashier starts with 500 EGP float, collects 8,000 EGP in cash sales, and drops 5,000 EGP to the safe:
  - Theoretical cash remaining in drawer: `500 + 8000 - 5000 = 3,500 EGP`.
  - System expected cash: `500 + 8000 = 8,500 EGP`.
  - Cashier counts actual drawer: `3,500 EGP`.
  - System reports an erroneous **Shortage of -5,000 EGP (عجز)** on the Z-Report!

### 2.3 Blind Cash Count Enforcement (Finding FIN-002)
- **Implementation:** [`lib/src/features/accounting/z_report_screen.dart#L570-L620`](file:///home/ammar/PIE/lib/src/features/accounting/z_report_screen.dart#L570-L620).
- **PRD Requirement (CASH-002):** "The cashier must enter their physical cash count without seeing the calculated drawer total beforehand to prevent theft and forced reconciliation."
- **Defect:** While entering denominations (200, 100, 50, etc.), `_buildSummaryColumn` renders:
  ```dart
  Text('الرصيد المحسوب بالدفتر:'),
  PieNumeral.money(expectedCash),
  Text('الفارق (العجز / الزيادة):'),
  PieNumeral.money(variance),
  ```
- **Financial Consequence:** The cashier knows exactly how much cash the system expects. If a cashier has 300 EGP excess or shortage, they can manipulate the counts before submitting the close.

---

## 3. Delivery COD & Driver Custody Settlement

### 3.1 Flow & Ledger Verification
- **Implementation:** [`lib/src/features/delivery/custody_settlement_screen.dart`](file:///home/ammar/PIE/lib/src/features/delivery/custody_settlement_screen.dart) and [`lib/src/features/delivery/driver_custody_collection_dialog.dart`](file:///home/ammar/PIE/lib/src/features/delivery/driver_custody_collection_dialog.dart).
- **Custody Allocation:** When a delivery order is dispatched, cash collected from the customer remains in the courier's custody (`DriverCustody`). It does **not** enter the cashier's active cash drawer upon order creation.
- **Handover & Drawer Injection:** When the courier returns to the branch and hands over collected cash to the cashier:
  1. Cashier opens `DriverCustodyCollectionDialog`.
  2. Dialog confirms collected deliveries and records a `CollectionModel` entry.
  3. Collected amount is injected into the cashier drawer ledger, increasing `expectedCash`.
- **Audit Verdict:** **PASS.** COD custody separation is correctly maintained between couriers and cashiers.

---

## 4. Payment Splits, Voids, and Rounding

### 4.1 Split Payments
- **Implementation:** [`lib/src/features/pos/pos_checkout_dialog.dart`](file:///home/ammar/PIE/lib/src/features/pos/pos_checkout_dialog.dart).
- **Validation:** Split payment permits dividing an order between Cash, Card (Visa/Mastercard), and Instapay.
- **Sum Verification:** The checkout dialog enforces `(cashPaid + cardPaid + otherPaid) == orderTotal` with a tolerance of `0.01 EGP` to prevent floating-point mismatch.
- **Audit Verdict:** **PASS.**

### 4.2 Order Voids and Cancellations
- **Implementation:** [`lib/src/features/manager/approvals_screen.dart`](file:///home/ammar/PIE/lib/src/features/manager/approvals_screen.dart) & [`lib/src/data/repositories/local_order_repository.dart`](file:///home/ammar/PIE/lib/src/data/repositories/local_order_repository.dart).
- **Authorization:** Voids on finalized orders require manager approval and entry of the manager PIN.
- **Stock & Accounting Impact:** Voiding an order reverses associated revenue from the session totals. However, because inventory recipe depletion is disconnected (GAP-002), stock reversal does not occur.
- **Audit Verdict:** **PARTIAL.** Monetary voiding works, but inventory reconciliation is missing.

---

## 5. Duplicate Transaction & Idempotency Analysis

### 5.1 Outbox Idempotency Keys
- **Implementation:** [`lib/src/data/local/outbox/outbox_entry.dart`](file:///home/ammar/PIE/lib/src/data/local/outbox/outbox_entry.dart).
- **Guarantee:** Every financial transaction (Order creation, Payment, Collection) generates a deterministic UUID client mutation ID (`localId`).
- **Sync Transport:** When pushing to Firestore, writes use `collection.doc(localId).set(data, SetOptions(merge: true))`.
- **Result:** Network timeouts or client retries execute idempotent upserts. Duplicate submissions never create duplicate invoices or charges.
- **Audit Verdict:** **PASS.**

---

## 6. Financial Integrity Recommendations

1. **Fix Drawer Settlement Accounting (Immediate):**
   - In `CashSessionRepository`, add `Future<void> recordCashDrop(String sessionId, double amount, String reason)`.
   - Update `CashSession.toRecord()` and `fromRecord()` to track `totalDroppedCash`.
   - Update `expectedCash` formula: `openingFloat + totalCashSales + totalCollectedDriverCustody - totalDroppedCash`.
2. **Enforce True Blind Cash Count (Immediate):**
   - In `ZReportScreen`, hide `expectedCash` and `variance` until the user presses `تأكيد الجرد وتقفيل الوردية`.
   - Require manager PIN confirmation if the variance exceeds a configurable threshold (e.g., > 50 EGP).
