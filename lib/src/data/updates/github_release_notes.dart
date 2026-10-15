import 'dart:convert';

import 'github_fetcher.dart';
import 'github_release_source.dart' show GitHubReleaseFetcher;

/// The newest published release, for display only.
///
/// Unlike [GitHubReleaseSource], this reads no manifest asset and installs
/// nothing: it reports the latest tag and its notes so every platform —
/// including web, which takes no artifact updates — can show what is new next
/// to what is installed. Read-only to the point of having no failure modes
/// worth surfacing: anything that goes wrong resolves to null and the caller
/// shows nothing extra.
class GitHubReleaseNotes {
  GitHubReleaseNotes({
    this.fetcher = fetchGitHubReleaseBody,
    this.owner = 'ammar0xff',
    this.repo = 'rms',
    this.includePrereleases = false,
  });

  final GitHubReleaseFetcher fetcher;
  final String owner;
  final String repo;

  /// When false (production), prereleases are skipped.
  final bool includePrereleases;

  /// The latest release tag and notes, or null when unknowable.
  Future<ReleaseNotes?> latest() async {
    try {
      final listing = jsonDecode(
        await fetcher(Uri.https(
          'api.github.com',
          '/repos/$owner/$repo/releases',
          const {'per_page': '5'},
        )),
      );
      if (listing is! List) return null;
      for (final item in listing) {
        if (item is! Map<String, dynamic>) continue;
        if (item['draft'] == true) continue;
        if (item['prerelease'] == true && !includePrereleases) continue;
        final tag = item['tag_name'];
        if (tag is! String || tag.isEmpty) continue;
        final notes = item['body'];
        return ReleaseNotes(
          tag: tag,
          notes: notes is String ? notes.trim() : '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// A release tag with its notes, as published on the release page.
class ReleaseNotes {
  const ReleaseNotes({required this.tag, required this.notes});

  /// e.g. `v0.18.0`.
  final String tag;

  /// The release body, possibly empty.
  final String notes;

  /// The tag without a leading `v`, for comparison against
  /// [AppVersion.number]-style versions.
  String get version => tag.startsWith('v') ? tag.substring(1) : tag;
}
