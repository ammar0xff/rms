# PRD TRACEABILITY & VERIFICATION MATRIX

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Specification:** `PRD-RMS-2026-V1`  
**Audit Date:** 2026-10-26  

---

## 1. Authentication & Role-Based Access Control (AUTH)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AUTH-001** | Operator email/password sign-in | `IMPLEMENTED` | `sign_in_screen.dart:40-120` | `auth_repository_test.dart` | — |
| **AUTH-002** | Operator self-registration toggle | `IMPLEMENTED` | `sign_in_screen.dart`, `firestore.rules:79` | `signup_toggle_flow_test.dart` | — |
| **AUTH-003** | Role resolution (`cashier`, `driver`, `manager`, `developer`) | `IMPLEMENTED` | `app_user.dart:20-60`, `firestore.rules:28-38` | `auth_repository_test.dart` | — |
| **AUTH-004** | Role-based Firestore write restrictions | `DEFECT` | `firestore.rules:95-148` (Open Writes) | *Untested against rules* | **SEC-001** |
| **AUTH-005** | Self-privilege escalation prevention | `IMPLEMENTED` | `firestore.rules:57-65` (Role mutation blocked) | `team_permissions_flow_test.dart`| — |
| **AUTH-006** | Manager PIN verification gate | `DEFECT` | `pin_service.dart:81-84` (Fallback `'1234'`) | `app_services_test.dart` | **SEC-002** |
| **AUTH-007** | Manager PIN brute-force lockout | `NOT_IMPLEMENTED` | `pin_service.dart` (Zero rate limiting) | *Untested* | **SEC-002** |
| **AUTH-008** | Supervisor delegation code generation | `NOT_IMPLEMENTED` | `pin_delegation_dialog.dart:48` (Mock `DEL-7921`)| *Untested* | **GAP-001** |
| **AUTH-009** | Branch operator assignment | `IMPLEMENTED` | `team_screen.dart`, `app_user.dart` | `team_permissions_flow_test.dart`| — |
| **AUTH-010** | Session lock & idle security timeout | `IMPLEMENTED` | `session_lock_and_guard_test.dart` | `session_lock_and_guard_test.dart`| — |

---

## 2. Point of Sale & Order Engine (POS)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **POS-001** | Fast-touch menu grid & category filter | `IMPLEMENTED` | `pos_screen.dart:180-260` | `pos_user_flows_test.dart` | — |
| **POS-002** | Modifier groups (required single, optional multi) | `IMPLEMENTED` | `pos_customise_sheet.dart:50-130` | `menu_repository_test.dart` | — |
| **POS-003** | Offline order finalization & persistence | `IMPLEMENTED` | `local_order_repository.dart:80-140` | `local_order_repository_test.dart`| — |
| **POS-004** | Shift gating (order blocked if shift closed) | `IMPLEMENTED` | `pos_screen.dart:320-350` | `pos_shift_gating_test.dart` | — |
| **POS-005** | Canonical sequential order numbering | `IMPLEMENTED` | `local_order_repository.dart:150-190` | `order_model_test.dart` | — |
| **POS-006** | Provisional offline order numbering | `IMPLEMENTED` | `order.dart:45-60` (`PROV-{id}-{seq}`) | `order_model_test.dart` | — |
| **POS-007** | Split payment execution (Cash + Card + Other) | `IMPLEMENTED` | `pos_checkout_dialog.dart:180-250` | `payment_repository_test.dart` | — |
| **POS-008** | Order channel routing (Takeaway, Delivery) | `IMPLEMENTED` | `order_type.dart`, `pos_screen.dart` | `order_model_test.dart` | — |
| **POS-009** | Customer phone lookup & linkage | `IMPLEMENTED` | `cashier_customers_screen.dart` | `customer_repository_test.dart` | — |
| **POS-010** | Order voiding with manager PIN approval | `IMPLEMENTED` | `approvals_screen.dart`, `pin_service.dart` | `approval_repository_test.dart` | — |
| **POS-011** | Automatic recipe inventory deduction | `NOT_IMPLEMENTED` | `pos_checkout_dialog.dart` (No inventory call) | *Missing test* | **GAP-002** |
| **POS-012** | Egyptian tax & service fee calculation | `IMPLEMENTED` | `order.dart:100-140` (14% VAT, configurable)| `order_model_test.dart` | — |

