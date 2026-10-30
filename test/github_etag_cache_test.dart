import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rms/src/data/updates/github_fetcher.dart';

void main() {
  group('fetchGitHubReleaseBody ETag Caching', () {
    setUp(() {
      clearGitHubETagCache();
    });

    test('caches ETag from 200 response and serves cached body on 304 Not Modified', () async {
      final testUri = Uri.parse('https://api.github.com/repos/test/rms/releases');
      int callCount = 0;
      String? sentIfNoneMatch;

      final mockClient = MockClient((request) async {
        callCount++;
        sentIfNoneMatch = request.headers['If-None-Match'];

        if (callCount == 1) {
          return http.Response(
            '{"tag_name": "v1.0.0"}',
            200,
            headers: {'etag': 'W/"etag-v1"'},
          );
        } else {
          expect(sentIfNoneMatch, 'W/"etag-v1"');
          return http.Response('', 304);
        }
      });

      // 1. First fetch: receives 200 with ETag
      final firstBody = await fetchGitHubReleaseBody(testUri, client: mockClient);
      expect(firstBody, '{"tag_name": "v1.0.0"}');
      expect(callCount, 1);
      expect(sentIfNoneMatch, isNull);

      // 2. Second fetch: sends ETag, gets 304, returns cached body without re-parsing
      final secondBody = await fetchGitHubReleaseBody(testUri, client: mockClient);
      expect(secondBody, '{"tag_name": "v1.0.0"}');
      expect(callCount, 2);
      expect(sentIfNoneMatch, 'W/"etag-v1"');
    });

    test('replaces cached body when new 200 response arrives', () async {
      final testUri = Uri.parse('https://api.github.com/repos/test/rms/releases');
      int callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            '{"tag_name": "v1.0.0"}',
            200,
            headers: {'etag': '"tag1"'},
          );
        } else {
          return http.Response(
            '{"tag_name": "v2.0.0"}',
            200,
            headers: {'etag': '"tag2"'},
          );
        }
      });

      final first = await fetchGitHubReleaseBody(testUri, client: mockClient);
      expect(first, '{"tag_name": "v1.0.0"}');

      final second = await fetchGitHubReleaseBody(testUri, client: mockClient);
      expect(second, '{"tag_name": "v2.0.0"}');
    });
  });
}
