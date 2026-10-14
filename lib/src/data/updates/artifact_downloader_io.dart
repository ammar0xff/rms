import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/update_manifest.dart';
import '../../domain/update/artifact_verifier.dart';
import '../../domain/update/download_state.dart';
import '../../domain/update/update_decision.dart';
import 'artifact_paths.dart';

/// Supplies the Firebase ID token that authorises a download.
///
/// Returning null falls back to an unauthenticated fetch, which a private
/// bucket rejects.
typedef ArtifactTokenProvider = Future<String?> Function();

/// Downloads a release artifact over HTTP and verifies its checksum.
///
/// [ArtifactDownloader.start] returns immediately with a `starting` state; the
/// transfer runs in the background and reports through [progress]. The download
/// is only ever handed to an installer after [ArtifactVerifier] confirms the
/// SHA-256, so a truncated or tampered payload is rejected before it can run.
///
/// When a [tokenProvider] is supplied the artifact is fetched through the
/// Firebase Storage REST API, where security rules are enforced. That keeps the
/// bucket private while still letting an authenticated device fetch a release.
/// With no provider it falls back to the public Cloud Storage URL, which only
/// works when the bucket is public.
///
/// Web is excluded: artifact delivery is mobile and desktop only, and `dart:io`
/// is unavailable there. The conditional import in `artifact_downloader.dart`
/// resolves the stub on that platform instead.
class HttpArtifactDownloader implements ArtifactDownloader {
  HttpArtifactDownloader({
    HttpClient? client,
    this.resolveUri,
    this.tokenProvider,
    this.storageBucket = 'teletunnal.firebasestorage.app',
  }) : _client = client ?? HttpClient();

  /// Turns the manifest's artifact reference into a fetchable URI.
  final Uri Function(String reference)? resolveUri;

  /// Authorises the download. Null means an unauthenticated fetch.
  final ArtifactTokenProvider? tokenProvider;

  /// Bucket used by the default resolvers.
  final String storageBucket;

  final StreamController<DownloadState> _controller =
      StreamController<DownloadState>.broadcast();

  HttpClient? _client;
  bool _cancelled = false;

  @override
  Stream<DownloadState> progress() => _controller.stream;

  /// The Firebase Storage REST download URL.
  ///
  /// Unlike the plain `storage.googleapis.com` form, this endpoint evaluates
  /// Cloud Storage security rules against the supplied ID token, which is what
  /// lets the bucket stay private. `alt=media` returns the bytes rather than
  /// object metadata.
  Uri _authenticatedUri(String reference) {
    final encoded = Uri.encodeComponent(reference);
    return Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o/$encoded'
      '?alt=media',
    );
  }

  Uri _uriFor(UpdateManifest manifest) {
    final resolve = resolveUri;
    if (resolve != null) return resolve(manifest.artifact.reference);
    final reference = manifest.artifact.reference;

    // A published release carries an absolute download URL, which is what the
    // release workflow writes. Honour it as-is.
    if (reference.startsWith('http://') || reference.startsWith('https://')) {
      return Uri.parse(reference);
    }

    // Otherwise treat it as a Cloud Storage object path. With a token the
    // authenticated endpoint is used, which evaluates security rules; without
    // one the plain public URL, which only works on a public bucket.
    if (tokenProvider != null) return _authenticatedUri(reference);
    return Uri.parse('https://storage.googleapis.com/$storageBucket/$reference');
  }

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async {
    _cancelled = false;
    final total = manifest.artifact.sizeBytes;
    final started = DateTime.now();
    final initial = DownloadState(
      stage: DownloadStage.starting,
      totalBytes: total,
      startedAt: started,
    );
    _controller.add(initial);
    // Deliberately not awaited: the caller observes progress via [progress].
    unawaited(_run(manifest));
    return initial;
  }

  Future<void> _run(UpdateManifest manifest) async {
    final total = manifest.artifact.sizeBytes;
    IOSink? sink;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, artifactFileName(manifest)));
      if (await file.exists()) await file.delete();

      _emit(
        DownloadState(
          stage: DownloadStage.downloading,
          totalBytes: total,
          startedAt: DateTime.now(),
        ),
      );

      final request = await _client!.getUrl(_uriFor(manifest));
      final token = await tokenProvider?.call();
      if (token != null && token.isNotEmpty) {
        // The Firebase Storage REST API expects the ID token under the
        // `Firebase` scheme, not `Bearer`, and evaluates security rules
        // against it.
        request.headers.set(HttpHeaders.authorizationHeader, 'Firebase $token');
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        // 401/403 here almost always means the session is missing, expired, or
        // not entitled by the bucket rules — worth saying plainly rather than
        // leaving the operator with a bare status code.
        final hint = switch (response.statusCode) {
          401 || 403 => ' (not signed in, or not permitted to read this release)',
          404 => ' (no artifact at the published path)',
          _ => '',
        };
        _fail('HTTP ${response.statusCode}$hint', total);
        return;
      }

      final out = file.openWrite();
      sink = out;
      var received = 0;
      var lastSecond = DateTime.now();
      var lastBytes = 0;

      await for (final chunk in response) {
        if (_cancelled) {
          await out.close();
          sink = null;
          await _discard(file);
          _emit(
            DownloadState(
              stage: DownloadStage.cancelled,
              totalBytes: total,
              downloadedBytes: received,
              endedAt: DateTime.now(),
            ),
          );
          return;
        }
        out.add(chunk);
        received += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastSecond).inMilliseconds >= 500) {
          final rate = (received - lastBytes) * 1000 ~/
              now.difference(lastSecond).inMilliseconds;
          _emit(
            DownloadState(
              stage: DownloadStage.downloading,
              totalBytes: total,
              downloadedBytes: received,
              bytesPerSecond: rate,
              progress: total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0,
            ),
          );
          lastSecond = now;
          lastBytes = received;
        }
      }

      await out.close();
      sink = null;

      _emit(
        DownloadState(
          stage: DownloadStage.verifying,
          totalBytes: total,
          downloadedBytes: received,
          progress: 1.0,
        ),
      );

      final verification = await ArtifactVerifier.verify(
        manifest: manifest,
        path: file.path,
      );

      // A payload whose length does not match the manifest is rejected without
      // hashing it: the checksum of a truncated file can never match, and the
      // download is wasted work.
      final truncated = received != total && total > 0;
      final ok = verification.isOk && !truncated;

      _emit(
        DownloadState(
          stage: ok ? DownloadStage.completed : DownloadStage.failed,
          totalBytes: total,
          downloadedBytes: received,
          progress: ok ? 1.0 : 0.0,
          verification: verification,
          error: ok ? '' : truncated ? 'incomplete download' : verification.status.name,
          endedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // The partial file is removed below; a close failure here is noise.
        }
      }
      _fail('$error', total);
    }
  }

  Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover temp file is harmless; the next run overwrites it.
    }
  }

  void _fail(String message, int total) {
    _emit(
      DownloadState(
        stage: DownloadStage.failed,
        totalBytes: total,
        error: message,
        endedAt: DateTime.now(),
      ),
    );
  }

  void _emit(DownloadState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  void dispose() {
    _controller.close();
    _client?.close();
    _client = null;
  }
}