/// Fetches a URL body for GitHub release tracking.
///
/// Resolved per platform (see `github_fetcher.dart`): `dart:io` on mobile and
/// desktop, an explicit failure on web — where artifact delivery is skipped
/// entirely, so this is never called.
export 'github_fetcher_stub.dart'
    if (dart.library.io) 'github_fetcher_io.dart';
