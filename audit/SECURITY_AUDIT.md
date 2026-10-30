# SECURITY & ACCESS CONTROL AUDIT REPORT

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1` (Section 5, Section 15: Security & RBAC)  
**Audit Date:** 2026-10-26  
**Auditor:** Application Security & Firebase Security Engineer  

---

## 1. Executive Security Evaluation

PIE Operations implements strong client-side permission abstractions via `AppRole`, `AppUser`, and `PermissionService`. However, **the server-side security boundary (Cloud Firestore Security Rules) has major authorization vulnerabilities**. 

In an offline-first distributed system using direct client-to-cloud synchronization, **the local client environment cannot be trusted**. Any authenticated user possessing valid Firebase Auth credentials can execute arbitrary queries and mutations using the Firebase JavaScript or REST SDK.

---

## 2. Cloud Firestore Security Rules Analysis (`firestore.rules`)

### 2.1 Collection-by-Collection Security Matrix

| Firestore Path | Current Rule Definition | Security Analysis & Vulnerability Exposure | Risk Level |
| :--- | :--- | :--- | :--- |
| `match /users/{uid}` | Read: self or privileged; Write: self (no role change) or privileged. | **Well protected.** Self-privilege escalation is prevented by `!request.resource.data.keys().hasAny(['role'])`. | LOW |
| `match /settings/{id}` | `read, write: if signedIn() && isPrivileged();` | **Protected.** Manager PIN document is restricted to managers and developers. | LOW |
| `match /public_settings/{id}` | Read: `true`; Write: `isPrivileged()`. | **Safe.** Allows unauthenticated visitors to inspect public settings (such as signup toggle). | LOW |
| `match /sync_operations/{id}` | `read, write: if signedIn();` | **Operational.** Allows offline sync engine to write queue operations. | MEDIUM |
| `match /orders/{id}` | `read, write: if signedIn();` | **CRITICAL VULNERABILITY.** Any signed-in user can modify order totals, void orders without approval, or delete items. | **CRITICAL** |
| `match /payments/{id}` | `read, write: if signedIn();` | **CRITICAL VULNERABILITY.** Any courier or cashier can forge payments, alter payment amounts, or mark unpaid orders as paid. | **CRITICAL** |
| `match /collections/{id}` | `read, write: if signedIn();` | **CRITICAL VULNERABILITY.** Driver custody collections can be falsified or deleted by client calls. | **CRITICAL** |
| `match /approvals/{id}` | `read, write: if signedIn();` | **CRITICAL VULNERABILITY.** A cashier can self-approve discount or void requests directly via Firestore SDK. | **CRITICAL** |
| `match /cashSessions/{id}` | `read, write: if signedIn();` | **CRITICAL VULNERABILITY.** Shift opening floats, expected cash, and counted cash can be modified directly. | **CRITICAL** |
| `match /inventoryItems/{id}` | `read, write: if signedIn();` | **HIGH RISK.** Stock on hand and unit purchase costs can be overwritten without manager approval. | **HIGH** |
| `match /stockMovements/{id}` | `read, write: if signedIn();` | **HIGH RISK.** Fraudulent stock adjustments can be inserted into the ledger. | **HIGH** |
| `match /deliveries/{id}` | Write: cashier, privileged, or courier without modifying `amount`. | **Partially hardened.** Guards `amount` tampering for drivers, but lacks assignment validation. | MEDIUM |
| `match /drivers/{id}` | Read: signedIn; Write: privileged or self (`request.auth.uid == id`). | **Reasonable.** Couriers can update their vehicle/status, managers manage roster. | LOW |
| `match /counters/{id}` | `read, write: if signedIn();` | **Medium Risk.** Any authenticated client can burn order sequence numbers causing numbering gaps. | MEDIUM |
| `match /releases/{id}` | Read: signedIn; Write: `false`. | **Safe.** Immutable client view of releases. | LOW |
| `match /audit_entries/{id}` | *No rule defined (Default Deny).* | **DATA GAP.** Cloud audit log collection does not exist and cannot be written to. | **HIGH (DATA)** |

---

## 3. High-Risk Threat & Attack Scenarios

### Scenario A: Self-Approval of Discounts and Bill Voids (Privilege Bypass)
1. **Attacker:** Cashier with standard restricted privileges.
2. **Attack Vector:** Cashier creates an order and requests a 50% discount. The application UI prompts for manager PIN.
3. **Exploitation:** Cashier opens DevTools in the web browser (or runs a script using their Auth token) and issues:
   ```javascript
   firebase.firestore().collection('approvals').doc('req_9823').update({
     status: 'approved',
     resolvedAt: new Date().toISOString(),
     approvedBy: 'bypassed_manager'
   });
   ```
4. **Outcome:** Because `approvals/{id}` allows `write: if signedIn();`, the Firestore write succeeds immediately. The cashier's terminal receives the snapshot and applies the discount without a manager ever entering a PIN.

### Scenario B: Tampering with Cash Session Drawer Balance
1. **Attacker:** Cashier with a cash shortage of 2,000 EGP at the end of the shift.
2. **Attack Vector:** Direct mutation of `cashSessions` collection before performing Z-Close.
3. **Exploitation:**
   ```javascript
   firebase.firestore().collection('cashSessions').doc('session_cairo_12').update({
     expectedCash: 3000.0, // Reduced from 5000.0 to match counted cash
   });
   ```
4. **Outcome:** The cloud session record is updated. Inbound sync reflects the tampered `expectedCash` on manager screens, masking the cash theft.

---

## 4. Manager PIN Service Cryptographic & Security Evaluation

### 4.1 Fallback Default PIN Vulnerability
In [`lib/src/data/services/pin_service.dart#L81-L84`](file:///home/ammar/PIE/lib/src/data/services/pin_service.dart#L81-L84):
```dart
Future<bool> verify(String pin) async {
  final data = await _read();
  final hash = data?['hash'];
  final salt = data?['salt'];
  if (hash is! String || salt is! String) {
    // In demo mode or unconfigured environments, allow standard manager PIN '1234'
    return pin.trim() == '1234';
  }
  return _hash(pin.trim(), salt) == hash;
}
```
- **Finding:** If the device is offline and does not have `settings/managerPin` cached, or if a new branch has not yet initialized the manager PIN, `verify(pin)` returns `true` for `'1234'`.
- **Severity:** HIGH. Any operator who unplugs the Ethernet cable or turns off Wi-Fi can input `'1234'` to approve any gated operation.

