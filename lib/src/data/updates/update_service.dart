import '../../domain/models/update_manifest.dart';
import '../../domain/update/artifact_verifier.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/update_acknowledgement.dart';
import '../../domain/update/update_audit_sink.dart';
import '../../domain/update/update_check_result.dart';
import '../../domain/update/update_decision.dart';
import '../../domain/update/update_health_checker.dart';
import '../../domain/update/update_installer.dart';
import '../../domain/update/update_lifecycle_coordinator.dart';
import '../../domain/update/update_migrator.dart';
import '../../domain/update/update_readiness.dart';
import '../local/outbox/outbox_access.dart';
import '../local/update_store_contracts.dart';

/// Everything the update flow needs, injected.
///
/// The service itself holds no state and performs no I/O of its own, so the
/// whole flow — including the parts that persist status and append audit
/// events — can be exercised with fakes.
class UpdateDeps {
  UpdateDeps({
    required this.downloader,
    required this.installer,
    required this.migrator,
    required this.healthChecker,
    this.outbox,
    this.auditSink,
    this.statusStore,
  });

  final ArtifactDownloader downloader;
  final UpdateInstaller installer;
  final UpdateMigrator migrator;
  final UpdateHealthChecker healthChecker;

  /// Null when there is no local store; the gate then reports no work.
  final OutboxAccess? outbox;

  final UpdateAuditSink? auditSink;
  final UpdateStatusStore? statusStore;
}

/// Sequences the update flow for a device.
///
/// Three steps, in the order the v1.2 addendum defines them:
///
/// 1. **check** — refresh the manifest, classify it against this device, and ask
///    the AC-35 gate whether installing now would risk unsynced local work.
/// 2. **apply** — hand the decision and the gate's verdict to the coordinator,
///    which downloads, verifies, installs, migrates and health-checks.
/// 3. **record** — persist the terminal status so a device that was rebooted
///    mid-update still reports what it was doing.
///
/// Nothing here bypasses the gate. A mandatory release waits for the backlog
/// exactly as an optional one does.
class UpdateService {
  const UpdateService({
    required this.deps,
    required this.deviceContext,
    required this.work,
    required this.acknowledgement,
    this.now,
  });

  final UpdateDeps deps;
  final UpdateContext deviceContext;
  final LocalWorkSnapshot work;
  final UpdateAcknowledgement? acknowledgement;
  final DateTime Function()? now;

  /// Classifies the release and asks whether it may be installed now.
  ///
  /// [manifest] is whatever the cache holds; the caller refreshes it first when
  /// it wants the newest document.
  UpdateCheckResult check(UpdateManifest? manifest) {
    final decision = UpdateDecisionEngine.decide(
      manifest: manifest,
      context: deviceContext,
    );
    final readiness = UpdateReadinessEngine.classify(
      decision: decision,
      work: work,
      acknowledgement: acknowledgement,
    );
    return UpdateCheckResult(decision: decision, readiness: readiness);
  }

  /// Runs the full install lifecycle for a release the check has already
  /// approved, and records the outcome.
  ///
  /// Safe to call when the gate is closed: the coordinator returns `idle`
  /// without downloading anything, so a caller cannot accidentally force an
  /// install past AC-35 by calling this directly.
  Future<DeviceUpdateStatus> apply(UpdateCheckResult check) async {
    final coordinator = UpdateLifecycleCoordinator(
      decision: check.decision,
      readiness: check.readiness,
      downloader: deps.downloader,
      installer: deps.installer,
      migrator: deps.migrator,
      healthChecker: deps.healthChecker,
      auditSink: deps.auditSink,
      now: now,
    );

    final status = await coordinator.execute();
    await deps.statusStore?.save(status);
    return status;
  }

  /// The convenience path: classify, and install if the gate allows.
  Future<DeviceUpdateStatus> checkAndApply(UpdateManifest? manifest) =>
      apply(check(manifest));
}