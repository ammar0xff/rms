import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device currently has a usable network link.
///
/// The plugin surface is injected so the mapping and stream behaviour can be
/// unit-tested without a platform channel.
class ConnectivityMonitor {
  ConnectivityMonitor({
    Stream<List<ConnectivityResult>>? changes,
    Future<List<ConnectivityResult>> Function()? check,
  })  : _changes = changes,
        _check = check;

  final Stream<List<ConnectivityResult>>? _changes;
  final Future<List<ConnectivityResult>> Function()? _check;

  Connectivity? _source;

  Connectivity get _connectivity => _source ??= Connectivity();

  /// Emits whenever the online/offline state flips.
  Stream<bool> get onChanged =>
      (_changes ?? _connectivity.onConnectivityChanged)
          .map(hasConnection)
          .distinct();

  /// One-shot check of the current state.
  Future<bool> get isOnline async =>
      hasConnection(await (_check?.call() ?? _connectivity.checkConnectivity()));

  static bool hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
