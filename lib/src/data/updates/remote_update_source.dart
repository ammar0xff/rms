import '../../domain/models/update_manifest.dart';

/// The result of asking the backend for a manifest.
///
/// Distinguishes "unreachable" from "nothing published" because the two mean
/// different things to an operator: the first is a connectivity problem worth
/// surfacing, the second is simply an up-to-date device.
class RemoteUpdateResult {
  const RemoteUpdateResult({this.manifest, this.unreachable = false});

  /// Nothing published, or the document could not be parsed.
  const RemoteUpdateResult.none() : this(manifest: null);

  /// The backend could not be reached.
  const RemoteUpdateResult.offline() : this(manifest: null, unreachable: true);

  final UpdateManifest? manifest;
  final bool unreachable;

  bool get isUsable => manifest != null;
}

/// Reads the release manifest the backend published for this device.
///
/// Split from [UpdateRepository] so the local cache and the network stay
/// separate: the cache is what the decision engine reads offline, and this is
/// only ever asked to bring it up to date.
abstract class RemoteUpdateSource {
  /// The published manifest. Implementations never throw: a failure is reported
  /// as [RemoteUpdateResult.offline] and the cached document keeps standing.
  Future<RemoteUpdateResult> fetch();
}