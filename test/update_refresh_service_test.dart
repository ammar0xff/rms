import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/repositories/update_repository.dart';
import 'package:rms/src/data/updates/remote_update_source.dart';
import 'package:rms/src/data/updates/update_refresh_service.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

UpdateManifest _manifest({required int buildNumber, String version = '1.0.0'}) =>
    UpdateManifest(
      releaseId: 'android-$buildNumber',
      version: version,
      buildNumber: buildNumber,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'releases/android/$version/$buildNumber/app.apk',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );

class _FakeRemote implements RemoteUpdateSource {
  _FakeRemote(this.result);

  RemoteUpdateResult result;
  Object? throwInsteadOf;
  int calls = 0;

  @override
  Future<RemoteUpdateResult> fetch() async {
    calls++;
    final error = throwInsteadOf;
    if (error != null) throw error;
    return result;
  }
}

class _FakeCache implements UpdateRepository {
  _FakeCache([this.stored]);

  UpdateManifest? stored;
  int writes = 0;

  @override
  Future<UpdateManifest?> cached() async => stored;

  @override
  Future<void> cache(UpdateManifest manifest) async {
    writes++;
    stored = manifest;
  }
}

void main() {
  group('UpdateRefreshService', () {
    test('caches a manifest when the device has none', () async {
      final remote = _FakeRemote(RemoteUpdateResult(manifest: _manifest(
        buildNumber: 5,
      )));
      final cache = _FakeCache();

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.updated);
      expect(cache.stored?.buildNumber, 5);
      expect(cache.writes, 1);
    });

    test('replaces an older cached manifest', () async {
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(buildNumber: 9)),
      );
      final cache = _FakeCache(_manifest(buildNumber: 4));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.updated);
      expect(cache.stored?.buildNumber, 9);
    });

    // A stale or replayed document must never downgrade a device.
    test('never downgrades to an equal or older build', () async {
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(buildNumber: 4)),
      );
      final cache = _FakeCache(_manifest(buildNumber: 9));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.unchanged);
      expect(cache.stored?.buildNumber, 9);
      expect(cache.writes, 0);
    });

    test('treats an equal build as unchanged', () async {
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(buildNumber: 9)),
      );
      final cache = _FakeCache(_manifest(buildNumber: 9));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.unchanged);
      expect(cache.writes, 0);
    });

    // The cache is authoritative: an update check is a convenience, never a
    // dependency.
    test('keeps the cache when the backend is unreachable', () async {
      final remote = _FakeRemote(const RemoteUpdateResult.offline());
      final cache = _FakeCache(_manifest(buildNumber: 9));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.offline);
      expect(cache.stored?.buildNumber, 9);
      expect(cache.writes, 0);
    });

    test('keeps the cache when a source violates its contract and throws',
        () async {
      final remote = _FakeRemote(
        const RemoteUpdateResult.none(),
      )..throwInsteadOf = StateError('boom');
      final cache = _FakeCache(_manifest(buildNumber: 9));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.offline);
      expect(cache.stored?.buildNumber, 9);
      expect(cache.writes, 0);
    });

    test('reports unchanged when nothing is published', () async {
      final remote = _FakeRemote(const RemoteUpdateResult.none());
      final cache = _FakeCache();

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.unchanged);
      expect(cache.stored, isNull);
      expect(cache.writes, 0);
    });

    test('treats an unparseable published document as nothing published',
        () async {
      final remote = _FakeRemote(const RemoteUpdateResult.none());
      final cache = _FakeCache(_manifest(buildNumber: 3));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.unchanged);
      expect(cache.stored?.buildNumber, 3);
    });

    test('accepts a newer version even when its build counter lags', () async {
      // Same counter family, but the build number went backwards while the
      // version went forwards (counters reset across version lines). Comparing
      // build numbers alone pinned the device on the old release forever.
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(version: '2.0.0', buildNumber: 1)),
      );
      final cache = _FakeCache(_manifest(version: '1.0.0', buildNumber: 40));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.updated);
      expect(cache.stored?.version, '2.0.0');
    });

    test('rejects an older version even when its build counter leads', () async {
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(version: '1.0.0', buildNumber: 99)),
      );
      final cache = _FakeCache(_manifest(version: '2.0.0', buildNumber: 2));

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.unchanged);
      expect(cache.stored?.version, '2.0.0');
    });

    test('skips the fetch where artifact delivery is unsupported', () async {
      final remote = _FakeRemote(
        RemoteUpdateResult(manifest: _manifest(buildNumber: 99)),
      );
      final cache = _FakeCache();

      final outcome = await UpdateRefreshService(
        remote: remote,
        cache: cache,
        artifactDeliverySupported: false,
      ).refresh();

      expect(outcome, UpdateRefreshOutcome.skipped);
      expect(remote.calls, 0);
      expect(cache.writes, 0);
    });
  });
}