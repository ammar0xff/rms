import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/updates/firestore_update_source.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

final _sha = 'a' * 64;

UpdateManifest _manifest({
  String releaseId = 'android-0.10.0-2',
  int buildNumber = 2,
  UpdatePlatform platform = UpdatePlatform.android,
}) =>
    UpdateManifest(
      releaseId: releaseId,
      version: '0.10.0',
      buildNumber: buildNumber,
      platform: platform,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.recommended,
      publishedAt: DateTime(2026, 10, 14),
      artifact: ReleaseArtifact(
        reference: 'https://example.com/app.apk',
        sizeBytes: 57329281,
        sha256: _sha,
      ),
    );

/// Records the reads it is asked for, so the ordering can be asserted.
class _Reader {
  _Reader(this.documents);

  final Map<String, Map<String, dynamic>?> documents;
  final List<String> reads = [];
  Object? throwOn;

  Future<Map<String, dynamic>?> call(String collection, String id) async {
    reads.add('$collection/$id');
    final error = throwOn;
    if (error != null) throw error;
    return documents['$collection/$id'];
  }
}

void main() {
  group('FirestoreUpdateSource', () {
    // Demo mode, where Firebase was never configured.
    test('reports nothing when there is no backend at all', () async {
      final source = FirestoreUpdateSource(platform: UpdatePlatform.android);

      final result = await source.fetch();

      expect(result.isUsable, isFalse);
      expect(result.unreachable, isFalse);
    });

    test('resolves the manifest the pointer names', () async {
      final manifest = _manifest();
      final reader = _Reader({
        'activeReleases/android': {'releaseId': 'android-0.10.0-2'},
        'releases/android-0.10.0-2': manifest.toRecord(),
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      final result = await source.fetch();

      expect(result.isUsable, isTrue);
      expect(result.manifest!.releaseId, 'android-0.10.0-2');
      expect(result.manifest!.buildNumber, 2);
      expect(result.manifest!.artifact.sizeBytes, 57329281);
    });

    // The pointer exists precisely so a device fetches one small document and
    // decides whether the larger one is worth reading.
    test('reads the pointer before the manifest', () async {
      final reader = _Reader({
        'activeReleases/android': {'releaseId': 'r-1'},
        'releases/r-1': _manifest(releaseId: 'r-1').toRecord(),
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      await source.fetch();

      expect(reader.reads, ['activeReleases/android', 'releases/r-1']);
    });

    test('does not fetch a manifest it will not be offered', () async {
      final reader = _Reader({'releases/r-1': _manifest().toRecord()});
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      final result = await source.fetch();

      expect(result.isUsable, isFalse);
      expect(reader.reads, ['activeReleases/android']);
    });

    test('reports nothing when the pointer names no release', () async {
      final reader = _Reader({
        'activeReleases/android': {'somethingElse': 'r-1'},
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      expect((await source.fetch()).isUsable, isFalse);
    });

    test('reports nothing when the pointer names an empty release', () async {
      final reader = _Reader({
        'activeReleases/android': {'releaseId': ''},
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      expect((await source.fetch()).isUsable, isFalse);
    });

    test('reports nothing when the named manifest is absent', () async {
      final reader = _Reader({
        'activeReleases/android': {'releaseId': 'r-missing'},
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      expect((await source.fetch()).isUsable, isFalse);
    });

    // A document written by a newer publisher, or truncated in transit, must
    // not wipe the cached manifest.
    test('treats a malformed manifest as absent', () async {
      final reader = _Reader({
        'activeReleases/android': {'releaseId': 'r-1'},
        'releases/r-1': {'releaseId': 'r-1'},
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      final result = await source.fetch();

      expect(result.isUsable, isFalse);
      // A parse failure is not a connectivity problem.
      expect(result.unreachable, isFalse);
    });

    // An unreachable backend is reported distinctly, because it means something
    // different to an operator than "you are up to date".
    test('reports the backend as unreachable when a read throws', () async {
      final reader = _Reader({})
        ..throwOn = StateError('permission denied');
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: reader.call,
      );

      final result = await source.fetch();

      expect(result.isUsable, isFalse);
      expect(result.unreachable, isTrue);
    });

    test('reports the backend as unreachable when the manifest read throws',
        () async {
      // Fail only on the second read, so the pointer resolves first and the
      // failure is specifically about the manifest fetch.
      Future<Map<String, dynamic>?> guarded(String collection, String id) async {
        if (collection == 'releases') throw StateError('flaky');
        return {'releaseId': 'r-1'};
      }

      final result = await FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        readDocuments: guarded,
      ).fetch();

      expect(result.isUsable, isFalse);
      expect(result.unreachable, isTrue);
    });

    // A desktop device must not pick up a pointer published for Android.
    test('keys the pointer on the requesting platform', () async {
      final reader = _Reader({
        'activeReleases/windows': {'releaseId': 'win-1'},
        'releases/win-1': _manifest(releaseId: 'win-1').toRecord(),
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.windows,
        readDocuments: reader.call,
      );

      final result = await source.fetch();

      expect(result.isUsable, isTrue);
      expect(reader.reads.first, 'activeReleases/windows');
    });

    test('honours custom collection names', () async {
      final reader = _Reader({
        'pointers/android': {'releaseId': 'r-1'},
        'manifests/r-1': _manifest(releaseId: 'r-1').toRecord(),
      });
      final source = FirestoreUpdateSource(
        platform: UpdatePlatform.android,
        releasesCollection: 'manifests',
        pointerCollection: 'pointers',
        readDocuments: reader.call,
      );

      expect((await source.fetch()).isUsable, isTrue);
      expect(reader.reads, ['pointers/android', 'manifests/r-1']);
    });
  });
}
