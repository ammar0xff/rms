# PRIORITIZED BUG AND GAP REGISTER

**System:** PIE Operations / Restaurant Management System (RMS)  
**Target Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1`  
**Audit Date:** 2026-10-26  
**Auditor:** Multi-Disciplinary Quality & Security Audit Team  

---

## Summary of Findings

| ID | Title | Category | Severity | Confidence | PRD Ref | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **SEC-001** | Open Firestore Write Permissions on Financial & Approval Collections | `SECURITY` | **CRITICAL** | `CONFIRMED` | `SEC-001`, `AUTH-004` | Open |
| **SEC-002** | Insecure Fallback Manager PIN (`1234`) & No Brute-Force Rate Limiting | `SECURITY` | **HIGH** | `CONFIRMED` | `SEC-002`, `MGR-002` | Open |
| **FIN-001** | Drawer Settlement Drops Bypass Accounting Ledger, Writing Only Local Audit Log | `FINANCIAL_INTEGRITY` | **HIGH** | `CONFIRMED` | `CASH-004`, `CASH-005` | Open |
| **FIN-002** | Violation of Blind Cash Count: Expected Cash & Variance Displayed During Count | `FINANCIAL_INTEGRITY` | **MEDIUM** | `CONFIRMED` | `CASH-002` | Open |
| **DATA-001** | Audit Log Entries Strictly Local to Device, Unsynchronized to Cloud Firestore | `DATA_INTEGRITY` | **HIGH** | `CONFIRMED` | `MGR-004`, `SYNC-002` | Open |
| **COMPAT-001** | ESC/POS Thermal Network Printer Sends Raw UTF-8 Without Arabic BiDi Shaping | `COMPATIBILITY` | **HIGH** | `CONFIRMED` | `PRN-001`, `PRN-002` | Open |
| **COMPAT-002** | Missing Android Background Location Tracking Service (Foreground Service) | `COMPATIBILITY` | **MEDIUM** | `CONFIRMED` | `DRV-001`, `DRV-002` | Open |
| **COMPAT-003** | Web/PWA Platform Incompatible with Raw ESC/POS TCP Socket Printing (Port 9100) | `COMPATIBILITY` | **MEDIUM** | `CONFIRMED` | `PRN-004`, `PLAT-003` | Open |
| **GAP-001** | Mock Supervisor Temporary Delegation Code (`DEL-7921`) Unbacked by Service | `GAP` | **HIGH** | `CONFIRMED` | `MGR-003` | Open |
| **GAP-002** | Order Checkout Does Not Trigger Recipe / BOM Inventory Depletion | `GAP` | **HIGH** | `CONFIRMED` | `INV-001`, `INV-002` | Open |
| **GAP-003** | Mock Cross-Branch Emergency Rerouting and Rebalancing Actions | `GAP` | **MEDIUM** | `CONFIRMED` | `MGR-005` | Open |
| **SYNC-001** | Inbound Remote Sync Lacks Timestamp / Vector Clock Ordering Protection | `DATA_INTEGRITY` | **MEDIUM** | `CONFIRMED` | `SYNC-003`, `SYNC-004` | Open |
| **PERF-001** | Update Artifact Verification Buffers Entire Multi-Megabyte APK in Memory | `PERFORMANCE` | **MEDIUM** | `CONFIRMED` | `OTA-003` | Open |
| **RELIAB-001** | Unauthenticated GitHub Release API Calls Vulnerable to IP Rate Limiting (HTTP 403) | `RELIABILITY` | **MEDIUM** | `CONFIRMED` | `OTA-001` | Open |
| **TEST-001** | Outdated Emoji and Icon Assertions in Driver Delivery Flow Tests | `TEST_GAP` | **LOW** | `CONFIRMED` | `TEST-001`, `DRV-005` | Open |

---

## Detailed Evidence-Based Finding Reports

### Finding SEC-001: Open Firestore Write Permissions on Financial & Approval Collections
- **Finding ID:** `SEC-001`
- **Title:** Unrestricted Firestore Write Access on Orders, Payments, Approvals, and Inventory
- **Category:** `SECURITY`
- **Severity:** `CRITICAL`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Any signed-in user—including drivers, temporary cashiers, or compromised client devices—can directly alter financial payments, mark orders as delivered/paid, self-approve discount/void requests, or adjust inventory balances by invoking the Firestore client SDK directly, bypassing all UI and application validation.
- **Affected File & Lines:** [`firestore.rules#L95-L148`](file:///home/ammar/PIE/firestore.rules#L95-L148)
- **Reproduction / Verification:**
  ```javascript
  // Any authenticated driver or cashier can run:
  db.collection("approvals").doc("appr_01").update({
    status: "approved",
    approvedBy: "compromised_client"
  });
  // Rule allows this because match /approvals/{id} has:
  allow read, write: if signedIn();
  ```
