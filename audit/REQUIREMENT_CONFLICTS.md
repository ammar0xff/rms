# REQUIREMENT CONFLICTS & ARCHITECTURAL FEASIBILITY REPORT

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1`  
**Audit Date:** 2026-10-26  
**Auditor:** Principal Enterprise Architect & Systems Analyst  

---

## 1. Executive Summary

During the audit of `PRD-RMS-2026-V1` against the actual implementation, four core requirement conflicts were identified where product specifications are mutually incompatible, impossible under standard hardware constraints, or contradict distributed systems principles.

---

## 2. Requirement Contradiction Register

### Conflict 1: Offline Finalization vs. Monotonic Centralized Invoice Numbering
- **PRD Statement A (POS-003, NFR-004):** Terminals must finalize orders and issue legally binding fiscal tax receipts completely offline during multi-day network partitions.
- **PRD Statement B (POS-005):** Invoices must be sequentially numbered without gaps or duplicates across all terminals in a branch.
- **The Impossibility:** According to distributed systems theory (CAP / FLP theorems), generating a gapless monotonic sequential sequence of integers across multiple distributed nodes without network consensus is impossible. If Terminal A and Terminal B are both offline and assign Invoice #1001, an unavoidable collision occurs upon reconnection.
- **Observed Repository Implementation:**
  - Employs a dual-identifier strategy:
    1. Offline: Generates a deterministic UUID (`localId`) and a provisional reference `PROV-{terminalId}-{seq}` printed on the initial receipt.
    2. Online: Transactionally increments a centralized Firestore counter (`counters/orderNumber`) and assigns `canonicalOrderNumber`.
- **Architectural Resolution:** Accept the dual-numbering approach formally in the PRD. The printed receipt displays the provisional number with a QR code referencing the immutable UUID. The tax authority verifies transactions by UUID rather than continuous integers.

---

### Conflict 2: Strict Blind Cash Count vs. Real-Time Cashier Shift Reconciliation
- **PRD Statement A (CASH-002):** "The cash count must be strictly blind. Cashiers must enter physical banknote counts without seeing the calculated drawer total to prevent theft and forced reconciliation."
- **PRD Statement B (CASH-003):** "The cashier must explain and rectify any drawer discrepancy before the shift can be closed."
- **The Conflict:** If the cashier is required to explain or rectify a discrepancy, they must know what the discrepancy is. But if the screen displays the discrepancy in real-time, the blind count is broken.
- **Current Defect:** The application currently renders `expectedCash` and `variance` side-by-side with the denomination steppers, allowing dishonest cashiers to adjust counts dynamically.
- **Architectural Resolution:** Implement a strict **Two-Phase Shift Close UX**:
  - **Phase 1 (Blind Input):** Denomination steppers only. Theoretical total and variance are completely hidden. The cashier presses "Lock & Submit Physical Count".
  - **Phase 2 (Reconciliation & Audit):** The count is permanently frozen. The system reveals the variance. If variance is zero, shift closes instantly. If variance > threshold, a mandatory reason field is displayed and manager PIN authorization is required.

---

### Conflict 3: Exactly-Once Hardware Printing Over Unidirectional TCP Sockets
- **PRD Statement (PRN-003):** "All orders and kitchen tickets must print exactly once. Duplicate prints and lost tickets are strictly prohibited."
- **The Hardware Reality:** Standard ESC/POS thermal printers connected via raw TCP port 9100 are **unidirectional data sinks**. The printer does not return application-level delivery acknowledgements over the socket. If the connection drops or the paper cutter jams:
  1. The socket may report success because bytes were written to the local OS network buffer.
  2. The printer may have lost power before burning the thermal paper.
  3. Resending unacknowledged bytes can print duplicate tickets in the kitchen.
- **Architectural Resolution:**
  - Acknowledge that raw TCP sockets cannot provide physical "exactly-once" delivery without bidirectional SNMP or specialized vendor SDKs (e.g. Epson ePOS SDK).
  - Implement an **at-least-once with idempotency** approach:
    - Every printed kitchen ticket prints a prominent order identifier.
    - If a network retry occurs, tickets print a `[REPRINT / بدل فاقد]` banner in bold text to prevent duplicate food preparation.
    - Provide an explicit "Reprint Ticket" button on POS order history.

---

### Conflict 4: Web/PWA Continuous Background Driver Tracking vs. Browser Lifecycle
- **PRD Statement (DRV-001, PLAT-003):** The Driver Application must run as a cross-platform Web/PWA application and stream continuous background GPS coordinates to dispatch during active trips.
- **The Browser Constraint:** Modern mobile browser engines (Chromium on Android, WebKit on iOS) aggressively throttle or terminate JavaScript execution and Geolocation APIs when a browser tab loses focus, the user switches apps, or the device screen turns off.
- **Field Impact:** A courier running the driver app in Chrome or Safari will stop transmitting GPS coordinates the moment they turn off the screen or switch to WhatsApp or phone calls.
- **Architectural Resolution:**
  - **Android Native APK is mandatory** for active couriers in the field, utilizing an Android Foreground Service with persistent status notification.
  - The Web/PWA driver portal must be designated for **in-store dispatch terminals, fleet monitoring tablets, or stationary review**, with clear UI warnings if launched on mobile browsers without background capability.
