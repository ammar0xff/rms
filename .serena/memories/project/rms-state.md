# RMS — Restaurant Management System (Flutter, offline-first)

## Repo / remote
- GitHub: https://github.com/ammar0xff/rms — PUBLIC, branch `main`.
- Design references used well: styles.refero.design (Refero Styles), uupm.cc (UI/UX Pro Max),
  21st.dev + framer.com via design-mcp. Rules documented in `docs/DESIGN.md` (each rule cites its source).
- Deploy gotcha: after deploy, GitHub Pages CDN may briefly serve the previous `main.dart.js`
  (no version query in flutter_bootstrap.js load). Verify with `curl` + grep for a new-only string;
  it self-heals within ~a minute.
- Local repo root: `/home/ammar/PIE` (folder name differs from repo name).
- Git identity is not global; commits use inline `-c user.name="ammar0xff" -c user.email="ammar0xff@users.noreply.github.com"`.
- `gh` at `/home/ammar/.local/bin/gh`, authenticated (scopes: gist, read:org, repo, workflow).

## Environment limits
- Flutter SDK is NOT installed locally (Garuda/Arch). No flutter pub get/analyze/test/run locally.
- All compilation/verification happens on GitHub Actions. Push, then check with `gh run watch <id>`.

## CI/CD (works)
- `.github/workflows/ci.yml`: Flutter stable, `flutter analyze --no-fatal-infos` (fails on errors/warnings) + `flutter test`.
- `.github/workflows/deploy-pages.yml`: generates web platform (`flutter create . --platforms web --project-name rms`),
  builds `flutter build web --release --base-href "/<repo name>/"`, deploys via actions/deploy-pages.
- Pages enabled (build_type=workflow). Live: https://ammar0xff.github.io/rms/ (HTTP 200 verified).

## App structure
- Entry: `lib/main.dart` -> `bootstrapApp()` -> `lib/src/app.dart` (`AppScope` + `AuthGate`) -> `AppShell`.
  Auth gate shows `SignInScreen` when signed out, else `AppShell`.
- Phase-0 DI/config: `lib/src/core/config/{firebase_config,app_version}.dart`, `lib/src/core/di/`
  (`AppServices` + `AppScope`), `lib/src/core/logging/app_logger.dart`,
  `lib/src/data/repositories/` (AuthRepository + Firebase/Demo impls), `lib/src/features/auth/`.
- Theme tokens: `lib/src/core/theme/{app_colors,app_spacing,app_text,app_theme}.dart`.
- Core widgets: `lib/src/core/widgets/` (app_shell, surface_card, status, buttons, rms_table, charts, stat_card, primitives, page, sync_chip).
- State: `lib/src/core/state/sync_monitor.dart` (singleton SyncMonitor.instance).
- Mock data: `lib/src/data/mock/mock_data.dart`.
- Screens (12): dashboard, pos, kitchen, delivery, accounting, menu, inventory, customers, reports, sync, conflicts, settings.
- Phase-0 domain scaffolding: `lib/src/data/local/outbox/`, `lib/src/data/sync/`, `lib/src/domain/`.
- Docs: `docs/` (PRD pdf/xmind/png, architecture.md, offline-capability-matrix.md).

## Design direction (locked)
Dense modern LIGHT dashboard, Arabic-only + RTL (locale `ar`, `String`s in Arabic). 3-tier elevation,
1px borders, NO glass/gradient/glow, tabular numerals, tiny type, dot statuses, brand amber #B45309.
Light tokens: base #F7F7F8, surface #FFF, fg #09090B, positive #059669, negative #DC2626,
warning #D97706, info #2563EB. `money()` suffix `ج.م`; chart ticks `10k/7.5k/5k/2.5k/0`; time `ص/م`.

## Gotchas learned
- GridRow (page.dart) wraps its Row in IntrinsicHeight; Row+CrossAxisAlignment.stretch inside a vertical
  SingleChildScrollView causes "BoxConstraints forces an infinite height".
- Dense table/row content uses Flexible + TextOverflow.ellipsis to avoid RenderFlex overflows.
- Widget test renders at desktop viewport (1600x1000); sidebar appears >= 900px width.
- Newer Flutter APIs used: Color.withValues(alpha:), WidgetStateProperty, MediaQuery.sizeOf.
- flutter analyze counts style infos as exit 1 -> CI uses --no-fatal-infos.

