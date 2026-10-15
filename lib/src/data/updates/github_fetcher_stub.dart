/// Web has no artifact delivery, so release tracking never runs there and no
/// HTTP client is needed. Anything calling this on web is a wiring bug, and
/// failing loudly is better than failing as "offline" (which would look like
/// a network problem and hide the real cause).
Future<String> fetchGitHubReleaseBody(Uri url) =>
    throw UnsupportedError('GitHub release tracking needs dart:io');
