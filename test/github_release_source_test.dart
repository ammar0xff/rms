import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/updates/github_release_source.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _manifestJson({
  String releaseId = 'android-0.14.0-9',
  String version = '0.14.0',
  int buildNumber = 9,
  String platform = 'android',
  String channel = 'production',
  String status = 'active',
  String severity = 'recommended',
}) =>
    {
      'releaseId': releaseId,
      'version': version,
      'buildNumber': buildNumber,
      'platform': platform,
      'architecture': '',
      'channel': channel,
      'status': status,
      'rolloutPercent': 100,
      'severity': severity,
      'publishedAt': '2026-10-15T08:00:00.000Z',
      'artifact': {
        'reference':
            'https://github.com/ammar0xff/rms/releases/download/v0.14.0/app-release.apk',
        'sizeBytes': 1024,
        'sha256': _sha,
        'signature': '',
        'expiresAt': null,
      },
      'minSupportedVersion': '0.0.0',
      'minBackendVersion': null,
      'maxBackendVersion': null,
      'localSchemaMin': null,
      'localSchemaMax': null,
      'requiredMigrationVersion': null,
      'releaseNotes': '',
      'expiresAt': null,
      'forceAfter': null,
      'rollbackTargetVersion': null,
      'targetBranchIds': [],
      'targetDeviceGroups': [],
      'manifestSchemaVersion': 1,
    };

Map<String, dynamic> _release({
  required String tag,
  bool draft = false,
  bool prerelease = false,
  Map<String, String> manifestAssets = const {},
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final entry in manifestAssets.entries)
          {'name': entry.key, 'browser_download_url': entry.value},
      ],
    };

/// Serves canned bodies keyed by URL.
class _Fetcher {
  _Fetcher(this.bodies);

  final Map<String, String> bodies;
  final List<Uri> requested = [];
  Object? throwOn;

  Future<String> call(Uri url) async {
    requested.add(url);
    final error = throwOn;
    if (error != null) throw error;
    final body = bodies[url.toString()];
    if (body == null) throw StateError('no canned body for $url');
    return body;
  }
}

const _manifestUrl = 'https://example.com/manifest.android.json';

GitHubReleaseSource _source(
  _Fetcher fetcher, {
  UpdatePlatform platform = UpdatePlatform.android,
  UpdateChannel channel = UpdateChannel.production,
}) =>
    GitHubReleaseSource(
      platform: platform,
      channel: channel,
      fetcher: fetcher.call,
    );

void main() {
  group('GitHubReleaseSource', () {
    test('takes the newest stable manifest for this platform', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': _manifestUrl,
          }),
        ]),
        _manifestUrl: jsonEncode(_manifestJson()),
      });

      final result = await _source(fetcher).fetch();

      expect(result.isUsable, isTrue);
      expect(result.manifest!.version, '0.14.0');
      expect(result.manifest!.buildNumber, 9);
      expect(result.manifest!.artifact.sha256, _sha);
    });

    test('skips drafts and prereleases when tracking production', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(
              tag: 'v0.15.0-beta',
              prerelease: true,
              manifestAssets: {'manifest.android.json': _manifestUrl}),
          _release(tag: 'v0.15.0-draft', draft: true),
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': _manifestUrl,
          }),
        ]),
        _manifestUrl: jsonEncode(_manifestJson()),
      });

      final result = await _source(fetcher).fetch();

      expect(result.manifest!.version, '0.14.0');
    });

    test('skips releases without this platform manifest', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(tag: 'v0.15.0', manifestAssets: {
            'manifest.windows.json': 'https://example.com/manifest.windows.json',
          }),
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': _manifestUrl,
          }),
        ]),
        _manifestUrl: jsonEncode(_manifestJson()),
      });

      final result = await _source(fetcher).fetch();

      expect(result.manifest!.version, '0.14.0');
    });

    test('skips a malformed manifest and takes the older readable one',
        () async {
      const badUrl = 'https://example.com/bad.json';
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(tag: 'v0.15.0', manifestAssets: {
            'manifest.android.json': badUrl,
          }),
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': _manifestUrl,
          }),
        ]),
        badUrl: jsonEncode({'version': 'oops'}),
        _manifestUrl: jsonEncode(_manifestJson()),
      });

      final result = await _source(fetcher).fetch();

      expect(result.manifest!.version, '0.14.0');
    });

    test('reports nothing when no release serves this platform', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(tag: 'v0.15.0'),
        ]),
      });

      final result = await _source(fetcher).fetch();

      expect(result.isUsable, isFalse);
      // Absent is not unreachable: the cache keeps standing either way, but
      // the two mean different things upstream.
      expect(result.unreachable, isFalse);
    });

    test('reports offline when the API cannot be reached', () async {
      final fetcher = _Fetcher({})..throwOn = StateError('no route');
      final result = await _source(fetcher).fetch();

      expect(result.isUsable, isFalse);
      expect(result.unreachable, isTrue);
    });

    test('reports offline on a malformed listing', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            'not json at all {{{',
      });

      final result = await _source(fetcher).fetch();

      // jsonDecode throws inside the guarded region: offline, cache stands.
      expect(result.isUsable, isFalse);
      expect(result.unreachable, isTrue);
    });

    // Withdrawal travels as an explicit revoked manifest, which the decision
    // engine already renders ineligible. The source passes it through rather
    // than hiding it.
    test('passes a revoked manifest through for the decision engine',
        () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': _manifestUrl,
          }),
        ]),
        _manifestUrl: jsonEncode(_manifestJson(status: 'revoked')),
      });

      final result = await _source(fetcher).fetch();

      expect(result.isUsable, isTrue);
      expect(result.manifest!.status, ReleaseStatus.revoked);
    });

    test('a beta channel tracks prereleases', () async {
      final fetcher = _Fetcher({
        'https://api.github.com/repos/ammar0xff/rms/releases?per_page=10':
            jsonEncode([
          _release(
              tag: 'v0.15.0-beta',
              prerelease: true,
              manifestAssets: {'manifest.android.json': _manifestUrl}),
          _release(tag: 'v0.14.0', manifestAssets: {
            'manifest.android.json': 'https://example.com/stable.json',
          }),
        ]),
        _manifestUrl: jsonEncode(_manifestJson(
          version: '0.15.0',
          releaseId: 'android-0.15.0-10',
          buildNumber: 10,
          channel: 'beta',
        )),
      });

      final result = await _source(fetcher, channel: UpdateChannel.beta).fetch();

      expect(result.manifest!.version, '0.15.0');
    });
  });
}