---

## 3. Thermal Printing Subsystem (PRN)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PRN-001** | Thermal receipt printing (80mm standard roll) | `IMPLEMENTED` | `receipt_print_service.dart:70-98` | `receipt_print_service_test.dart`| — |
| **PRN-002** | ESC/POS network socket printing (Port 9100) | `DEFECT` | `network_esc_pos_adapter.dart:78` (Raw UTF-8) | `print_adapter_test.dart` | **COMPAT-001** |
| **PRN-003** | Kitchen ticket station splitting | `IMPLEMENTED` | `kitchen_ticket_factory.dart:30-80` | `kitchen_ticket_factory_test.dart`| — |
| **PRN-004** | Web browser HTML receipt printing | `IMPLEMENTED` | `receipt_print_service.dart:73-84` | `receipt_print_service_test.dart`| — |
| **PRN-005** | RJ12 cash drawer electric pulse kick | `IMPLEMENTED` | `network_esc_pos_adapter.dart:125` (`ESC p 0`) | `print_adapter_test.dart` | — |
| **PRN-006** | Automatic partial paper cutting | `IMPLEMENTED` | `network_esc_pos_adapter.dart:95` (`GS V 66 0`)| `print_adapter_test.dart` | — |
| **PRN-007** | Z-Report shift closing receipt printing | `IMPLEMENTED` | `receipt_print_service.dart:450-520` | `settings_printing_flow_test.dart`| — |

---

## 4. Cash Sessions, Shifts & Financial Accounting (CASH)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CASH-001** | Opening float entry upon shift start | `IMPLEMENTED` | `open_shift_dialog.dart:60-120` | `shift_session_flow_test.dart` | — |
| **CASH-002** | Strictly blind physical cash count | `DEFECT` | `z_report_screen.dart:575-620` (Expected shown) | `shift_session_flow_test.dart` | **FIN-002** |
| **CASH-003** | Egyptian banknote denomination steppers | `IMPLEMENTED` | `z_report_screen.dart:35-50` (200, 100, 50, etc.)| `shift_session_flow_test.dart` | — |
| **CASH-004** | Mid-shift drawer drops to main safe | `DEFECT` | `drawer_settlement_dialog.dart` (Bypasses ledger)| *Untested on ledger* | **FIN-001** |
| **CASH-005** | Variance calculation (Surplus / Deficit) | `IMPLEMENTED` | `cash_session.dart:53-58` (`counted - expected`) | `cash_session_test.dart` | — |
| **CASH-006** | Historical Z-Report shift log | `IMPLEMENTED` | `shift_screen.dart:420-460` | `shift_and_invoices_edge_cases_test.dart`| — |

---

## 5. Delivery Dispatch & Driver Custody (DSP)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DSP-001** | Delivery order dispatch & courier assignment | `IMPLEMENTED` | `delivery_assignment.dart:30-90` | `delivery_assignment_test.dart` | — |
| **DSP-002** | Delivery zone fee configuration | `IMPLEMENTED` | `delivery_zone.dart`, `firestore.rules:158` | `delivery_repository_test.dart` | — |
| **DSP-003** | COD courier cash custody tracking | `IMPLEMENTED` | `delivery.dart:45-80`, `collection.dart` | `delivery_settlement_sync_test.dart`| — |
| **DSP-004** | Courier handover to cashier drawer | `IMPLEMENTED` | `driver_custody_collection_dialog.dart` | `delivery_settlement_sync_test.dart`| — |
| **DSP-005** | Delivery failure handling (No answer, etc.) | `IMPLEMENTED` | `driver_fail_dialog.dart:30-80` | `ui/driver_delivery_flow_test.dart` | — |
| **DSP-006** | Central fleet dispatch map overview | `IMPLEMENTED` | `fleet_screen.dart:50-140` | `fleet_driver_permissions_test.dart`| — |

---