### 4.2 Brute-Force Rate Limiting & Work Factor
- **PIN Complexity:** 4 to 8 digits (typically 4 digits = 10,000 possibilities).
- **Work Factor:** Single-iteration SHA-256 (`sha256.convert('rms-pin:$salt:$pin')`). SHA-256 is designed for fast hardware throughput, allowing millions of hashes per second.
- **Throttling:** There is **zero throttling, zero delay, and no lockout** after repeated incorrect PIN entries. An automated script or rogue client can brute-force all 10,000 combinations in milliseconds.

### 4.3 Mock Supervisor Delegation Code
In [`lib/src/features/manager/pin_delegation_dialog.dart#L48, L139`](file:///home/ammar/PIE/lib/src/features/manager/pin_delegation_dialog.dart#L48):
- Displays hardcoded static string `DEL-7921`.
- It does not generate unique OTP tokens, does not record delegation events in the audit log, and does not expire.

---

## 5. Secret Handling and API Credentials

1. **Firebase API Keys:** The `apiKey` in `firebase_options.dart` or `run_firebase.sh` is an identifier for Google Cloud API routing, which is standard for client-side Firebase apps. Security relies entirely on Firestore Security Rules and App Check.
2. **GitHub Updater:** Requests to `https://api.github.com/repos/...` do not include personal access tokens (PAT). This is safe from a credential leakage perspective, but subjects terminals to IP-based rate limiting (60 requests/hour).
3. **Hardcoded Secrets Check:** Static analysis confirmed no private RSA keys, service account JSON files, or administrative database credentials committed to the Git repository.

---

## 6. Security Remediation Action Plan

1. **Harden `firestore.rules` Immediately:**
   ```javascript
   match /approvals/{id} {
     allow read: if signedIn();
     allow create: if signedIn();
     allow update: if signedIn() && isPrivileged();
     allow delete: if signedIn() && isPrivileged();
   }
   match /cashSessions/{id} {
     allow read: if signedIn();
     allow create: if signedIn();
     allow update: if signedIn() && (isPrivileged() || myRole() == 'cashier');
     allow delete: if false;
   }
   match /inventoryItems/{id} {
     allow read: if signedIn();
     allow write: if signedIn() && isPrivileged();
   }
   ```
2. **Fail Closed on Manager PIN:** Remove `'1234'` fallback. Return `false` whenever the hash is unavailable.
3. **Implement Brute-Force Lockout:** Enforce a 30-second delay after 3 failed PIN attempts, and a 5-minute lockout after 5 failed attempts.
4. **Mirror `audit_entries` to Cloud:** Create an immutable, append-only `audit_entries` collection in Firestore with `allow create: if signedIn(); allow update, delete: if false;`.
