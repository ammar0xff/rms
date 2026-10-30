# REPOSITORY AND ENVIRONMENT BASELINE

**System:** PIE Operations / Restaurant Management System (RMS)  
**Target Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1`  
**Audit Date:** 2026-10-26  
**Auditor:** Independent Multi-Disciplinary Engineering & Security Audit Team  
**Repository Path:** `/home/ammar/PIE`  

---

## 1. Environment & Tooling Specifications

| Tool / Environment Variable | Observed Value | Verification Command / Source |
| :--- | :--- | :--- |
| **Operating System** | Linux (Ubuntu / Debian x86_64, Kernel 6.8) | `uname -srm` |
| **Flutter SDK** | Flutter 3.47.7 (Channel stable, commit `a1cfec7`) | `flutter --version` |
| **Dart SDK** | Dart 3.13.5 (build 3.13.5) | `dart --version` |
| **Java / Android Toolchain** | OpenJDK 17.0.12 (Gradle 8.3 / AGP 8.2) | `android/build.gradle` & `gradlew` |
| **Git Working Tree State** | Clean (no uncommitted modifications) | `git status --porcelain` |
| **Current Git Branch** | `main` | `git rev-parse --abbrev-ref HEAD` |
| **Current Git Commit SHA** | `571e46c72ea8380e5e01b7a6fc7e0c451bb37e75` | `git rev-parse HEAD` |
| **Latest Commit Message** | `feat(driver): remove fake journey simulation, wire real GPS tracking, and remove google button` | `git log -1 --pretty=%B` |

---

## 2. Dependencies & Framework Topology

Extracted directly from `pubspec.yaml` and resolved in `pubspec.lock`:

### Core Runtime & Cross-Platform Libraries
- **Local Persistence:** `sembast: ^3.7.4+1` (IndexedDB fallback on Web, file-based Sembast IO on Native Desktop & Mobile).
- **Cloud Backend & Sync:** `cloud_firestore: ^6.10.0`, `firebase_auth: ^6.7.0`, `firebase_core: ^4.15.0`.
- **Hardware & Geolocation:** `geolocator: ^14.0.1`.
- **Networking & Transport:** `http: ^1.2.2`, raw `dart:io` sockets (`InternetAddress.anyIPv4`, port 9100).
- **Cryptography & Hashing:** `crypto: ^3.0.6` (SHA-256 for manager PIN, update artifact verification).
- **UI & Layout:** Flutter Material 3, Custom Design System (`PieColors`, `PieTypography`, `PieRadius`, `PieNumeral`).
- **Sound & Haptics:** Custom audio tone synthesizer (`pie_sound_service.dart`).

---

## 3. Baseline Verification Commands & Raw Output

### 3.1 Static Analysis (`flutter analyze`)
- **Execution Date:** 2026-10-26T01:00:15Z
- **Command:** `flutter analyze --no-pub`
- **Result:** **0 Errors, 0 Warnings, 241 Info diagnostics**.
- **Diagnostic Categories:**
  - `prefer_const_constructors`: 148 occurrences
  - `prefer_const_literals_to_create_immutables`: 52 occurrences
  - `avoid_print`: 12 occurrences
  - `unused_element`: 8 occurrences
  - `dangling_library_doc_comments`: 21 occurrences
- **Conclusion:** No blocking compilation or type errors detected.

### 3.2 Automated Test Suite (`flutter test`)
- **Execution Date:** 2026-10-26T01:02:10Z
- **Command:** `flutter test`
- **Total Test Cases Executed:** 576 tests across 82 test suites.
- **Outcome:** **574 PASSED, 2 FAILED (99.65% Pass Rate)**.

#### Failing Tests Detail:
1. **Suite:** `test/ui/driver_delivery_flow_test.dart`
   - **Test:** `Active Trip Flow: view stop details, nav sheet, receipt sheet, and deliver stop`
   - **Failure Point:** Line 62: `find.text('عرض البون')`
   - **Root Cause:** Label in `active_trip_screen.dart` was updated to `'عرض البون 🧾'`. The test was expecting the string without the emoji.
2. **Suite:** `test/ui/driver_delivery_flow_test.dart`
   - **Test:** `Fancy In-App Built-in Navigation Flow: opens cockpit HUD, tests 3D toggle and telemetry`
   - **Failure Point:** Line 341: `find.byIcon(Icons.play_arrow_rounded)`
   - **Root Cause:** The simulation play icon was intentionally removed when fake journey simulation was replaced with real hardware GPS streaming. The test was not updated to reflect this PRD-driven removal.

---

## 4. Directory & Module Structure

```text
/home/ammar/PIE
├── android/                  # Android native project, permissions, and FileProvider
├── assets/                   # Static audio, logos, and raster assets
├── docs/                     # Architecture, offline, and protocol documentation
├── firestore.rules           # Cloud Firestore security rules
├── lib/
│   ├── main.dart             # Cross-platform application entry point & root router
│   └── src/
│       ├── core/             # Logging, sound, state, theme, numerals, and widgets
│       ├── data/
│       │   ├── local/        # Sembast databases, stores, outbox, and audit logs
│       │   ├── repositories/ # Repositories bridging Sembast, Outbox, and Mirrors
│       │   ├── services/     # PIN service, print service, permission service
│       │   ├── sync/         # Outbox drain, retry policy, inbound sync, record mirror
│       │   └── updates/      # In-app updater, GitHub releases, APK installer
│       ├── domain/
│       │   ├── models/       # Immutable domain entities, DTOs, and value objects
│       │   ├── navigation/   # Geolocator platform transport, OSRM routing, geofence
│       │   ├── services/     # ESC/POS network adapter, receipt HTML generator
│       │   └── update/       # Update policies, artifact verification, health check
│       └── features/
│           ├── accounting/   # Z-report, drawer settlement, invoices
│           ├── auth/         # Sign-in, registration, operator role detection
│           ├── cashier/      # Customer directory, cashier personal settings
│           ├── delivery/     # Driver cockpit, real map tiles, custody, trip log
│           ├── manager/      # Approvals, branch triage, inventory, dashboard, PIN gate
│           ├── pos/          # POS touch grid, customization sheet, split checkout
│           ├── shift/        # Open shift, cash drawer gating, shift history
│           └── system/       # Diagnostics, settings, offline conflict monitor
└── test/                     # 82 unit, widget, and mock integration test suites
```
