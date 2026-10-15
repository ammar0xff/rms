import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/updates/github_release_notes.dart';

Map<String, dynamic> _release({
  required String tag,
  bool draft = false,
  bool prerelease = false,
  String body = 'notes here',
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': body,
    };

void main() {
  group('GitHubReleaseNotes', () {
    Future<ReleaseNotes?> latest(
      Object listing, {
      bool includePrereleases = false,
      Object? throwOn,
    }) =>
        GitHubReleaseNotes(
          fetcher: (_) async {
            if (throwOn != null) throw throwOn;
            return listing is String ? listing : jsonEncode(listing);
          },
          includePrereleases: includePrereleases,
        ).latest();

    test('reports the newest stable tag and its notes', () async {
      final notes = await latest([
        _release(tag: 'v0.18.0', body: 'Driver home.'),
      ]);

      expect(notes, isNotNull);
      expect(notes!.tag, 'v0.18.0');
      expect(notes.version, '0.18.0');
      expect(notes.notes, 'Driver home.');
    });

    test('skips drafts and prereleases by default', () async {
      final notes = await latest([
        _release(tag: 'v0.19.0-beta', prerelease: true),
        _release(tag: 'v0.19.0-draft', draft: true),
        _release(tag: 'v0.18.0'),
      ]);

      expect(notes!.tag, 'v0.18.0');
    });

    test('includes prereleases when asked', () async {
      final notes = await latest(
        [
          _release(tag: 'v0.19.0-beta', prerelease: true),
          _release(tag: 'v0.18.0'),
        ],
        includePrereleases: true,
      );

      expect(notes!.tag, 'v0.19.0-beta');
    });

    test('trims the notes and tolerates a missing body', () async {
      final notes = await latest([
        {'tag_name': 'v1', 'draft': false, 'prerelease': false},
      ]);

      expect(notes!.notes, '');
    });

    test('resolves to null when unreachable', () async {
      expect(await latest([], throwOn: StateError('no route')), isNull);
    });

    test('resolves to null on malformed listings', () async {
      expect(await latest('garbage {{{'), isNull);
      expect(await latest([]), isNull);
      expect(await latest([{'nope': true}]), isNull);
    });

    test('version strips one leading v', () async {
      const notes = ReleaseNotes(tag: 'v0.18.0', notes: '');
      expect(notes.version, '0.18.0');
      expect(
        const ReleaseNotes(tag: '0.18.0', notes: '').version,
        '0.18.0',
      );
    });
  });
}