- **Expected Behavior (PRD SEC-001 / AUTH-004):** Only users with privileged roles (`manager`, `developer`) may approve requests, modify cash sessions, or adjust inventory. Only cashiers and managers may create orders/payments.
- **Actual Behavior:** `orders`, `payments`, `approvals`, `cashSessions`, `inventoryItems`, and `purchases` allow unrestricted `allow read, write: if signedIn();`.
- **Recommended Fix:** Implement granular Role-Based Access Control (RBAC) in `firestore.rules` using `isPrivileged()` and `myRole()`. Restrict writes to `approvals`, `cashSessions`, and `inventoryItems` to privileged users only. Restrict `payments` and `orders` updates so non-privileged users cannot manipulate settled amounts.
- **Regression Test:** Create Firestore Rules unit tests verifying that non-manager auth tokens receive `permission-denied` when updating `approvals/{id}` or `cashSessions/{id}`.

---

### Finding SEC-002: Insecure Fallback Manager PIN (`1234`) & No Brute-Force Rate Limiting
- **Finding ID:** `SEC-002`
- **Title:** Manager PIN Service Falls Back to Insecure Default `1234` on Cache Miss and Lacks Attempt Throttling
- **Category:** `SECURITY`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** When a terminal is offline or running in an unconfigured branch, entering `'1234'` authorizes manager overrides, including bill cancellations, drawer openings, and custom discounts. An unauthorized operator can disconnect the terminal from Wi-Fi to force a cache miss or brute-force the 4-digit PIN (10,000 combinations) in seconds without any rate limiting.
- **Affected File & Lines:** [`lib/src/data/services/pin_service.dart#L81-L84`](file:///home/ammar/PIE/lib/src/data/services/pin_service.dart#L81-L84)
- **Reproduction / Verification:**
  ```dart
  // In pin_service.dart:
  if (hash is! String || salt is! String) {
    // In demo mode or unconfigured environments, allow standard manager PIN '1234'
    return pin.trim() == '1234';
  }
  ```
- **Expected Behavior (PRD SEC-002 / MGR-002):** Unset or unreachable manager PIN must fail closed. The system must enforce brute-force rate-limiting (e.g. 5 failed attempts locks the gate for 5 minutes). PIN hashing should use a secure work factor.
- **Actual Behavior:** When `settings/managerPin` is not found or fails to load, `pin == '1234'` evaluates to `true`. No rate limiting or delay is enforced on wrong entries.
- **Recommended Fix:** Remove the `'1234'` fallback. Return `false` (fail closed) if the PIN hash is missing or unreadable. Introduce a progressive lockout timer (3 attempts = 30s lock, 5 attempts = 5m lock) stored in secure local state.
- **Regression Test:** Add unit test in `test/pin_service_test.dart` asserting that `verify('1234')` returns `false` when `settings/managerPin` document is null.

---

### Finding FIN-001: Drawer Settlement Drops Bypass Accounting Ledger
- **Finding ID:** `FIN-001`
- **Title:** Cashier Drawer Settlement Submissions Write Only Local Audit Log Without Updating Session Ledger
- **Category:** `FINANCIAL_INTEGRITY`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Cash drops to the main safe ("توريد للخزينة الرئيسية") do not reduce the expected cash in the active cash session (`CashSession.expectedCash`). At the end of the shift, the drawer will show a massive false shortage equal to the dropped amount, causing severe financial discrepancies and accounting confusion.
- **Affected File & Lines:** [`lib/src/features/accounting/drawer_settlement_dialog.dart#L108-L135`](file:///home/ammar/PIE/lib/src/features/accounting/drawer_settlement_dialog.dart#L108-L135)
- **Reproduction / Verification:**
  ```dart
  // In drawer_settlement_dialog.dart:
  // Only records an AuditEntry:
  services.audit?.record(
    AuditEntry(
      id: 'settlement_${DateTime.now().millisecondsSinceEpoch}',
      action: AuditAction.closeCashSession,
      entityType: 'drawer_settlement',
      ...
    ),
  );
  // No update to cashSession or cash_drops collection!
  ```
- **Expected Behavior (PRD CASH-004 / CASH-005):** A cash drop must record a formal `CashMovement` or `CashDrop` entry linked to the active `CashSession`, reducing `expectedCash` and printing a cash drop receipt.
- **Actual Behavior:** The dialog only writes a local Sembast `AuditEntry` and closes, leaving the active session's expected balance unchanged.
- **Recommended Fix:** Add a `recordCashDrop(double amount, String reason)` method to `CashSessionRepository` that persists a formal cash movement, updates the session's ledger, and triggers a receipt print.
- **Regression Test:** Add integration test in `test/cash_session_test.dart` verifying that after a cash drop of 1,000 EGP, `expectedCash` decreases by exactly 1,000 EGP.

---

### Finding FIN-002: Violation of Blind Cash Count in Z-Report Screen
- **Finding ID:** `FIN-002`
- **Title:** Calculated Drawer Expected Cash and Live Variance Rendered to Cashier During Shift Close
- **Category:** `FINANCIAL_INTEGRITY`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Cashiers can observe the calculated theoretical drawer cash in real time while incrementing banknote denominations. This enables dishonest cashiers to adjust physical counts to artificially match the system, concealing pocketed cash.
- **Affected File & Lines:** [`lib/src/features/accounting/z_report_screen.dart#L570-L620`](file:///home/ammar/PIE/lib/src/features/accounting/z_report_screen.dart#L570-L620), [`lib/src/features/shift/shift_screen.dart#L354`](file:///home/ammar/PIE/lib/src/features/shift/shift_screen.dart#L354)
- **Reproduction / Verification:**
  Inspect `_buildSummaryColumn` in `z_report_screen.dart`:
  ```dart
  Text('الرصيد المحسوب بالدفتر:'),
  PieNumeral.money(expectedCash),
  Text('الفارق (العجز / الزيادة):'),
  PieNumeral.money(variance),
  ```
  Both are rendered while the cashier is on the counting screen before submitting the Z-close.
- **Expected Behavior (PRD CASH-002):** The cash count must be strictly blind. Expected cash and variance must remain hidden until the physical count is committed and confirmed.
- **Actual Behavior:** Expected cash and variance update dynamically on screen with each banknote increment.
- **Recommended Fix:** Mask or hide `expectedCash` and `variance` on the active counting screen for standard cashier operators. Reveal the variance only after the count is locked and submitted.
- **Regression Test:** Widget test asserting that `find.text('الرصيد المحسوب بالدفتر:')` is not visible until the cash count submission button has been pressed.

---

### Finding DATA-001: Audit Log Entries Strictly Local to Device
- **Finding ID:** `DATA-001`
- **Title:** Audit Log (`audit_entries`) is Never Synchronized to Cloud Firestore
- **Category:** `DATA_INTEGRITY`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** If a local terminal crashes, is reinstalled, or has its browser/application cache cleared, the entire audit trail of voids, cash drops, discounts, and overrides is permanently lost. Remote managers cannot monitor operator actions across branches.
- **Affected File & Lines:** [`lib/src/data/sync/record_mirror.dart#L46-L64`](file:///home/ammar/PIE/lib/src/data/sync/record_mirror.dart#L46-L64), [`firestore.rules#L1-L189`](file:///home/ammar/PIE/firestore.rules#L1-L189)
- **Reproduction / Verification:**
  Check `mirrorCollectionFor` in `record_mirror.dart`:
  ```dart
  String? mirrorCollectionFor(String entityType) => switch (entityType) {
    'order' => 'orders',
    'payment' => 'payments',
    // ...
    // 'auditEntry' is completely omitted!
    _ => null,
  };
  ```
  `firestore.rules` also has no rule for `match /audit_entries/{id}`.
- **Expected Behavior (PRD MGR-004 / SYNC-002):** Audit log entries must be mirrored to a remote `audit_entries` collection with tamper-evident immutability (append-only, update/delete forbidden).
- **Actual Behavior:** Audit entries are stored exclusively in local Sembast `LocalStores.audit` and never leave the terminal.
- **Recommended Fix:** Add `'auditEntry' => 'audit_entries'` to `mirrorCollectionFor`, add immutable append-only rules for `audit_entries` in `firestore.rules`, and wire outbox sync for audit events.
- **Regression Test:** Unit test in `test/audit_log_test.dart` verifying that `record(...)` enqueues an outbox mirror operation for remote persistence.

---

### Finding COMPAT-001: ESC/POS Thermal Printer Lacks Arabic BiDi Shaping
- **Finding ID:** `COMPAT-001`
- **Title:** Raw UTF-8 Bytes Sent to ESC/POS Socket Without Arabic Glyphs Shaping or BiDi Reversal
- **Category:** `COMPATIBILITY`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Standard ESC/POS thermal receipt printers (Epson, Sunmi, Xprinter) do not decode raw multi-byte UTF-8 Arabic text. Receipts and kitchen tickets print out as illegible characters, disconnected glyphs, or question marks, rendering paper printing unusable in Egyptian restaurant operations.
- **Affected File & Lines:** [`lib/src/domain/services/network_esc_pos_adapter.dart#L78, L89, L116`](file:///home/ammar/PIE/lib/src/domain/services/network_esc_pos_adapter.dart#L78)
- **Reproduction / Verification:**
  ```dart
  // In network_esc_pos_adapter.dart:
  buffer.addAll(utf8.encode('*** بون مطبخ - ${ticket.station} ***\n'));
  ```
  Thermal ESC/POS printers require either:
  1. CP864 / CP1256 code page with shaped glyphs.
  2. Raster bitmap rendering (rendering Flutter widgets to monochrome PNG/bitmaps and printing via `GS v 0`).
- **Expected Behavior (PRD PRN-001 / PRN-002):** Thermal receipts must output connected, right-to-left Arabic text with correct ligature shaping.
- **Actual Behavior:** Raw UTF-8 bytes are streamed directly to port 9100.
- **Recommended Fix:** Implement raster bitmap printing or integrate an Arabic shaping and BiDi reordering library with CP864/CP1256 code page encoding.
- **Regression Test:** Add integration test with an ESC/POS byte decoder verifying Arabic ligature connectivity and code-page headers.

---

### Finding COMPAT-002: Missing Android Background Location Tracking Service
- **Finding ID:** `COMPAT-002`
- **Title:** Driver App Lacks Foreground Service Permission for Continuous Background GPS Tracking
- **Category:** `COMPATIBILITY`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** When a delivery courier locks their Android device, receives a phone call, or navigates using an external map app, Android suspends location updates. The cashier dashboard and manager fleet map lose real-time courier tracking.
- **Affected File & Lines:** [`android/app/src/main/AndroidManifest.xml#L11-L14`](file:///home/ammar/PIE/android/app/src/main/AndroidManifest.xml#L11-L14)
- **Reproduction / Verification:**
  `AndroidManifest.xml` contains:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  ```
  Missing permissions:
  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  ```
- **Expected Behavior (PRD DRV-001 / DRV-002):** Continuous background driver location streaming to fleet dispatch until trip completion.
- **Actual Behavior:** OS kills location stream as soon as app is backgrounded or screen turns off.
- **Recommended Fix:** Add foreground service permissions to `AndroidManifest.xml` and configure a persistent foreground notification with `flutter_background_service` or `geolocator_android`.
- **Regression Test:** Test manifest validation script verifying required foreground service permissions.

---

### Finding COMPAT-003: Web/PWA Cannot Connect to Raw ESC/POS Thermal Printers
- **Finding ID:** `COMPAT-003`
- **Title:** Web/PWA Platform Incompatible with Raw TCP Socket Printing on Port 9100
- **Category:** `COMPATIBILITY`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Cashiers using the Web/PWA version of PIE Operations cannot print to network receipt printers via TCP port 9100 without a local hardware print bridge or desktop agent.
- **Affected File & Lines:** [`lib/src/domain/services/socket_printer/socket_printer_transport_stub.dart#L1-L20`](file:///home/ammar/PIE/lib/src/domain/services/socket_printer/socket_printer_transport_stub.dart#L1-L20)
- **Reproduction / Verification:**
  Web browsers do not support raw TCP sockets. `createSocketPrinterTransport()` resolves to a stub on Web that throws or no-ops.
- **Expected Behavior (PRD PRN-004 / PLAT-003):** Web users must be explicitly informed to use the native Desktop/Android app or browser print dialog (`window.print()`).
- **Actual Behavior:** `ReceiptPrintService` gracefully falls back to browser HTML printing dialog, but network printer settings in UI indicate port 9100 without explaining the web limitation.
- **Recommended Fix:** Disable or clarify network socket printer configuration when running on Web (`kIsWeb`), directing users to the HTML print dialog.
- **Regression Test:** Unit test in `test/receipt_print_service_test.dart` verifying Web behavior when network printing is requested.

---

### Finding GAP-001: Mock Supervisor Temporary Delegation Code
- **Finding ID:** `GAP-001`
- **Title:** Static Mock Delegation Code `DEL-7921` Displayed Without Backend Generation or Expiry
- **Category:** `GAP`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** The supervisor delegation feature is non-functional. It displays a static string `DEL-7921` that is not cryptographically generated, does not expire, and cannot be used anywhere to authorize an operation.
- **Affected File & Lines:** [`lib/src/features/manager/pin_delegation_dialog.dart#L48, L139`](file:///home/ammar/PIE/lib/src/features/manager/pin_delegation_dialog.dart#L48)
- **Reproduction / Verification:**
  ```dart
  // In pin_delegation_dialog.dart:
  final String _generatedDelegationCode = 'DEL-7921';
  ```
- **Expected Behavior (PRD MGR-003):** Temporary delegation codes must be dynamically generated with a 60-minute TTL, stored in Firestore `delegation_codes`, and verified atomically upon redemption.
- **Actual Behavior:** Fixed static constant displayed in the dialog without any storage or verification backend.
- **Recommended Fix:** Implement `DelegationCodeService` to generate 6-character random alphanumeric tokens with Firestore backing and expiration timestamps.
- **Regression Test:** Test in `test/pin_delegation_test.dart` verifying random token generation and TTL expiry.

---

### Finding GAP-002: Order Checkout Does Not Trigger Inventory Recipe Depletion
- **Finding ID:** `GAP-002`
- **Title:** POS Order Completion Does Not Deduct Raw Material Ingredients from Inventory
- **Category:** `GAP`
- **Severity:** `HIGH`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Inventory stock levels on hand do not decrease when meals are prepared and sold. Restaurant food costing, waste tracking, and ingredient reorder thresholds remain inaccurate unless updated manually.
- **Affected File & Lines:** [`lib/src/features/pos/pos_checkout_dialog.dart`](file:///home/ammar/PIE/lib/src/features/pos/pos_checkout_dialog.dart), [`lib/src/domain/models/menu_item.dart#L65-L87`](file:///home/ammar/PIE/lib/src/domain/models/menu_item.dart#L65-L87)
- **Reproduction / Verification:**
  `MenuItemModel` has no recipe or ingredient linkage. `recordMovement` is never called on checkout completion.
- **Expected Behavior (PRD INV-001 / INV-002):** Selling a menu item must automatically deplete associated raw ingredients according to the defined Bill of Materials (BOM).
- **Actual Behavior:** Stock movements are only recorded during manual adjustments or branch transfers.
- **Recommended Fix:** Add `recipe` (list of `RecipeIngredient { itemId, quantity }`) to `MenuItemModel`. In `OrderRepository` or `LocalInventoryRepository`, deduct ingredients automatically upon order completion.
- **Regression Test:** Add test in `test/inventory_repository_test.dart` verifying that completing an order with 2 Pizzas deducts flour and cheese stock.

---

### Finding GAP-003: Mock Cross-Branch Emergency Rerouting and Triage Actions
- **Finding ID:** `GAP-003`
- **Title:** Cross-Branch Triage Rerouting Only Displays SnackBar Without Persisting Changes
- **Category:** `GAP`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** The manager's triage screen implies that emergency order rerouting to an adjacent branch is operational, but clicking the button merely displays a SnackBar notification and performs no database updates.
- **Affected File & Lines:** [`lib/src/features/manager/triage_screen.dart#L262-L270`](file:///home/ammar/PIE/lib/src/features/manager/triage_screen.dart#L262-L270)
- **Reproduction / Verification:**
  ```dart
  // In triage_screen.dart:
  onPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تفعيل التحويل التلقائي للأوردرات الزائدة لأقرب فرع')),
    );
  }
  ```
- **Expected Behavior (PRD MGR-005):** Emergency rebalance must prompt for destination branch, reassign pending orders, and notify target branch staff.
- **Actual Behavior:** Pure visual mock with static feedback.
- **Recommended Fix:** Wire `TriageService.rebalanceOrders(sourceBranch, targetBranch, orderIds)` to update branch IDs and notify both branches.
- **Regression Test:** Test in `test/triage_test.dart` asserting that rebalance modifies order `branchId` and triggers sync.

---

### Finding SYNC-001: Inbound Remote Sync Lacks Timestamp Ordering Protection
- **Finding ID:** `SYNC-001`
- **Title:** Delayed Inbound Firestore Snapshots Can Overwrite Newer Local Sembast State
- **Category:** `DATA_INTEGRITY`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** If a device receives a stale snapshot from Firestore that was delayed by network buffering, it will unconditionally overwrite local records if there is no pending local outbox mutation, causing state regression.
- **Affected File & Lines:** [`lib/src/data/sync/inbound_sync_service.dart#L127-L143`](file:///home/ammar/PIE/lib/src/data/sync/inbound_sync_service.dart#L127-L143)
- **Reproduction / Verification:**
  ```dart
  // In inbound_sync_service.dart:
  final hasLocalPending = await _outbox.hasOutstandingFor(...);
  if (hasLocalPending) continue;
  // Unconditionally overwrites:
  await store.record(entityId).put(_db.db, record);
  ```
- **Expected Behavior (PRD SYNC-003 / SYNC-004):** Inbound updates must check `updatedAt` / `version` against existing local records to enforce monotonic Last-Write-Wins (LWW).
- **Actual Behavior:** Inbound records overwrite existing local records regardless of relative timestamps.
- **Recommended Fix:** Compare `record['updatedAt']` with existing local record's `updatedAt`. Skip the put if the incoming timestamp is older.
- **Regression Test:** Add test in `test/inbound_sync_test.dart` asserting that an older snapshot cannot overwrite a newer local record.

---

### Finding PERF-001: Update Artifact Verification Buffers Entire APK in Memory
- **Finding ID:** `PERF-001`
- **Title:** `ArtifactVerifier` Reads Entire Downloaded Binary File into Memory to Compute SHA-256
- **Category:** `PERFORMANCE`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** On low-memory Android POS terminals (1GB-2GB RAM), loading a 60MB-100MB APK file entirely into a Dart byte array (`List<int>`) can trigger an Out-Of-Memory (OOM) crash right before installation.
- **Affected File & Lines:** [`lib/src/domain/update/artifact_verifier.dart#L90-L95`](file:///home/ammar/PIE/lib/src/domain/update/artifact_verifier.dart#L90-L95)
- **Reproduction / Verification:**
  ```dart
  // In artifact_verifier.dart:
  final data = await read(path);
  final digest = _sha256Hex(downloadedBytes);
  ```
- **Expected Behavior (PRD OTA-003):** Large binary artifacts must be hashed using streaming chunks (`File.openRead().transform(sha256)`).
- **Actual Behavior:** Full file is read into memory as a monolithic byte buffer.
- **Recommended Fix:** Refactor `ArtifactVerifier` to accept a `Stream<List<int>>` or use chunked streaming digest calculation.
- **Regression Test:** Add test verifying streaming checksum verification with simulated 100MB chunked stream.

---

### Finding RELIAB-001: Unauthenticated GitHub Release API Calls Vulnerable to IP Rate Limiting
- **Finding ID:** `RELIAB-001`
- **Title:** GitHub Release Notes and Manifest Checks Rely on Unauthenticated API Endpoint
- **Category:** `RELIABILITY`
- **Severity:** `MEDIUM`
- **Confidence:** `CONFIRMED`
- **Business Impact:** Multiple restaurant terminals behind a shared NAT IP checking for updates will exceed GitHub's unauthenticated limit of 60 requests/hour, resulting in HTTP 403 errors and update failures.
- **Affected File & Lines:** [`lib/src/data/updates/github_fetcher.dart#L15-L28`](file:///home/ammar/PIE/lib/src/data/updates/github_fetcher.dart#L15-L28)
- **Reproduction / Verification:**
  `http.get(url, headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'rms-updater'})`. No auth token or conditional ETag caching (`If-None-Match`).
- **Expected Behavior (PRD OTA-001):** Update checks must use HTTP caching (ETags) or route through a cached Firebase/Cloud proxy endpoint.
- **Actual Behavior:** Direct unauthenticated requests to `api.github.com` without caching headers.
- **Recommended Fix:** Implement `If-None-Match` caching with stored ETag to receive HTTP 304 Not Modified without burning rate limits.
- **Regression Test:** Test in `test/github_fetcher_test.dart` asserting that `If-None-Match` header is sent when cached ETag exists.

---

### Finding TEST-001: Outdated Emoji and Icon Assertions in Driver Delivery Flow Tests
- **Finding ID:** `TEST-001`
- **Title:** Two UI Test Failures in `driver_delivery_flow_test.dart` Due to Stale Assertions
- **Category:** `TEST_GAP`
- **Severity:** `LOW`
- **Confidence:** `CONFIRMED`
- **Business Impact:** False alarms in CI/CD pipeline blocking automated deployment.
- **Affected File & Lines:** [`test/ui/driver_delivery_flow_test.dart#L62, L341`](file:///home/ammar/PIE/test/ui/driver_delivery_flow_test.dart#L62)
- **Reproduction / Verification:**
  Run `flutter test test/ui/driver_delivery_flow_test.dart`:
  - Fails on `find.text('عرض البون')` (actual widget has emoji `'عرض البون 🧾'`).
  - Fails on `find.byIcon(Icons.play_arrow_rounded)` (fake journey simulation button was removed per user request).
- **Expected Behavior (PRD TEST-001 / DRV-005):** Test suite must accurately reflect current UI labels and real GPS controls.
- **Actual Behavior:** 2 out of 576 tests fail due to outdated assertions.
- **Recommended Fix:** Update test expectations to match current production widget tree.
- **Regression Test:** `flutter test test/ui/driver_delivery_flow_test.dart` passes cleanly (6/6 passing).
