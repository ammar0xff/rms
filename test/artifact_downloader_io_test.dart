import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/updates/artifact_downloader_io.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/download_state.dart';
import 'package:rms/src/domain/update/update_decision.dart';

const _decision = UpdateDecision(status: UpdateDecisionStatus.recommended);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

UpdateManifest _manifest({
  required String reference,
  required String sha256,
  required int sizeBytes,
}) =>
    UpdateManifest(
      releaseId: 'android-0.10.0-2',
      version: '0.10.0',
      buildNumber: 2,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.recommended,
      publishedAt: DateTime(2026, 10, 14),
      artifact: ReleaseArtifact(
        reference: reference,
        sizeBytes: sizeBytes,
        sha256: sha256,
      ),
    );

/// A local HTTP server standing in for the release host.
class _Host {
  _Host(this._server);

  final HttpServer _server;

  int requests = 0;
  String? authorization;
  Uri? requested;

  int get port => _server.port;

  String url(String path) => 'http://127.0.0.1:$port$path';

  Future<void> close() => _server.close(force: true);
}

Future<_Host> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final host = _Host(server);
  server.listen((request) async {
    host.requests++;
    host.authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    host.requested = request.uri;
    await handler(request);
  });
  return host;
}

/// Serves [body] with a 200.
Future<void> _ok(HttpRequest request, List<int> body) async {
  request.response
    ..statusCode = 200
    ..add(body);
  await request.response.close();
}

