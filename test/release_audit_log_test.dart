import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/release_audit_log.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';

int _seq = 0;

ReleaseAuditEvent _event({
  String eventId = 'evt-1',
  String releaseId = 'rel-1',
  DateTime? at,
  ReleaseAuditEventType type = ReleaseAuditEventType.downloadStarted,
}) =>
    ReleaseAuditEvent(
      eventId: eventId,
      releaseId: releaseId,
      occurredAt: at ?? DateTime(2026, 10, 13, 14),
      eventType: type,
    );

void main() {
  late LocalDatabase db;
  late ReleaseAuditLog log;

  setUp(() async {
    db = await LocalDatabase.memory('rms_audit_${_seq++}');
    log = ReleaseAuditLog(db);
  });

  tearDown(() async => db.close());

  test('appends an event through the audit sink contract', () async {
    await log.append(_event());

    expect(await log.count(), 1);
    final events = await log.list();
    expect(events.single.eventId, 'evt-1');
    expect(events.single.eventType, ReleaseAuditEventType.downloadStarted);
  });

  test('lists events newest first', () async {
    await log.append(_event(eventId: 'e1', at: DateTime(2026, 10, 13, 10)));
    await log.append(_event(eventId: 'e2', at: DateTime(2026, 10, 13, 12)));
    await log.append(_event(eventId: 'e3', at: DateTime(2026, 10, 13, 11)));

    final ids = (await log.list()).map((e) => e.eventId).toList();
    expect(ids, ['e2', 'e3', 'e1']);
  });

  test('caps the list at the requested limit', () async {
    for (var i = 0; i < 5; i++) {
      await log.append(
        _event(eventId: 'e$i', at: DateTime(2026, 10, 13, 10 + i)),
      );
    }

    expect((await log.list(limit: 2)).length, 2);
    expect(await log.count(), 5);
  });

  test('forRelease filters by release id', () async {
    await log.append(_event(eventId: 'a1', releaseId: 'rel-1'));
    await log.append(_event(eventId: 'b1', releaseId: 'rel-2'));
    await log.append(_event(eventId: 'a2', releaseId: 'rel-1'));

    final forOne = await log.forRelease('rel-1');
    expect(forOne.length, 2);
    expect(forOne.map((e) => e.eventId).toSet(), {'a1', 'a2'});
    expect(await log.forRelease('rel-missing'), isEmpty);
  });

  test('preserves event fields across a round trip', () async {
    final original = ReleaseAuditEvent(
      eventId: 'evt-full',
      releaseId: 'rel-9',
      occurredAt: DateTime(2026, 10, 13, 14, 30),
      eventType: ReleaseAuditEventType.healthCheckFailed,
      deviceId: 'dev-1',
      deviceGroup: 'terminals',
      outcome: 'failed',
      reason: 'health',
      actorId: 'manager',
      metadata: const {'attempt': 2},
    );

    await log.append(original);
    final restored = (await log.list()).single;

    expect(restored.eventId, original.eventId);
    expect(restored.releaseId, original.releaseId);
    expect(restored.occurredAt, original.occurredAt);
    expect(restored.eventType, original.eventType);
    expect(restored.deviceId, 'dev-1');
    expect(restored.deviceGroup, 'terminals');
    expect(restored.outcome, 'failed');
    expect(restored.reason, 'health');
    expect(restored.actorId, 'manager');
    expect(restored.metadata['attempt'], 2);
  });

  test('appends within a caller transaction', () async {
    await db.transaction((txn) => log.add(txn, _event(eventId: 'txn-1')));

    expect((await log.list()).single.eventId, 'txn-1');
  });

  test('drops a malformed row without hiding the rest', () async {
    await log.append(_event(eventId: 'good-1'));
    await LocalStores.releaseAuditEvents.record('corrupt').put(
          db.db,
          const {'eventId': 'corrupt'},
        );
    await log.append(_event(eventId: 'good-2'));

    // The row is stored but not surfaced, and the readable trail still works.
    expect(await log.count(), 3);
    final events = await log.list();
    expect(events.length, 2);
    expect(events.map((e) => e.eventId).toSet(), {'good-1', 'good-2'});
  });

  test('reads back from the database, not from instance state', () async {
    await log.append(_event(eventId: 'persisted'));

    // A second log over the same database must see the event, proving reads go
    // to storage rather than to anything cached on the instance.
    final second = ReleaseAuditLog(db);
    expect((await second.list()).single.eventId, 'persisted');
    expect(await second.count(), 1);
  });
}