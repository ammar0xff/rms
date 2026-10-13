import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';
import 'package:rms/src/domain/update/update_policy.dart';

void main() {
  group('DeviceUpdateStatus', () {
    test('copyWith updates fields and preserves others', () {
      const base = DeviceUpdateStatus(state: UpdateLifecycleState.idle);
      final updated = base.copyWith(
        state: UpdateLifecycleState.installing,
        releaseId: 'rel-1',
        version: '1.0.0',
        progress: 0.25,
      );
      expect(updated.state, UpdateLifecycleState.installing);
      expect(updated.releaseId, 'rel-1');
      expect(updated.version, '1.0.0');
      expect(updated.progress, 0.25);
      expect(updated.statusAt, isNull);
    });

    test('isActive and isTerminal reflect lifecycle', () {
      expect(const DeviceUpdateStatus(state: UpdateLifecycleState.installing).isActive, isTrue);
      expect(const DeviceUpdateStatus(state: UpdateLifecycleState.completed).isTerminal, isTrue);
      expect(const DeviceUpdateStatus(state: UpdateLifecycleState.failed).isTerminal, isTrue);
      expect(const DeviceUpdateStatus(state: UpdateLifecycleState.idle).isActive, isFalse);
      expect(const DeviceUpdateStatus(state: UpdateLifecycleState.idle).isTerminal, isFalse);
    });
  });

  group('ReleaseAuditEvent', () {
    test('round-trips through a record', () {
      final ev = ReleaseAuditEvent(
        eventId: 'evt-1',
        releaseId: 'rel-1',
        occurredAt: DateTime(2026, 10, 13, 15, 0, 0),
        eventType: ReleaseAuditEventType.downloadCompleted,
        deviceId: 'dev-1',
        deviceGroup: 'terminals',
        outcome: 'ok',
        reason: '',
        actorId: 'sys',
        metadata: const {'bytes': 100},
      );
      final rec = ev.toRecord();
      final parsed = ReleaseAuditEvent.tryFromRecord(rec);
      expect(parsed, isNotNull);
      expect(parsed!.eventId, ev.eventId);
      expect(parsed.releaseId, ev.releaseId);
      expect(parsed.eventType, ev.eventType);
      expect(parsed.metadata['bytes'], 100);
    });

    test('rejects malformed records', () {
      expect(ReleaseAuditEvent.tryFromRecord(const {}), isNull);
      expect(ReleaseAuditEvent.tryFromRecord(const {'eventId': ''}), isNull);
      expect(ReleaseAuditEvent.tryFromRecord(const {'eventId': 'e', 'releaseId': 'r'}), isNull);
    });
  });

  group('UpdatePolicy', () {
    test('copyWith updates mode and preserves flags', () {
      const base = UpdatePolicy(mode: UpdatePolicyMode.prompt, allowWifiOnly: true);
      final updated = base.copyWith(mode: UpdatePolicyMode.auto, allowBeta: true);
      expect(updated.mode, UpdatePolicyMode.auto);
      expect(updated.allowBeta, isTrue);
      expect(updated.allowWifiOnly, isTrue);
    });
  });
}
