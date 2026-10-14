import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/update_manifest.dart';
import 'remote_update_source.dart';

/// Reads a document by collection and id, returning its fields or null when it
/// does not exist.
///
/// The platform seam for this source. Firestore cannot be constructed in a unit
/// test, and the resolution rules — pointer first, then manifest, never throw —
/// are the part worth checking, so they run against this instead.
typedef ManifestDocumentReader = Future<Map<String, dynamic>?> Function(
  String collection,
  String documentId,
);

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
    this.readDocuments,
    this.releasesCollection = 'releases',
    this.pointerCollection = 'activeReleases',
  }) : _firestore = firestore;

  final UpdatePlatform platform;
  final String releasesCollection;
  final String pointerCollection;

  final FirebaseFirestore? _firestore;

  /// Overrides the Firestore transport entirely. Supplied by tests; production
  /// leaves it null and the instance goes to Firestore directly.
  final ManifestDocumentReader? readDocuments;

  @override
  Future<RemoteUpdateResult> fetch() async {
    final db = _firestore;
    // Demo mode: Firebase was never configured, so there is nothing to ask.
    if (db == null && readDocuments == null) return const RemoteUpdateResult.none();

    final reader = readDocuments ?? _firestoreReader(db!);
    return _resolve(reader);
  }

  ManifestDocumentReader _firestoreReader(FirebaseFirestore db) =>
      (collection, documentId) async =>
          (await db.collection(collection).doc(documentId).get()).data();

  Future<RemoteUpdateResult> _resolve(ManifestDocumentReader read) async {
    try {
      final pointer = await read(pointerCollection, platform.name);
      if (pointer == null) return const RemoteUpdateResult.none();

      final releaseId = pointer['releaseId'];
      if (releaseId is! String || releaseId.isEmpty) {
        return const RemoteUpdateResult.none();
      }

      final manifest = await read(releasesCollection, releaseId);
      if (manifest == null) return const RemoteUpdateResult.none();

      // Defensive parse: a malformed or newer-schema document is treated as
      // absent so the cached manifest keeps serving.
      return RemoteUpdateResult(
        manifest: UpdateManifest.parse(manifest).manifest,
      );
    } catch (_) {
      // Offline, permission denied, or a transient failure. The cache stands.
      return const RemoteUpdateResult.offline();
    }
  }
}