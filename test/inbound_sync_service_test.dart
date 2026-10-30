import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/sync/inbound_sync_service.dart';

void main() {
  group('InboundSyncService LWW monotonicity and timestamp resolution', () {
    test('extracts ISO-8601 string timestamp correctly', () {
      final record = {
        'id': 'ord-1',
        'updatedAt': '2026-10-30T10:00:00.000Z',
      };
      final ts = InboundSyncService.extractTimestamp(record);
      expect(ts, isNotNull);
      expect(ts, DateTime.utc(2026, 10, 30, 10, 0, 0));
    });

    test('extracts Firestore Timestamp correctly', () {
      final now = DateTime.utc(2026, 10, 30, 12, 30, 0);
      final record = {
        'id': 'ord-2',
        'lastModifiedAt': Timestamp.fromDate(now),
      };
      final ts = InboundSyncService.extractTimestamp(record);
      expect(ts, isNotNull);
      expect(ts, now);
    });

    test('extracts epoch milliseconds and seconds integers', () {
      const millis = 1793361600000;
      final recordMillis = {'timestamp': millis};
      final tsMillis = InboundSyncService.extractTimestamp(recordMillis);
      expect(tsMillis?.millisecondsSinceEpoch, millis);

      const seconds = 1793361600;
      final recordSeconds = {'createdAt': seconds};
      final tsSeconds = InboundSyncService.extractTimestamp(recordSeconds);
      expect(tsSeconds?.millisecondsSinceEpoch, seconds * 1000);
    });

    test('prefers updatedAt over createdAt', () {
      final record = {
        'createdAt': '2026-10-30T08:00:00.000Z',
        'updatedAt': '2026-10-30T14:00:00.000Z',
      };
      final ts = InboundSyncService.extractTimestamp(record);
      expect(ts, DateTime.utc(2026, 10, 30, 14, 0, 0));
    });

    test('isLocalNewer returns true when local is strictly newer', () {
      final local = {
        'id': 'ord-10',
        'updatedAt': '2026-10-30T15:00:00.000Z',
        'status': 'settled',
      };
      final remote = {
        'id': 'ord-10',
        'updatedAt': '2026-10-30T14:59:00.000Z',
        'status': 'pending',
      };

      expect(InboundSyncService.isLocalNewer(local, remote), isTrue);
    });

    test('isLocalNewer returns false when remote is newer or equal', () {
      final local = {
        'id': 'ord-10',
        'updatedAt': '2026-10-30T15:00:00.000Z',
      };
      final remoteNewer = {
        'id': 'ord-10',
        'updatedAt': '2026-10-30T15:01:00.000Z',
      };
      final remoteEqual = {
        'id': 'ord-10',
        'updatedAt': '2026-10-30T15:00:00.000Z',
      };

      expect(InboundSyncService.isLocalNewer(local, remoteNewer), isFalse);
      expect(InboundSyncService.isLocalNewer(local, remoteEqual), isFalse);
    });

    test('isLocalNewer returns false when timestamps are absent', () {
      final local = {'id': 'ord-10'};
      final remote = {'id': 'ord-10'};

      expect(InboundSyncService.isLocalNewer(local, remote), isFalse);
    });
  });
}
