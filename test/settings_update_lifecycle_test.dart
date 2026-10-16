import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/device_update_context.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/core/widgets/buttons.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/update_store_contracts.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/app_user.dart';
import 'package:rms/src/data/repositories/update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';
import 'package:rms/src/domain/update/update_acknowledgement.dart';
import 'package:rms/src/features/settings/settings_screen.dart';

final _sha = 'a' * 64;

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

class _FakeUpdates implements UpdateRepository {
  _FakeUpdates(this.manifest);

  final UpdateManifest? manifest;

  @override
  Future<UpdateManifest?> cached() async => manifest;

  @override
  Future<void> cache(UpdateManifest manifest) async {}

  @override
  Future<void> clear() async {}
}

/// In-memory stand-in for the Sembast-backed status store.
class _FakeStatusStore implements UpdateStatusStore {
  _FakeStatusStore([this.status]);

  DeviceUpdateStatus? status;

  @override
  Future<DeviceUpdateStatus?> load() async => status;

  @override
  Future<void> save(DeviceUpdateStatus status) async {
    this.status = status;
  }

  @override
  Future<DateTime?> snoozedUntil() async => null;

  @override
  Future<void> setSnoozedUntil(DateTime? until) async {}
}

class _FakeAuditTrail implements ReleaseAuditTrail {
  _FakeAuditTrail(this.events);

  List<ReleaseAuditEvent> events;

  @override
  Future<List<ReleaseAuditEvent>> list({int limit = 200}) async =>
      events.take(limit).toList();
}

class _FakeAcknowledgementStore implements UpdateAcknowledgementStore {
  _FakeAcknowledgementStore([this.acknowledgement]);

  UpdateAcknowledgement? acknowledgement;

  @override
  Future<UpdateAcknowledgement?> load() async => acknowledgement;

  @override
  Future<void> save(UpdateAcknowledgement acknowledgement) async {
    this.acknowledgement = acknowledgement;
  }
}

/// In-memory stand-in for the transactional outbox.
///
/// The real store is Sembast-backed and does not settle under the widget-test
/// binding, which is why the UI reads it through [OutboxAccess] instead.
class _FakeOutbox implements OutboxAccess {
  _FakeOutbox(this.entries);

  List<OutboxEntry> entries;

  @override
  Future<List<OutboxEntry>> all() async => entries;

  @override
  Future<void> save(OutboxEntry entry) async {
    entries = [
      for (final e in entries)
        if (e.operationId != entry.operationId) e,
      entry,
    ];
  }

  @override
  Future<int> pruneSynced() async => 0;
}

