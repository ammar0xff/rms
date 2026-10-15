import 'dart:convert';

import '../../domain/models/update_manifest.dart';
import 'github_fetcher.dart';
import 'remote_update_source.dart';

/// Fetches a URL body and returns it as text. Injected so the release
/// selection rules — the part worth testing — run against canned responses
/// instead of the network.
typedef GitHubReleaseFetcher = Future<String> Function(Uri url);

/// Reads the published manifest from GitHub Releases instead of Firestore.
///
/// The release workflow attaches a `manifest.<platform>.json` asset to every
/// release (same shape as the old Firestore document). This source walks the
/// release list newest-first and takes the first readable manifest for this
/// platform on our channel, so one source serves every platform without any
/// per-platform backend state.
///
/// Every failure resolves the same way the Firestore source did: unreachable
/// backend reads as offline and the cache keeps standing. Rate limits,
/// malformed JSON, missing assets and wrong channels all land there too — a
/// tracking failure must never clear a good cache or crash a check.
class GitHubReleaseSource implements RemoteUpdateSource {
  GitHubReleaseSource({
    required this.platform,
    required this.channel,
    this.fetcher = fetchGitHubReleaseBody,
    this.owner = 'ammar0xff',
    this.repo = 'rms',
    this.maxReleases = 10,
  });

  final UpdatePlatform platform;
  final UpdateChannel channel;
  final GitHubReleaseFetcher fetcher;
  final String owner;
  final String repo;

  /// How many releases back to look for a usable manifest. Ten is plenty: a
  /// manifest goes missing only when a publish misfires, and walking forever
  /// would turn one bad release into unbounded API calls.
  final int maxReleases;

  String get _manifestAssetName => 'manifest.${platform.name}.json';

  Uri get _releasesUri => Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/releases',
        {'per_page': '$maxReleases'},
      );

  /// Production tracks stable releases; every other channel tracks
  /// prereleases. The manifest itself carries a channel the decision engine
  /// checks again, so this is a pre-filter, not the gate.
  bool _servesChannel(bool prerelease) =>
      channel == UpdateChannel.production ? !prerelease : prerelease;

  @override
  Future<RemoteUpdateResult> fetch() async {
    try {
      final listing = jsonDecode(await fetcher(_releasesUri));
      if (listing is! List) return const RemoteUpdateResult.none();
      for (final item in listing) {
        if (item is! Map<String, dynamic>) continue;
        if (item['draft'] == true) continue;
        if (!_servesChannel(item['prerelease'] == true)) continue;
        final manifestUrl = _manifestUrl(item);
        if (manifestUrl == null) continue;
        final manifest = await _readManifest(manifestUrl);
        if (manifest == null) continue;
        return RemoteUpdateResult(manifest: manifest);
      }
      return const RemoteUpdateResult.none();
    } catch (_) {
      return const RemoteUpdateResult.offline();
    }
  }

  String? _manifestUrl(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      if (asset['name'] != _manifestAssetName) continue;
      final url = asset['browser_download_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  Future<UpdateManifest?> _readManifest(String url) async {
    try {
      final body = await fetcher(Uri.parse(url));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      return UpdateManifest.parse(decoded).manifest;
    } catch (_) {
      return null;
    }
  }
}
