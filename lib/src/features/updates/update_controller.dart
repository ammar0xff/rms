import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/updates/update_runtime.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/download_state.dart';
import '../../domain/update/update_prompt_mode.dart';
import '../../domain/update/update_prompt_state.dart';

/// Drives the update flow and exposes what the UI should show.
///
/// Owns the state machine the prompt reacts to: check, apply, record. Progress
/// comes from the real downloader rather than being simulated, so what the
/// operator sees is the actual transfer.
///
/// Every check builds a fresh [UpdateService] through the runtime, so AC-35 is
/// judged against the backlog as it is now — an operator cannot be offered an
/// install that was safe five minutes ago but is not any more.
class UpdateController extends ChangeNotifier {
  UpdateController({required this.runtime});

  final UpdateRuntime runtime;

  UpdatePromptState _state = const UpdatePromptState(
    mode: UpdatePromptMode.none,
  );
  UpdatePromptMode? _inFlight;
  DeviceUpdateStatus? _lastStatus;
  double _progress = 0.0;
  String _detail = '';
  StreamSubscription<DownloadState>? _downloads;
  bool _checking = false;

  UpdatePromptState get state => _state;

  DeviceUpdateStatus? get lastStatus => _lastStatus;

  bool get isChecking => _checking;

  /// True once a check has run at least once.
  bool get hasChecked => _state.mode != UpdatePromptMode.none || _checkedOnce;
  bool _checkedOnce = false;

  /// Classifies the release currently published or cached.
  Future<void> refresh() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();
    try {
      final check = await runtime.check();
      _checkedOnce = true;
      _derive(check);
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Applies the release the last check approved.
  ///
  /// Returns without touching the network when there is nothing checked or the
  /// gate is closed, so a stale button cannot install past AC-35.
  Future<void> apply() async {
    if (!_state.canApply) return;

    _inFlight = UpdatePromptMode.working;
    _progress = 0.0;
    _detail = '';
    _rebuild();

    await _subscribeToDownloads();
    try {
      final service = await runtime.service();
      final status = await service.apply(_state.check!);
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
      _rebuild();
    }
  }

  /// Clears a completed or failed attempt so the prompt stops showing, then
  /// re-checks so a newer release can surface.
  Future<void> acknowledge() async {
    _inFlight = null;
    _detail = '';
    _progress = 0.0;
    _rebuild();
    await refresh();
  }

  /// Runs the attempt again after a failure: clears the terminal state,
  /// re-checks against the backlog as it is now, and applies when the gate
  /// allows. If the gate is closed the prompt falls back to showing why,
  /// rather than spinning on an install that cannot proceed.
  Future<void> retry() async {
    _inFlight = null;
    _detail = '';
    _progress = 0.0;
    _rebuild();
    await refresh();
    await apply();
  }

  void _derive(dynamic check) {
    _state = UpdatePromptState.derive(
      check: check,
      inFlight: _inFlight,
      detail: _detail,
      progress: _progress,
    );
  }

  /// Recomputes the prompt against the last check, keeping the in-flight state.
  void _rebuild() {
    final check = _state.check;
    _state = check == null
        ? const UpdatePromptState(mode: UpdatePromptMode.none)
        : UpdatePromptState.derive(
            check: check,
            inFlight: _inFlight,
            detail: _detail,
            progress: _progress,
          );
    notifyListeners();
  }

  Future<void> _subscribeToDownloads() async {
    await _downloads?.cancel();
    _downloads = runtime.buildService().downloader.progress().listen((download) {
      switch (download.stage) {
        case DownloadStage.downloading || DownloadStage.verifying:
          _progress = download.progress;
          _rebuild();
        case DownloadStage.failed:
          _detail = download.error;
          _rebuild();
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