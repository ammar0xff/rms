import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fetches a URL body over HTTPS with bounded waits.
///
/// Unauthenticated GitHub API calls are limited to 60 per hour per IP, so this
/// is called sparingly: once per update check for the release list, plus once
/// per manifest download. Asset downloads bypass the API quota (they redirect
/// to object storage), which is why only the listing counts.
Future<String> fetchGitHubReleaseBody(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(url);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'rms-updater');
    final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
    if (response.statusCode != 200) {
      throw StateError('GitHub API answered HTTP ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join().timeout(
          const Duration(seconds: 30),
        );
  } finally {
    client.close();
  }
}
