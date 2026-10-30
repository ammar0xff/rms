# THERMAL PRINTING, GPS NAVIGATION & FLEET AUDIT REPORT

**System:** PIE Operations / Restaurant Management System (RMS)  
**Evaluated Version:** `v0.39.0+40`  
**PRD Reference:** `PRD-RMS-2026-V1` (Section 7: Thermal Printing; Section 10: Driver GPS & Navigation)  
**Audit Date:** 2026-10-26  
**Auditor:** Hardware Integration, Thermal ESC/POS & GPS Telematics Engineer  

---

## 1. Executive Summary: Hardware & Telematics

The PIE Operations RMS bridges physical peripherals and hardware telematics across desktop POS terminals, mobile courier devices, and web browsers:
1. **Receipt & Kitchen Thermal Printing:** Supports dual-pipeline printing (HTML browser printing for Web, raw ESC/POS TCP sockets on port 9100 for Native Desktop/Mobile). The web HTML pipeline renders crisp, styled Arabic receipts. However, the native ESC/POS TCP pipeline sends raw UTF-8 bytes without Arabic BiDi shaping or code-page conversion, creating an immediate printing failure on standard physical thermal receipt printers.
2. **Driver GPS & Fleet Navigation:** Recently refactored to eliminate all fake journey simulations. The driver app utilizes live GPS streams via `package:geolocator`, calculates real turn-by-turn routes via OSRM, renders Slippy OSM raster tiles, and triggers geofence arrival detection within 45 meters of the destination. However, background location tracking on Android lacks foreground service configuration.

---

## 2. Thermal Printing Subsystem Audit

### 2.1 Printing Architecture & Dispatch Pipeline

```
                              ┌───────────────────────────────────┐
                              │     ReceiptPrintService.print     │
                              └───────────────────────────────────┘
                                                │
                       ┌────────────────────────┴────────────────────────┐
                       ▼                                                 ▼
             [Web Platform: kIsWeb]                         [Native Desktop / Android]
                       │                                                 │
          ┌─────────────────────────┐                       ┌─────────────────────────┐
          │ Build HTML Receipt DOM  │                       │ Build ESC/POS Command   │
          │ (Arabic CSS Typography) │                       │ (ESC @, Cut, Drawer)    │
          └─────────────────────────┘                       └─────────────────────────┘
                       │                                                 │
          ┌─────────────────────────┐                       ┌─────────────────────────┐
          │ iframe + window.print() │                       │ Raw TCP Socket (9100)   │
          │ Instant Browser Dialog  │                       │ (NetworkEscPosAdapter)  │
          └─────────────────────────┘                       └─────────────────────────┘
```

