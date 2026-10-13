import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/update_status_store.dart';
import 'package:rms/src/data/repositories/local_update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/device_update_status.dart';

int _seq = 0;

final _sha = 'a' * 64;

UpdateManifest _manifest() => UpdateManifest(
      releaseId: 'rel-1',
      version: '1.1.0',
      buildNumber: 42,
      platform: UpdatePlatform.web,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'https://example.com/app.tar.gz',
        sizeBytes: 1000,
        sha256: _sha,
      ),
    );

void main() {
  late LocalDatabase db;
  late LocalUpdateStatusStore store;

  setUp(() async {
    db = await LocalDatabase.memory('rms_status_${_seq++}');
    store = LocalUpdateStatusStore(db);
  });

  tearDown(() async => db.close());

  test('load returns null when nothing was stored', () async {
    expect(await store.load(), isNull);
  });

  test('round-trips a terminal failure', () async {
    final at = DateTime(2026, 10, 13, 14, 30);
    await store.save(
      DeviceUpdateStatus(
        state: UpdateLifecycleState.failed,
        statusAt: at,
        releaseId: 'rel-1',
        version: '1.1.0',
        buildNumber: 42,
        progress: 0.8,
        health: UpdateHealthStatus.failed,
        failureReason: UpdateFailureReason.healthCheckFailed,
        errorMessage: 'health check failed',
        rollbackTargetVersion: '1.0.0',
        requiresRollback: true,
        lastAppliedAt: at,
      ),
    );

    final restored = await store.load();
    expect(restored, isNotNull);
    expect(restored!.state, UpdateLifecycleState.failed);
    expect(restored.releaseId, 'rel-1');
    expect(restored.version, '1.1.0');
    expect(restored.buildNumber, 42);
    expect(restored.progress, 0.8);
    expect(restored.health, UpdateHealthStatus.failed);
    expect(restored.failureReason, UpdateFailureReason.healthCheckFailed);
    expect(restored.errorMessage, 'health check failed');
    expect(restored.rollbackTargetVersion, '1.0.0');
    expect(restored.requiresRollback, isTrue);
    expect(restored.lastAppliedAt, at);
  });

  test('round-trips an idle status with its null timestamps', () async {
    await store.save(
      const DeviceUpdateStatus(state: UpdateLifecycleState.idle),
    );

    final restored = await store.load();
    expect(restored!.state, UpdateLifecycleState.idle);
    expect(restored.statusAt, isNull);
    expect(restored.lastAppliedAt, isNull);
    expect(restored.health, UpdateHealthStatus.pending);
    expect(restored.failureReason, UpdateFailureReason.none);
  });

  test('a later save replaces the earlier status', () async {
    await store.save(
      const DeviceUpdateStatus(
        state: UpdateLifecycleState.installing,
        releaseId: 'rel-1',
      ),
    );
    await store.save(
      const DeviceUpdateStatus(
        state: UpdateLifecycleState.completed,
        releaseId: 'rel-1',
      ),
    );

    final restored = await store.load();
    expect(restored!.state, UpdateLifecycleState.completed);
    expect(await LocalStores.config.count(db.db), 1);
  });

  test('a malformed row is treated as absent', () async {
    await LocalStores.config.record(LocalUpdateStatusStore.statusKey).put(
          db.db,
          const {'state': 'nonsense'},
        );

    expect(await store.load(), isNull);
  });

  test('coexists with the cached manifest in the config store', () async {
    // Both live under LocalStores.config, so neither may clobber the other.
    await LocalUpdateRepository(db).cache(_manifest());
    await store.save(
      const DeviceUpdateStatus(
        state: UpdateLifecycleState.completed,
        releaseId: 'rel-1',
      ),
    );

    expect((await store.load())!.state, UpdateLifecycleState.completed);
    final manifest = await LocalUpdateRepository(db).cached();
    expect(manifest!.releaseId, 'rel-1');
    expect(manifest.version, '1.1.0');
  });

  test('uses a distinct config key from the manifest', () {
    expect(LocalUpdateStatusStore.statusKey, isNot(LocalUpdateRepository.manifestKey));
  });
}