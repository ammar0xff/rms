import '../../core/config/device_update_context.dart';
import '../../domain/models/update_manifest.dart';
import '../../domain/update/update_check_result.dart';
import '../../domain/update/update_decision.dart';
import '../local/outbox/outbox_access.dart';
import '../local/outbox/outbox_snapshot.dart';
import '../local/update_store_contracts.dart';
import '../repositories/update_repository.dart';
import 'remote_update_source.dart';
import 'update_refresh_service.dart';
import 'update_service.dart';

/// Assembles the update flow against live device state.
///
/// [UpdateService] deliberately takes a snapshot of the decision inputs, so it
/// cannot be held for the lifetime of the app: the local-work counts change as
/// orders are taken, and the acknowledgement changes when an operator signs
/// off. This builds a fresh service for every check, so AC-35 is always judged
/// against the backlog as it is now rather than as it was at launch.
class UpdateRuntime {
  UpdateRuntime({
    required this.cache,
    required this.outbox,
    required this.buildService,
    this.remote,
    this.acknowledgement,
    this.branchId,
    this.online,
    this.artifactDeliverySupported = true,
    this.now,
  });

  final UpdateRepository cache;

  /// Null when there is no local store; the gate then reports no work.
  final OutboxAccess? outbox;

  /// Builds the service's collaborators. Supplied by bootstrap so the runtime
  /// itself stays free of platform dependencies.
  final UpdateDeps Function() buildService;

  final RemoteUpdateSource? remote;
  final UpdateAcknowledgementStore? acknowledgement;

  /// Supplies the branch id, which doubles as the rollout cohort seed.
  final Future<String> Function()? branchId;

  final bool Function()? online;

  /// False on platforms that take no release artifact, which skip polling.
  final bool artifactDeliverySupported;

  final DateTime Function()? now;

  DateTime _now() => now?.call() ?? DateTime.now();

  /// The manifest to act on.
  ///
  /// A published release is fetched first when a remote source is configured,
  /// but a failed fetch never clears the cache, so the device always has
  /// something to classify even offline.
  Future<UpdateManifest?> manifest() async {
    final source = remote;
    if (source != null && artifactDeliverySupported) {
      await UpdateRefreshService(
        remote: source,
        cache: cache,
        artifactDeliverySupported: artifactDeliverySupported,
      ).refresh();
    }
    return cache.cached();
  }

  /// A service bound to the device's state as it is right now.
  Future<UpdateService> service() async {
    final branch = await branchId?.call() ?? '';
    final work = await loadLocalWorkSnapshot(
      outbox,
      online: online?.call() ?? false,
    );
    final ack = await acknowledgement?.load();

    return UpdateService(
      deps: buildService(),
      deviceContext: buildUpdateContext(
        now: _now(),
        branchId: branch,
        // The branch is the stable per-device seed, so a device always lands in
        // the same rollout bucket.
        cohortSeed: branch,
      ),
      work: work,
      acknowledgement: ack,
      now: now,
    );
  }

  /// Classifies the current release against the current device state.
  Future<UpdateCheckResult> check() async =>
      (await service()).check(await manifest());

  /// Classifies a specific manifest without refetching. Used when the caller
  /// already has one, such as straight after an install.
  Future<UpdateCheckResult> checkManifest(UpdateManifest? manifest) async =>
      (await service()).check(manifest);
}

/// Convenience for the decision-only path, which needs no collaborators.
UpdateDecision decisionFor(UpdateManifest? manifest, UpdateContext context) =>
    UpdateDecisionEngine.decide(manifest: manifest, context: context);