### 2.2 ESC/POS Command Sequences & Hardware Control
- **Implementation:** [`lib/src/domain/services/network_esc_pos_adapter.dart#L70-L140`](file:///home/ammar/PIE/lib/src/domain/services/network_esc_pos_adapter.dart#L70-L140).
- **Initialization:** `ESC @` (`0x1B, 0x40`) resets printer hardware state.
- **Paper Cut:** `GS V 66 0` (`0x1D, 0x56, 0x42, 0x00`) performs a clean partial paper cut.
- **Cash Drawer Kick:** `ESC p 0 25 250` sends a 50ms electric pulse to the RJ12 drawer kick solenoid.
- **Kitchen Ticket Splitting:** [`lib/src/domain/services/kitchen_ticket_factory.dart`](file:///home/ammar/PIE/lib/src/domain/services/kitchen_ticket_factory.dart) splits incoming orders by preparation station (`Kitchen`, `Bar`, `Grill`, `Oven`), routing items to their designated physical station printers.
- **Audit Verdict:** **PASS.** Hardware command sequences comply with ESC/POS standards.

### 2.3 The Arabic Glyph & BiDi Rendering Defect (Finding COMPAT-001)
- **Defect:** In `_buildKitchenTicketEscPos` and `_buildReceiptEscPos`:
  ```dart
  buffer.addAll(utf8.encode('*** بون مطبخ - ${ticket.station} ***\n'));
  buffer.addAll(utf8.encode('رقم الطلب: ${ticket.orderRef}\n'));
  ```
- **Technical Analysis:** Thermal receipt printers (Epson TM-T20, Rongta, Xprinter, Sunmi) do not natively process UTF-8 Arabic code points. When sent raw UTF-8:
  1. Multi-byte Arabic UTF-8 sequences are interpreted as random single-byte ANSI/ASCII glyphs (e.g. `Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨`).
  2. Characters are printed from left-to-right rather than right-to-left.
  3. Arabic letters are not joined in their cursive connected forms (isolated glyphs).
- **Remediation Options:**
  - **Option A (Raster Graphics Bitmap - Recommended):** Render the receipt widget or ticket off-screen using Flutter's `PictureRecorder` into a monochrome bitmap, then output using ESC/POS bitmap command `GS v 0`. This guarantees 100% font fidelity, logos, and QR codes across all printer brands.
  - **Option B (Code Page Conversion):** Shape Arabic text using `arabic_tools` or similar shaping algorithm, apply BiDi reversal, and encode into Code Page 864 or CP1256.

---

## 3. Driver GPS, Telematics & Cockpit Navigation Audit

### 3.1 Hardware GPS Acquisition
- **Implementation:** [`lib/src/domain/navigation/driver_location_service.dart`](file:///home/ammar/PIE/lib/src/domain/navigation/driver_location_service.dart) & [`geolocator_location_transport.dart`](file:///home/ammar/PIE/lib/src/domain/navigation/location/geolocator_location_transport.dart).
- **Verification:** The system utilizes `Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5))`.
- **Fallbacks:** If GPS permissions are denied or disabled, the UI surfaces clear diagnostic banners with one-tap buttons to `openAppSettings()` or `openLocationSettings()`.
- **Audit Verdict:** **PASS.** Real hardware GPS streams reliably in foreground.

### 3.2 Live Turn-by-Turn Routing & Tile Map Rendering
- **Implementation:** [`lib/src/features/delivery/driver_cockpit_nav_screen.dart`](file:///home/ammar/PIE/lib/src/features/delivery/driver_cockpit_nav_screen.dart), [`driver_nav_map_canvas.dart`](file:///home/ammar/PIE/lib/src/features/delivery/widgets/driver_nav_map_canvas.dart), and [`real_map_tile_widget.dart`](file:///home/ammar/PIE/lib/src/features/delivery/widgets/real_map_tile_widget.dart).
- **Routing Engine:** Queries OpenStreetMap / OSRM public API (`https://router.project-osrm.org/route/v1/driving/...`).
- **Telemetry HUD:** Displays live vehicle velocity (km/h), remaining trip distance (km/m), and dynamic estimated time of arrival (ETA).
- **3D Cockpit Mode:** Supports toggling between 2D Top-Down North-Up view and 3D Perspective Course-Up view with dynamic canvas transformation.
- **Audit Verdict:** **PASS.**

### 3.3 Geofence Arrival Detection (45-Meter Threshold)
- **Implementation:** [`driver_cockpit_nav_screen.dart#L280-L310`](file:///home/ammar/PIE/lib/src/features/delivery/driver_cockpit_nav_screen.dart#L280-L310).
- **Logic:**
  ```dart
  final distanceMeters = Geolocator.distanceBetween(
    driverCoord.latitude, driverCoord.longitude,
    destCoord.latitude, destCoord.longitude,
  );
  if (distanceMeters <= 45.0 && !_hasTriggeredArrival) {
    _triggerArrivalPrompt();
  }
  ```
- **Behavior:** When the courier enters within 45 meters of the delivery destination, the cockpit automatically plays an arrival chime, expands the bottom sheet, and presents the customer phone and delivery completion button.
- **Audit Verdict:** **PASS.**

### 3.4 Background Location Tracking Limitation (Finding COMPAT-002)
- **Defect:** `AndroidManifest.xml` lacks `android.permission.FOREGROUND_SERVICE_LOCATION`.
- **Field Impact:** When the driver locks the screen or switches to a WhatsApp messaging app to contact the customer, Android throttles or suspends background GPS coordinates, causing the manager's dispatch fleet map to show a stationary courier.
- **Remediation:** Configure Android Foreground Service with persistent notification channel in `AndroidManifest.xml`.