## Current state
Shipped: light + Arabic-only (RTL) across all 12 screens — `7371f44`; live verified.
Shipped: **Phase 0 foundation** — `df9e987` (on top of `8297dd6`, CI fix `df9e987`): build-time Firebase
config via `--dart-define` with demo-mode fallback, `AuthRepository` (Firebase + demo), `AuthGate` +
Arabic `SignInScreen`, `AppServices`/`AppScope` DI, `AppVersion`/`AppLogger` surfaced in Settings,
deploy injects `FIREBASE_*` secrets. CI + deploy green; live site shows sign-in → dashboard verified.
Gotchas: `FirebaseOptions.messagingSenderId` is non-nullable `String` (do not pass null);
`actions/upload-pages-artifact@v5` (NOT v7); checkout@v7 ok. Demo stream uses `Stream.multi` (broadcast
race). Version now `0.2.0+1`, sdk `>=3.6.0`.
Next: Firestore-backed `SyncTransport` + repositories, then wire the UI to `services.orders`.
Now shipped: Firestore transport + connectivity auto-drain + POS order submission (see below).

## Local persistence (SHIPPED) — CI + Deploy green, live re-verified (0 console errors)
- Store: **sembast** (schemaless doc store) chosen over PRD's SQLite/Drift to avoid `build_runner`
  codegen (cannot run without a local SDK); works on web via IndexedDB. Deps added: `sembast ^3.8.11`,
  `sembast_web ^2.4.6`, `path ^1.9.1`, `path_provider ^2.1.6`. Flutter stable here = 3.47.7 / Dart 3.13.5
  (satisfies deps' `^3.12.0`).
  - `lib/src/data/local/platform/db_factory{,_stub,_io,_web}.dart` — conditional import
    (`dart.library.io` / `dart.library.js_interop`) selects file vs IndexedDB; stub uses memory.
  - `lib/src/data/local/local_database.dart` — wraps sembast `Database`; `openPlatform()`, `memory()`,
    `fromDatabase()`, `transaction()`. `local_stores.dart` — `orders` + `outbox` stores.
  - `OutboxEntry.toRecord()/fromRecord()`, `OutboxStore` (append-in-txn, pending/all, markInProgress/
    markSynced/markRetryable). `OutboxEntry.copyWith(clearLastError:)`.
  - `lib/src/data/sync/`: `SyncTransport` iface + `SyncEngine.drain()` (markInProgress → push →
    markSynced + `onApplied` / catch → markRetryable), `InMemorySyncTransport` (dedupes on
    idempotencyKey), `SyncCoordinator` (re-entrancy guard).
  - `Order`/`OrderItem` gained `toRecord/fromRecord`; new `OrderDraft`, `OrderRepository` (iface),
    `LocalOrderRepository` (atomic order+outbox write; `applySynced`).
  - `AppServices` gained optional `database`/`orders` (+ `hasLocalStore`); `bootstrapApp()` opens the
    store independently of Firebase, degrading platform→memory→none.
  - `test/offline_sync_test.dart`: create offline → reopen file (restart) → reconnect → sync → replay
    dedupes; transient-failure retry; failed-transaction rollback.
  - GOTCHA (cost a CI round-trip): sembast's `StoreRef.find/record` and `RecordRef.get/put` are
    **extension methods** — a file calling them must `import 'package:sembast/sembast.dart';` directly
    (importing a file that imports sembast is NOT enough). Also: don't reference the cascade target
    variable inside a cascade initializer.
  - NOTE: sync is NOT auto-wired in the app yet (no real backend transport); screens still show mock
    data. Next: Firestore-backed transport + repositories, then wire UI to `services.orders`.


## Unit tests (Phase 0) — 46 pass, CI green
Files: `test/order_model_test.dart`, `outbox_test.dart`, `sync_test.dart`, `local_order_repository_test.dart`,
`local_database_test.dart`, `app_services_test.dart` (plus existing `auth_repository_test`, `firebase_config_test`,
`widget_test`, `offline_sync_test`).
- GOTCHA: `databaseFactoryMemory.openDatabase(path)` **caches the DB instance by path** (sembast
  `SembastDatabaseFactory._databases`), so reusing the same name across tests leaks state (records persist
  across open/close). Give each memory DB a unique name (tests use a per-file `_seq` counter → `LocalDatabase.memory('rms_x_${_seq++}')`).
- GOTCHA: `flutter analyze` fails on **unused private test helpers** (`unused_element` is a warning).

## Firebase (LIVE)
- Project **`teletunnal`** (pre-existing), web app config supplied by user.
- GitHub Secrets set for `ammar0xff/rms`: FIREBASE_API_KEY, FIREBASE_AUTH_DOMAIN
  (`teletunnal.firebaseapp.com`), FIREBASE_PROJECT_ID (`teletunnal`), FIREBASE_STORAGE_BUCKET
  (`teletunnal.firebasestorage.app`), FIREBASE_MESSAGING_SENDER_ID, FIREBASE_APP_ID. No `FIREBASE_MEASUREMENT_ID`.
- Console configured by user: Email/Password enabled, authorized domain `ammar0xff.github.io`, a user added.
- Live site now runs in REAL mode (no more demo line). Verified: valid apiKey, Auth enabled —
  dummy creds return the mapped "invalid credentials" message (no config errors). Real user login is
  user-driven (we have no stored creds).
- NOTE: the deploy build injects secrets only via `--dart-define`; `gh secret set` + workflow_dispatch
  redeploys. Config values are public web config (not sensitive), but kept in Secrets. Actions still
  gates deploy; the web key is only restricted by GCP API/referrer rules — add `ammar0xff.github.io`
  referrer restriction in GCP Credentials when hardening.

## Cloud sync — Firestore transport + connectivity auto-drain (SHIPPED)
- `lib/src/data/sync/firestore_sync_transport.dart` — `FirestoreSyncTransport implements SyncTransport`;
  writes each entry to `Firestore` collection `sync_operations` with **doc id = `idempotencyKey`** via
  `set(...)` so replays overwrite (server half of exactly-once). Fields: operationId/entityType/entityId/
  operationType/payload/schemaVersion/createdAt/`clientPushedAt`=FieldValue.serverTimestamp(). Ctor takes
  optional `FirebaseFirestore` (uses `.instance` when null) + `collection` name.
- `lib/src/data/sync/connectivity_monitor.dart` — wraps `connectivity_plus`; `onChanged`→`Stream<bool>`
  (`.map(hasConnection).distinct()`), `isOnline` via `checkConnectivity()`; `hasConnection(List<ConnectivityResult>)`
  = any != `none`. Plugin source lazily created; `changes`/`check` injectable for tests.
- `lib/src/data/sync/sync_service.dart` — `start()` reads `isOnline`, subscribes to `onChanged`, does a
  catch-up `requestSync()` when online; re-syncs on every reconnect; `isOnline` getter; `dispose()` cancels.
- Bootstrap: when `firebaseReady && database != null`, builds one `OutboxStore` shared by
  `LocalOrderRepository` + `SyncEngine(onApplied: orders.applySynced)`, wrapped in `SyncCoordinator` +
  `SyncService`; `unawaited(sync.start())`. `AppServices.sync` (nullable `SyncService`) added; null in
  demo mode / no store.
- POS wiring (`pos_screen.dart`): "إرسال للمطبخ" + "تحصيل" call `_submitOrder()` → `services.orders.createOrder`,
  clear cart, snackbar with `provisionalOrderNumber`, then `services.sync?.requestSync()`; disabled while
  submitting; falls back to an error snackbar when `orders==null`. `createdOffline = services.sync?.isOnline == false`.
  Product id = menu item name (menu has no ids).
- Tests: `test/connectivity_monitor_test.dart`, `test/sync_service_test.dart` (catch-up on start, offline→connect
  sync, dispose stops reacting). NOTE: future awaits in most tests must poll via `_until()` — the service uses
  `unawaited(requestSync())` so one `Duration.zero` yield is not enough.
- STILL OPEN: Firestore DB may not exist in project `teletunnal` → pushes fail → entries go `retryableFailure`
  (non-fatal). Server-assigned `canonicalOrderNumber`/`serverId` not yet produced (needs a Cloud Function);
  `applySynced` already reads them from `entry.payload` if present. `SyncMonitor`/sync chip still hardcoded.
