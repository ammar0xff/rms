import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/device_update_context.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/local/release_audit_log.dart';
import 'package:rms/src/data/local/update_acknowledgement_store.dart';
import 'package:rms/src/data/local/update_status_store.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/data/repositories/local_update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';

final _sha = 'a' * 64;
int _seq = 0;

UpdateManifest _manifest() => UpdateManifest(
  releaseId: 'rel-1',
  version: '1.1.0',
  buildNumber: 42,
  platform: currentUpdatePlatform(),
  channel: currentUpdateChannel(),
  status: ReleaseStatus.active,
  rolloutPercent: 100,
  severity: UpdateSeverity.mandatory,
  publishedAt: DateTime(2026, 10, 13),
  artifact: ReleaseArtifact(
    reference: 'releases/rms-1.1.0.pkg',
    sizeBytes: 1024,
    sha256: _sha,
  ),
);

OutboxEntry _stuckEntry(String id, OutboxStatus status) => OutboxEntry(
  operationId: 'op-$id',
  entityType: 'order',
  entityId: 'O-$id',
  operationType: 'upsert',
  payload: const {},
  schemaVersion: 1,
  idempotencyKey: 'idem-$id',
  createdAt: DateTime(2026, 10, 13),
  syncStatus: status,
);

AppServices _services(LocalDatabase db) => AppServices(
  config: const FirebaseConfig.empty(),
  auth: DemoAuthRepository(),
  firebaseReady: false,
  database: db,
  outbox: OutboxStore(db),
  updates: LocalUpdateRepository(db),
  updateAudit: ReleaseAuditLog(db),
  updateStatus: UpdateStatusStore(db),
  updateAcknowledgement: UpdateAcknowledgementStore(db),
);

Future<void> _seedStuck(LocalDatabase db, int stuck) async {
  final outbox = OutboxStore(db);
  await db.transaction((txn) async {
    for (var i = 0; i < stuck; i++) {
      await outbox.append(txn, _stuckEntry('$i', OutboxStatus.conflict));
    }
  });
}

Future<void> _openSettings(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RmsApp(services: services));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).at(0), 'ammar@rms.dev');
  await tester.enterText(find.byType(TextField).at(1), 'secret');
  await tester.tap(find.text('دخول'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('الإعدادات'));
  await tester.pumpAndSettle();
}

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await LocalDatabase.memory('rms_settings_${_seq++}');
    await LocalUpdateRepository(db).cache(_manifest());
  });

  tearDown(() async => db.close());

  testWidgets('an eligible update offers the install action', (tester) async {
    await _openSettings(tester, _services(db));

    expect(find.text('تحديث'), findsOneWidget);
    expect(find.textContaining('تحديث إلزامي'), findsOneWidget);
    expect(find.text('جاهز للتثبيت'), findsOneWidget);
  });

  testWidgets('stuck work withholds the install and offers acknowledgement', (
    tester,
  ) async {
    await _seedStuck(db, 2);
    await _openSettings(tester, _services(db));

    expect(find.text('أعمال محلية معلّقة'), findsOneWidget);
    expect(find.text('إقرار'), findsOneWidget);
    // The plain install action is not offered while work is stuck.
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('acknowledging stuck work unblocks the install', (tester) async {
    await _seedStuck(db, 2);
    await _openSettings(tester, _services(db));

    await tester.tap(find.text('إقرار'));
    await tester.pumpAndSettle();

    // The gate now reports ready and the install action is offered again.
    expect(find.text('جاهز للتثبيت'), findsOneWidget);
    expect(find.text('تحديث'), findsOneWidget);
  });

  testWidgets('the acknowledgement is persisted with the stuck count', (
    tester,
  ) async {
    await _seedStuck(db, 3);
    final store = UpdateAcknowledgementStore(db);
    expect(await store.load(), isNull);

    await _openSettings(tester, _services(db));
    await tester.tap(find.text('إقرار'));
    await tester.pumpAndSettle();

    final saved = await store.load();
    expect(saved, isNotNull);
    expect(saved!.stuckCount, 3);
  });

  testWidgets('a failed update attempt is surfaced after a reboot', (
    tester,
  ) async {
    await UpdateStatusStore(db).save(
      DeviceUpdateStatus(
        state: UpdateLifecycleState.failed,
        releaseId: 'rel-1',
        version: '1.1.0',
        buildNumber: 42,
        failureReason: UpdateFailureReason.healthCheckFailed,
        requiresRollback: true,
        rollbackTargetVersion: '1.0.0',
      ),
    );
    await ReleaseAuditLog(db).append(
      ReleaseAuditEvent(
        eventId: 'evt-1',
        releaseId: 'rel-1',
        occurredAt: DateTime(2026, 10, 13, 14),
        eventType: ReleaseAuditEventType.healthCheckFailed,
      ),
    );

    await _openSettings(tester, _services(db));

    expect(find.text('آخر محاولة تحديث'), findsOneWidget);
    expect(find.text('فشل التحديث'), findsOneWidget);
    expect(find.text('سبب الفشل'), findsOneWidget);
    expect(find.text('فشل فحص ما بعد التحديث'), findsOneWidget);
    expect(find.text('إجراء مطلوب'), findsOneWidget);
    expect(find.text('تراجع إلى 1.0.0'), findsOneWidget);
    expect(find.text('سجل التحديث'), findsWidgets);
  });

  testWidgets('a healthy completed update is surfaced without a failure row', (
    tester,
  ) async {
    await UpdateStatusStore(db).save(
      const DeviceUpdateStatus(
        state: UpdateLifecycleState.completed,
        releaseId: 'rel-1',
        version: '1.1.0',
      ),
    );

    await _openSettings(tester, _services(db));

    expect(find.text('آخر محاولة تحديث'), findsOneWidget);
    expect(find.text('اكتمل التحديث'), findsOneWidget);
    expect(find.text('سبب الفشل'), findsNothing);
    expect(find.text('إجراء مطلوب'), findsNothing);
  });
}
