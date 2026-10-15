import 'dart:async';

import 'package:http/http.dart' as http;

/// Fetches a URL body for GitHub release tracking, on every platform.
///
/// `package:http` rides `dart:io` on mobile/desktop and browser fetch on web,
/// so one implementation serves all three — no conditional imports. The web
/// app only ever fetches the release listing (version and notes live there);
/// api.github.com allows that cross-origin. Asset bytes stay mobile/desktop,
/// where the artifact downloader (already `dart:io`) handles them.
///
/// Unauthenticated API calls are limited to 60 per hour per IP: the listing
/// is fetched once per check, and asset downloads bypass the quota.
Future<String> fetchGitHubReleaseBody(Uri url) async {
  final response = await http
      .get(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'rms-updater',
        },
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw StateError('GitHub API answered HTTP ${response.statusCode}');
  }
  return response.body;
}
