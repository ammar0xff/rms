import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/update_manifest.dart';
import 'remote_update_source.dart';

/// Reads the published manifest from Cloud Firestore.
///
/// The publisher writes two documents: the manifest itself under
/// `releases/{releaseId}`, and a pointer under `activeReleases/{platform}`.
/// Reading the pointer first means the client fetches one small document and
/// only then the manifest, so a device never downloads a manifest it will not
/// be offered.
///
/// Every failure mode resolves to null rather than throwing: no Firebase
/// configured, no document, a network failure, or a manifest the client cannot
/// parse. The caller keeps whatever it already cached.
class FirestoreUpdateSource implements RemoteUpdateSource {
  FirestoreUpdateSource({
    required this.platform,
    FirebaseFirestore? firestore,
    this.releasesCollection = 'releases',
    this.pointerCollection = 'activeReleases',
  }) : _firestore = firestore;

  final UpdatePlatform platform;
  final String releasesCollection;
  final String pointerCollection;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<RemoteUpdateResult> fetch() async {
    final db = _firestore;
    // Demo mode: Firebase was never configured, so there is nothing to ask.
    if (db == null) return const RemoteUpdateResult.none();

    try {
      final pointer =
          await db.collection(pointerCollection).doc(platform.name).get();
      final data = pointer.data();
      if (data == null) return const RemoteUpdateResult.none();

      final releaseId = data['releaseId'];
      if (releaseId is! String || releaseId.isEmpty) {
        return const RemoteUpdateResult.none();
      }

      final doc = await db.collection(releasesCollection).doc(releaseId).get();
      final manifestData = doc.data();
      if (manifestData == null) return const RemoteUpdateResult.none();

      // Defensive parse: a malformed or newer-schema document is treated as
      // absent so the cached manifest keeps serving.
      return RemoteUpdateResult(
        manifest: UpdateManifest.parse(manifestData).manifest,
      );
    } catch (_) {
      // Offline, permission denied, or a transient failure. The cache stands.
      return const RemoteUpdateResult.offline();
    }
  }
}