import 'dart:async';

import 'package:http/http.dart' as http;

class _CachedGitHubResponse {
  const _CachedGitHubResponse({required this.etag, required this.body});
  final String etag;
  final String body;
}

/// In-memory ETag cache for GitHub API requests to avoid rate limits (60 requests/hr).
final Map<String, _CachedGitHubResponse> _gitHubETagCache = {};

/// Clears the in-memory ETag cache. Visible for testing.
void clearGitHubETagCache() => _gitHubETagCache.clear();

/// Fetches a URL body for GitHub release tracking, on every platform.
///
/// `package:http` rides `dart:io` on mobile/desktop and browser fetch on web,
/// so one implementation serves all three — no conditional imports. The web
/// app only ever fetches the release listing (version and notes live there);
/// api.github.com allows that cross-origin. Asset bytes stay mobile/desktop,
/// where the artifact downloader (already `dart:io`) handles them.
///
/// Supports conditional HTTP requests with `If-None-Match` and GitHub ETags,
/// returning cached content on HTTP 304 Not Modified without exhausting the
/// 60 req/hr unauthenticated rate limit.
Future<String> fetchGitHubReleaseBody(Uri url, {http.Client? client}) async {
  final urlKey = url.toString();
  final cached = _gitHubETagCache[urlKey];

  final headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'rms-updater',
    if (cached != null && cached.etag.isNotEmpty) 'If-None-Match': cached.etag,
  };

  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 304 && cached != null) {
      return cached.body;
    }

    if (response.statusCode != 200) {
      throw StateError('GitHub API answered HTTP ${response.statusCode}');
    }

    final etag = response.headers['etag'];
    if (etag != null && etag.isNotEmpty) {
      _gitHubETagCache[urlKey] = _CachedGitHubResponse(
        etag: etag,
        body: response.body,
      );
    }

    return response.body;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
