import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/updates/update_service.dart';
import '../../domain/models/update_manifest.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/download_state.dart';
import '../../domain/update/update_check_result.dart';
import '../../domain/update/update_prompt_mode.dart';
import '../../domain/update/update_prompt_state.dart';

/// Drives the update flow and exposes what the UI should show.
///
/// Owns the state machine the prompt reacts to: check, apply, record. Progress
/// comes from the downloader rather than being simulated, so what the operator
/// sees is the real transfer.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.service,
    required this.manifest,
    this.now,
  });

  /// Supplies the manifest to act on. Called on every check so a newly
  /// published release is picked up without recreating the controller.
  final UpdateManifest? Function() manifest;

  final UpdateService service;
  final DateTime Function()? now;

  UpdateCheckResult? _check;
  UpdatePromptMode? _inFlight;
  DeviceUpdateStatus? _lastStatus;
  double _progress = 0.0;
  String _detail = '';
  StreamSubscription<DownloadState>? _downloads;
  bool _checking = false;

  UpdatePromptState get state => UpdatePromptState.derive(
        check: _check ?? UpdateCheckResult.empty,
        inFlight: _inFlight,
        detail: _detail,
        progress: _progress,
      );

  UpdateCheckResult? get check => _check;

  DeviceUpdateStatus? get lastStatus => _lastStatus;

  bool get isChecking => _checking;

  /// Classifies the release currently held by the cache or backend.
  Future<void> refresh() async {
    _checking = true;
    notifyListeners();
    try {
      final result = service.check(manifest());
      _check = result;
      _detail = result.isBlockedByLocalWork
          ? result.readiness.status.label
          : '';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Applies the release, if the gate allows it.
  ///
  /// Returns without touching the network when the gate is closed, so the
  /// button being wrong cannot install past AC-35.
  Future<void> apply() async {
    final current = _check;
    if (current == null || !current.canInstall) return;

    _inFlight = UpdatePromptMode.working;
    _progress = 0.0;
    _detail = '';
    notifyListeners();

    await _subscribeToDownloads();
    try {
      final status = await service.apply(current);
      _lastStatus = status;
      _inFlight = switch (status.state) {
        UpdateLifecycleState.completed => UpdatePromptMode.completed,
        UpdateLifecycleState.failed || UpdateLifecycleState.rolledBack =>
          UpdatePromptMode.failed,
        _ => null,
      };
      _detail = status.failureReason == UpdateFailureReason.none
          ? ''
          : status.failureReason.label;
    } finally {
      await _downloads?.cancel();
      _downloads = null;
      notifyListeners();
    }
  }

  /// Clears a completed or failed attempt so the prompt stops showing.
  void acknowledge() {
    _inFlight = null;
    _detail = '';
    _progress = 0.0;
    notifyListeners();
  }

  Future<void> _subscribeToDownloads() async {
    await _downloads?.cancel();
    _downloads = service.deps.downloader.progress().listen((download) {
      switch (download.stage) {
        case DownloadStage.downloading || DownloadStage.verifying:
          _progress = download.progress;
          notifyListeners();
        case DownloadStage.failed:
          _detail = download.error;
          notifyListeners();
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _downloads?.cancel();
    super.dispose();
  }
}