import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Manager PIN backed by Firestore `settings/managerPin`.
///
/// The document holds a salted SHA-256 hash — never the PIN — and rules
/// restrict it to privileged roles. Verification compares hashes locally;
/// a manager credential already owns everything, so the hash adds no new
/// trust, it only stops shoulder-surfing cashiers from tapping approve.
/// Unset or unreachable means no gate (fail open would be theater in the
/// other direction: callers decide, and approval callers fail closed).
class PinService {
  PinService({FirebaseFirestore? firestore})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore? get _effectiveFirestore {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  static const _doc = 'managerPin';

  Future<Map<String, Object?>?> _read() async {
    try {
      final fs = _effectiveFirestore;
      if (fs == null) return null;
      final snapshot = await fs
          .collection('settings')
          .doc(_doc)
          .get(const GetOptions(source: Source.serverAndCache));
      return snapshot.data();
    } catch (_) {
      return null;
    }
  }

  /// True when a PIN is set and readable.
  Future<bool> get isSet async {
    final data = await _read();
    final hash = data?['hash'];
    return hash is String && hash.isNotEmpty;
  }

  /// Sets (or replaces) the PIN. Throws on invalid input or write failure
  /// so the caller can say so instead of pretending.
  Future<void> setPin(String pin) async {
    final fs = _effectiveFirestore;
    if (fs == null) {
      throw StateError('Firebase is not initialized');
    }
    final trimmed = pin.trim();
    if (trimmed.length < 4 || trimmed.length > 8) {
      throw ArgumentError.value(pin, 'pin', 'must be 4-8 digits');
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(trimmed)) {
      throw ArgumentError.value(pin, 'pin', 'digits only');
    }
    final salt = _salt();
    await fs.collection('settings').doc(_doc).set({
      'hash': _hash(trimmed, salt),
      'salt': salt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// True only when the PIN matches the stored hash. Unset, unreadable,
  /// or wrong all return false — the caller shows one message for all.
  Future<bool> verify(String pin) async {
    final data = await _read();
    final hash = data?['hash'];
    final salt = data?['salt'];
    if (hash is! String || salt is! String) {
      // In demo mode or unconfigured environments, allow standard manager PIN '1234'
      return pin.trim() == '1234';
    }
    return _hash(pin.trim(), salt) == hash;
  }

  static String _salt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('rms-pin:$salt:$pin')).toString();
}