## 6. Driver GPS, Telematics & Cockpit Navigation (DRV)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DRV-001** | Real hardware GPS acquisition (Geolocator) | `IMPLEMENTED` | `driver_location_service.dart:55-95` | `navigation_test.dart` | — |
| **DRV-002** | Android background location tracking | `DEFECT` | `AndroidManifest.xml` (No FG Service) | *Missing test* | **COMPAT-002** |
| **DRV-003** | Real turn-by-turn routing via OSRM | `IMPLEMENTED` | `driver_cockpit_nav_screen.dart:180-240` | `navigation_test.dart` | — |
| **DRV-004** | Raster tile rendering (Slippy Map OSM) | `IMPLEMENTED` | `real_map_tile_widget.dart:30-110` | `navigation_test.dart` | — |
| **DRV-005** | Geofence arrival detection within 45m | `IMPLEMENTED` | `driver_cockpit_nav_screen.dart:285` | `ui/driver_delivery_flow_test.dart` | **TEST-001** |
| **DRV-006** | 3D perspective cockpit HUD mode | `IMPLEMENTED` | `driver_nav_map_canvas.dart:80-140` | `ui/driver_delivery_flow_test.dart` | **TEST-001** |
| **DRV-007** | Elimination of fake journey simulation | `IMPLEMENTED` | Commit `571e46c` (Fake code purged) | `ui/driver_delivery_flow_test.dart` | **TEST-001** |

---

## 7. Inventory, Recipes & Stock Ledger (INV)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **INV-001** | Ingredient stock tracking & units | `IMPLEMENTED` | `inventory_item.dart`, `local_inventory_repo.dart`| `inventory_repository_test.dart`| — |
| **INV-002** | Recipe (BOM) linkage on menu items | `NOT_IMPLEMENTED` | `menu_item.dart` (No recipe data structure) | *Missing test* | **GAP-002** |
| **INV-003** | Purchase orders & supplier invoices | `IMPLEMENTED` | `purchase_order.dart`, `supplier.dart` | `purchasing_repository_test.dart`| — |
| **INV-004** | Moving average unit cost calculation | `IMPLEMENTED` | `local_purchase_repository.dart:90-130` | `purchase_payable_sync_test.dart`| — |
| **INV-005** | Inter-branch stock transfers | `IMPLEMENTED` | `stock_transfer.dart`, `local_transfer_repo.dart` | `transfer_repository_test.dart` | — |
| **INV-006** | Stock movement ledger (Append-only) | `IMPLEMENTED` | `stock_movement.dart:20-60` | `inventory_repository_test.dart`| — |

---

## 8. Manager Approvals, CRM & OTA Updates (MGR, CRM, OTA)

| Req ID | Requirement Summary | Status | Implementation Evidence | Test Suite | Finding ID |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **MGR-001** | Discount and void approval requests | `IMPLEMENTED` | `approvals_screen.dart:80-160` | `approval_repository_test.dart` | — |
| **MGR-002** | Cross-branch operational triage | `PARTIAL` | `triage_screen.dart` (Rebalance is mock SnackBar)| *Untested* | **GAP-003** |
| **MGR-003** | Central audit trail synchronization | `DEFECT` | `record_mirror.dart` (Audit log not mirrored) | `audit_log_test.dart` | **DATA-001** |
| **CRM-001** | Customer delivery address book | `IMPLEMENTED` | `customer.dart`, `cashier_customers_screen.dart` | `customer_repository_test.dart` | — |
| **CRM-002** | Customer loyalty points & credit ledger | `NOT_IMPLEMENTED` | `customer.dart` (No loyalty ledger) | *Missing test* | — |
| **OTA-001** | GitHub release tracking & semantic versions | `IMPLEMENTED` | `github_release_source.dart:30-80` | `github_release_source_test.dart`| **RELIAB-001** |
| **OTA-002** | Android in-app APK installer (FileProvider) | `IMPLEMENTED` | `android_update_installer.dart:40-90` | `in_app_update_dialog_test.dart`| — |
| **OTA-003** | Cryptographic SHA-256 artifact verification | `IMPLEMENTED` | `artifact_verifier.dart:30-75` | `artifact_verifier_test.dart` | **PERF-001** |
