import '../../domain/models/update_manifest.dart';

/// The result of asking the backend for a manifest.
///
/// Distinguishes "unreachable" from "nothing published" because the two mean
/// different things to an operator: the first is a connectivity problem worth
/// surfacing, the second is simply an up-to-date device.
class RemoteUpdateResult {
  const RemoteUpdateResult(
      {this.manifest, this.unreachable = false, this.pointerReleaseId});

  /// Nothing published, or the document could not be parsed. Carries the
  /// pointer identity when one was read, so a pulled release is
  /// distinguishable from an empty backend.
  const RemoteUpdateResult.none({this.pointerReleaseId})
      : manifest = null,
        unreachable = false;

  /// The backend could not be reached.
  const RemoteUpdateResult.offline() : this(manifest: null, unreachable: true);

  final UpdateManifest? manifest;
  final bool unreachable;

  /// The release id the pointer names, when a pointer was read — even when
  /// its document turned out missing or unparseable. Lets the refresh tell
  /// "nothing published" apart from "the offered release was pulled".
  final String? pointerReleaseId;

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