void main() {
  Directory? staging;
  _Host? host;

  setUp(() async {
    staging = await Directory.systemTemp.createTemp('rms_download_test');
  });

  tearDown(() async {
    // Guarded: a test that throws before standing up its host must not fail
    // again here and mask the original failure.
    await host?.close();
    final dir = staging;
    if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
  });

  // Non-null accessors; setUp has run by the time any test body executes.
  Directory _staging() => staging!;
  String _url(String path) => host!.url(path);

  HttpArtifactDownloader downloader({
    ArtifactTokenProvider? tokenProvider,
    Uri Function(String)? resolveUri,
    String bucket = 'teletunnal.firebasestorage.app',
  }) =>
      HttpArtifactDownloader(
        tokenProvider: tokenProvider,
        resolveUri: resolveUri,
        tempDirectory: () async => _staging(),
        storageBucket: bucket,
      );

  /// Subscribes before starting so no state is missed, then resolves on the
  /// first terminal one.
  Future<DownloadState> _terminal(HttpArtifactDownloader d) {
    final done = Completer<DownloadState>();
    late final StreamSubscription<DownloadState> sub;
    sub = d.progress().listen((state) {
      if (state.isTerminal && !done.isCompleted) {
        done.complete(state);
        sub.cancel();
      }
    });
    return done.future;
  }

  List<int> _payload([int length = 4096]) =>
      List<int>.generate(length, (i) => (i * 31) & 0xff);

  group('a successful download', () {
    test('completes and verifies the written artifact', () async {
      final body = _payload();
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      expect(state.stage, DownloadStage.completed);
      expect(state.error, '');
      expect(state.downloadedBytes, body.length);
      expect(state.progress, 1.0);
      expect(
        state.verification?.status,
        ArtifactVerificationStatus.verified,
      );
      expect(state.verification?.isOk, isTrue);
    });

    test('writes the artifact under the manifest build number', () async {
      final body = _payload(1024);
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      await terminal;
      addTearDown(d.dispose);

      final written = File('${_staging().path}/rms-update-2.artifact');
      expect(written.existsSync(), isTrue);
      expect(written.lengthSync(), body.length);
    });

    test('reports starting immediately, before the transfer finishes',
        () async {
      final body = _payload(2048);
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final first = await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      addTearDown(d.dispose);

      // start() hands back a starting state so the caller is unblocked; the
      // transfer runs behind it.
      expect(first.stage, DownloadStage.starting);
      expect(first.totalBytes, body.length);
    });

    test('replaces a stale artifact left by an earlier attempt', () async {
      final body = _payload(512);
      final stale = File('${_staging().path}/rms-update-2.artifact')
        ..writeAsBytesSync(List<int>.filled(999, 7));
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      await terminal;
      addTearDown(d.dispose);

      // If the stale bytes had survived, the digest could not have matched.
      expect(stale.readAsBytesSync(), body);
    });
  });

  group('fail-closed on a bad artifact', () {
    test('rejects a payload whose bytes do not match the manifest digest',
        () async {
      final published = _payload(2048);
      // Same length, one byte different — the change a tampered artifact would
      // actually carry, and the one a length check alone would miss.
      final tampered = List<int>.of(published);
      tampered[1024] ^= 0xff;
      expect(_sha(tampered), isNot(_sha(published)));

      host = await _serve((r) => _ok(r, tampered));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(published),
          sizeBytes: published.length,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      expect(state.stage, DownloadStage.failed);
      expect(
        state.verification?.status,
        ArtifactVerificationStatus.checksumMismatch,
      );
      expect(state.verification?.isOk, isFalse);
    });

    // The length disagrees with the manifest, so the checksum of a truncated
    // file can never match. Rejected without being treated as a success.
    test('rejects an incomplete download', () async {
      final body = _payload(4096);
      final short = body.sublist(0, 1000);
      host = await _serve((r) => _ok(r, short));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      expect(state.stage, DownloadStage.failed);
      expect(state.error, contains('incomplete'));
    });

    test('fails rather than succeeding when the manifest carries no digest',
        () async {
      final body = _payload(256);
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: '',
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      // Nothing to verify against must not read as "verified".
      expect(state.stage, DownloadStage.failed);
      expect(
        state.verification?.status,
        ArtifactVerificationStatus.noChecksum,
      );
    });
  });

  group('server and network failures', () {
    Future<DownloadState> _status(int code) async {
      host = await _serve((r) async {
        r.response.statusCode = code;
        await r.response.close();
      });
      final d = downloader();
      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(_payload(16)),
          sizeBytes: 16,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);
      return state;
    }

    test('reports a missing artifact', () async {
      final state = await _status(404);
      expect(state.stage, DownloadStage.failed);
      expect(state.error, contains('404'));
      expect(state.error, contains('no artifact'));
    });

    // A bare status code tells an operator nothing they can act on.
    test('explains a refusal as a permissions problem', () async {
      final state = await _status(403);
      expect(state.stage, DownloadStage.failed);
      expect(state.error, contains('not permitted'));
    });

    test('explains an expired session', () async {
      final state = await _status(401);
      expect(state.stage, DownloadStage.failed);
      expect(state.error, contains('not signed in'));
    });

    test('reports a server error without guessing at a cause', () async {
      final state = await _status(500);
      expect(state.stage, DownloadStage.failed);
      expect(state.error, contains('500'));
      expect(state.error, isNot(contains('not signed in')));
    });

    test('fails when the host cannot be reached at all', () async {
      // Nothing is listening on port 1, and the resulting socket error must
      // surface as a failed download rather than an unhandled async error.
      final d = downloader(
        resolveUri: (_) => Uri.parse('http://127.0.0.1:1/x'),
      );
      final terminal = _terminal(d);

      await d.start(
        manifest: _manifest(
          reference: 'unused',
          sha256: _sha(_payload(8)),
          sizeBytes: 8,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      expect(state.stage, DownloadStage.failed);
      expect(state.error, isNotEmpty);
    });
  });

  group('authorisation', () {
    test('sends the ID token under the Firebase scheme, not Bearer',
        () async {
      final body = _payload(128);
      host = await _serve((r) => _ok(r, body));
      final d = downloader(tokenProvider: () async => 'id-token-abc');

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      await terminal;
      addTearDown(d.dispose);

      // The Firebase Storage REST API evaluates security rules against this
      // header, and only honours the Firebase scheme.
      expect(host!.authorization, 'Firebase id-token-abc');
    });

    test('sends no header when no token provider is configured', () async {
      final body = _payload(128);
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      await terminal;
      addTearDown(d.dispose);

      expect(host!.authorization, isNull);
    });

    test('sends no header when the provider yields an empty token', () async {
      final body = _payload(128);
      host = await _serve((r) => _ok(r, body));
      final d = downloader(tokenProvider: () async => '');

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      await terminal;
      addTearDown(d.dispose);

      // An empty token must not become "Firebase ", which the backend reads as
      // a malformed credential rather than an anonymous request.
      expect(host!.authorization, isNull);
    });
  });

  group('uri resolution', () {
    UpdateManifest manifestWith(String reference) => _manifest(
          reference: reference,
          sha256: _sha(_payload(4)),
          sizeBytes: 4,
        );

    test('honours an absolute https URL as published', () {
      final d = downloader();
      final uri = d.uriFor(manifestWith('https://github.com/o/r/releases/x.apk'));
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/o/r/releases/x.apk');
    });

    test('honours an absolute http URL', () {
      final d = downloader();
      final uri = d.uriFor(manifestWith('http://example.com/a.apk'));
      expect(uri.scheme, 'http');
      expect(uri.host, 'example.com');
    });

    // Without a token there is no way to satisfy security rules, so the public
    // endpoint is the only option.
    test('uses the public bucket URL for a bare object path with no token', () {
      final d = downloader(bucket: 'my-bucket');
      final uri = d.uriFor(manifestWith('releases/app.apk'));
      expect(uri.host, 'storage.googleapis.com');
      expect(uri.path, '/my-bucket/releases/app.apk');
      expect(uri.query, isEmpty);
    });

    test('uses the rules-evaluating endpoint when a token is available', () {
      final d = downloader(
        tokenProvider: () async => 't',
        bucket: 'my-bucket',
      );
      final uri = d.uriFor(manifestWith('releases/app.apk'));

      // This is what keeps the bucket private while an authenticated device
      // can still fetch a release.
      expect(uri.host, 'firebasestorage.googleapis.com');
      expect(uri.path, '/v0/b/my-bucket/o/releases%2Fapp.apk');
      expect(uri.queryParameters['alt'], 'media');
    });

    test('a supplied resolver wins over every default rule', () {
      final d = downloader(
        tokenProvider: () async => 't',
        resolveUri: (reference) => Uri.parse('https://mirror.example/$reference'),
      );
      expect(
        d.uriFor(manifestWith('releases/app.apk')).host,
        'mirror.example',
      );
    });

    // An absolute URL is what the release workflow writes; the token header is
    // still sent, because GitHub Releases ignores it rather than rejecting it.
    test('an absolute URL is preferred over the storage endpoints', () {
      final d = downloader(tokenProvider: () async => 't');
      final uri = d.uriFor(manifestWith('https://example.com/direct.apk'));
      expect(uri.host, 'example.com');
    });
  });

  group('cancellation', () {
    test('never yields a completed, verified artifact', () async {
      // Send some bytes, then stall, so the transfer is still in flight when
      // cancel() lands.
      final body = _payload(64 * 1024);
      host = await _serve((r) async {
        r.response.statusCode = 200;
        r.response.add(body.sublist(0, 1024));
        await r.response.flush();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      final d = downloader();
      final seen = <DownloadState>[];
      final watcher = d.progress().listen(seen.add);
      addTearDown(watcher.cancel);
      addTearDown(d.dispose);

      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      // cancel() must not block. It closes the client without forcing, so the
      // in-flight response keeps being drained afterwards and may emit states
      // later — which is why this waits a bounded window rather than for a
      // terminal state that may never arrive at all.
      await d.cancel().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 3));

      // The property worth pinning: no path through a cancelled transfer
      // produces a success the installer would act on.
      expect(
        seen.where((s) => s.stage == DownloadStage.completed),
        isEmpty,
        reason: 'a cancelled download reported success',
      );
      expect(
        seen.where((s) => s.verification?.isOk == true),
        isEmpty,
        reason: 'a cancelled download produced a verified artifact',
      );
    });

    // The partial file is removed on the cancelled path. Where cancellation
    // surfaces as a socket error instead, the leftover is cleared by the next
    // attempt, which deletes any existing artifact before writing.
    test('a later attempt clears whatever an earlier one left behind', () async {
      final body = _payload(2048);
      final stale = File('${_staging().path}/rms-update-2.artifact')
        ..writeAsBytesSync(List<int>.filled(999, 7));
      host = await _serve((r) => _ok(r, body));
      final d = downloader();

      final terminal = _terminal(d);
      await d.start(
        manifest: _manifest(
          reference: _url('/app.apk'),
          sha256: _sha(body),
          sizeBytes: body.length,
        ),
        decision: _decision,
      );
      final state = await terminal;
      addTearDown(d.dispose);

      expect(state.stage, DownloadStage.completed);
      expect(stale.readAsBytesSync(), body);
    });
  });
}