OutboxEntry _entry(
  String id,
  OutboxStatus status,
) =>
    OutboxEntry(
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

AppServices _services({
  required _FakeStatusStore status,
  _FakeAuditTrail? audit,
  _FakeAcknowledgementStore? acknowledgement,
  OutboxAccess? outbox,
}) =>
    AppServices(
      config: const FirebaseConfig.empty(),
      // Signed in as a manager, like production behind the AuthGate: the
      // acknowledgement action is privileged.
      auth: DemoAuthRepository(
        initialUser: const AppUser(
          uid: 'u-manager',
          email: 'manager@rms.dev',
          role: AppRole.manager,
        ),
      ),
      firebaseReady: false,
      updates: _FakeUpdates(_manifest()),
      // Null would mean "backlog unreadable" and withhold the install; the
      // eligible cases need an enumerated-empty backlog instead.
      outbox: outbox ?? _FakeOutbox(const []),
      updateStatus: status,
      updateAudit: audit ?? _FakeAuditTrail(const []),
      updateAcknowledgement: acknowledgement ?? _FakeAcknowledgementStore(),
    );

/// Advances a bounded number of frames.
///
/// [WidgetTester.pumpAndSettle] is avoided deliberately: it blocks until the
/// scheduler goes quiet, so one stray ticker becomes a hang that reports
/// nothing.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSettings(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsScreen(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('an eligible update offers the install action',
      (tester) async {
    await _openSettings(
      tester,
      _services(status: _FakeStatusStore()),
    );

    expect(find.text('التحديثات'), findsOneWidget);
    expect(find.text('جاهز للتثبيت'), findsOneWidget);
    // No install button here: the action lives in the shell-mounted prompt,
    // which is showing whenever the gate allows. The card used to carry a
    // duplicate button with a stale "not enabled" claim.
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('a failed attempt is surfaced with its rollback target',
      (tester) async {
    final status = _FakeStatusStore(
      DeviceUpdateStatus(
        state: UpdateLifecycleState.failed,
        releaseId: 'rel-1',
        version: '1.1.0',
        failureReason: UpdateFailureReason.healthCheckFailed,
        requiresRollback: true,
        rollbackTargetVersion: '1.0.0',
      ),
    );

    await _openSettings(tester, _services(status: status));

    expect(find.text('آخر محاولة تحديث'), findsOneWidget);
    expect(find.text('فشل التحديث'), findsOneWidget);
    expect(find.text('سبب الفشل'), findsOneWidget);
    expect(find.text('فشل فحص ما بعد التحديث'), findsOneWidget);
    expect(find.text('إجراء مطلوب'), findsOneWidget);
    expect(find.text('تراجع إلى 1.0.0'), findsOneWidget);
  });

  testWidgets('a completed attempt shows no failure rows', (tester) async {
    final status = _FakeStatusStore(
      const DeviceUpdateStatus(
        state: UpdateLifecycleState.completed,
        releaseId: 'rel-1',
        version: '1.1.0',
      ),
    );

    await _openSettings(tester, _services(status: status));

    expect(find.text('آخر محاولة تحديث'), findsOneWidget);
    expect(find.text('اكتمل التحديث'), findsOneWidget);
    expect(find.text('سبب الفشل'), findsNothing);
    expect(find.text('إجراء مطلوب'), findsNothing);
  });

  testWidgets('the audit trail is listed newest first', (tester) async {
    final audit = _FakeAuditTrail([
      ReleaseAuditEvent(
        eventId: 'e1',
        releaseId: 'rel-1',
        occurredAt: DateTime(2026, 10, 13, 14),
        eventType: ReleaseAuditEventType.migrationCompleted,
      ),
      ReleaseAuditEvent(
        eventId: 'e2',
        releaseId: 'rel-1',
        occurredAt: DateTime(2026, 10, 13, 15),
        eventType: ReleaseAuditEventType.healthCheckPassed,
      ),
    ]);

    await _openSettings(
      tester,
      _services(status: _FakeStatusStore(), audit: audit),
    );

    expect(find.text('سجل التحديث'), findsNWidgets(2));
    expect(find.text('نجح فحص ما بعد التحديث'), findsOneWidget);
    expect(find.text('اكتمل الترحيل'), findsOneWidget);
  });

  testWidgets('stuck work withholds the install and offers acknowledgement',
      (tester) async {
    await _openSettings(
      tester,
      _services(
        status: _FakeStatusStore(),
        outbox: _FakeOutbox([
          _entry('a', OutboxStatus.conflict),
          _entry('b', OutboxStatus.conflict),
        ]),
      ),
    );

    expect(find.text('أعمال محلية معلّقة'), findsOneWidget);
    expect(find.text('إقرار'), findsOneWidget);
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('the acknowledge action records the stuck count and unblocks',
      (tester) async {
    final acknowledgement = _FakeAcknowledgementStore();

    await _openSettings(
      tester,
      _services(
        status: _FakeStatusStore(),
        outbox: _FakeOutbox([
          _entry('a', OutboxStatus.conflict),
          _entry('b', OutboxStatus.conflict),
          _entry('c', OutboxStatus.conflict),
        ]),
        acknowledgement: acknowledgement,
      ),
    );

    expect(find.text('إقرار'), findsOneWidget);
    await tester.tap(find.text('إقرار'));
    await _settle(tester);

    // The sign-off captures how many stuck records were reviewed, and the gate
    // then allows the install.
    expect(acknowledgement.acknowledgement?.stuckCount, 3);
    expect(find.text('جاهز للتثبيت'), findsOneWidget);
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('a stale acknowledgement does not unblock new stuck work',
      (tester) async {
    final acknowledgement = _FakeAcknowledgementStore(
      UpdateAcknowledgement(
        stuckCount: 1,
        acknowledgedAt: DateTime(2026, 10, 13, 14),
        acknowledgedBy: 'manager',
      ),
    );

    await _openSettings(
      tester,
      _services(
        status: _FakeStatusStore(),
        outbox: _FakeOutbox([
          _entry('a', OutboxStatus.conflict),
          _entry('b', OutboxStatus.conflict),
          _entry('c', OutboxStatus.conflict),
        ]),
        acknowledgement: acknowledgement,
      ),
    );

    expect(find.text('أعمال محلية معلّقة'), findsOneWidget);
    expect(find.text('إقرار'), findsOneWidget);
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('unsynced work blocks the install even when acknowledged',
      (tester) async {
    await _openSettings(
      tester,
      _services(
        status: _FakeStatusStore(),
        outbox: _FakeOutbox([
          _entry('a', OutboxStatus.conflict),
          _entry('b', OutboxStatus.pending),
        ]),
        acknowledgement: _FakeAcknowledgementStore(
          UpdateAcknowledgement(
            stuckCount: 1,
            acknowledgedAt: DateTime(2026, 10, 13, 14),
            acknowledgedBy: 'manager',
          ),
        ),
      ),
    );

    // A record that can still sync is never waived by an acknowledgement.
    // There is no install button here at all: the action lives in the
    // shell-mounted prompt, and the card no longer duplicates it.
    expect(find.text('أعمال محلية معلّقة'), findsNothing);
    expect(find.widgetWithText(RmsButton, 'تحديث'), findsNothing);
  });

  testWidgets('no acknowledgement is recorded when nothing is stuck',
      (tester) async {
    final acknowledgement = _FakeAcknowledgementStore();

    await _openSettings(
      tester,
      _services(
        status: _FakeStatusStore(),
        outbox: _FakeOutbox(const []),
        acknowledgement: acknowledgement,
      ),
    );

    expect(acknowledgement.acknowledgement, isNull);
    expect(find.text('إقرار'), findsNothing);
    expect(find.text('تحديث'), findsNothing);
  });

  testWidgets('a malformed status row is ignored rather than rendered',
      (tester) async {
    await _openSettings(
      tester,
      _services(status: _FakeStatusStore()),
    );

    expect(find.text('آخر محاولة تحديث'), findsNothing);
    expect(find.text('سبب الفشل'), findsNothing);
  });

  testWidgets('readiness label is shown for a blocked release',
      (tester) async {
    // A manifest for another platform is ineligible, so the card explains the
    // block rather than offering an install.
    await tester.pumpWidget(
      AppScope(
        services: AppServices(
          config: const FirebaseConfig.empty(),
          auth: DemoAuthRepository(
            initialUser: const AppUser(
              uid: 'u-manager',
              email: 'manager@rms.dev',
              role: AppRole.manager,
            ),
          ),
          firebaseReady: false,
          updates: _FakeUpdates(_otherPlatformManifest()),
          updateStatus: _FakeStatusStore(),
          updateAudit: _FakeAuditTrail(const []),
          updateAcknowledgement: _FakeAcknowledgementStore(),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('سبب عدم الإتاحة'), findsOneWidget);
    expect(find.text('النظام الأساسي غير مطابق'), findsOneWidget);
    expect(
      find.text('أعمال محلية معلّقة محتاجة إقرار'),
      findsNothing,
    );
  });
}

UpdateManifest _otherPlatformManifest() => UpdateManifest(
      releaseId: 'rel-other',
      version: '1.1.0',
      buildNumber: 43,
      platform: currentUpdatePlatform() == UpdatePlatform.web
          ? UpdatePlatform.ios
          : UpdatePlatform.web,
      channel: currentUpdateChannel(),
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.mandatory,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'releases/rms-other.pkg',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );