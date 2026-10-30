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

  static int _failedAttempts = 0;
  static DateTime? _lockedUntil;

  /// True when the PIN gate is temporarily locked out due to repeated failed attempts.
  static bool get isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  /// Remaining lockout duration, or null if not currently locked.
  static Duration? get remainingLockout {
    final locked = _lockedUntil;
    if (locked == null) return null;
    final diff = locked.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  static String? _testPin;

  /// Injects a test PIN for automated UI test harnesses where Firestore is unconfigured.
  static void setTestPin(String? pin) {
    _testPin = pin;
  }

  /// Reset lockout state (for unit testing and developer diagnostics).
  static void resetLockoutForTesting() {
    _failedAttempts = 0;
    _lockedUntil = null;
    _testPin = null;
    _activeDelegationCode = null;
    _delegationCodeExpiresAt = null;
  }

  static String? _activeDelegationCode;
  static DateTime? _delegationCodeExpiresAt;

  /// Generates a random supervisor delegation code with a 1-hour expiry.
  static String generateDelegationCode({Duration ttl = const Duration(hours: 1)}) {
    final rand = Random.secure().nextInt(9000) + 1000;
    final code = 'DEL-$rand';
    _activeDelegationCode = code;
    _delegationCodeExpiresAt = DateTime.now().add(ttl);
    return code;
  }

  /// Verifies and consumes a delegation code (single-use, time-bounded).
  /// Accepts either the full code ('DEL-1234') or the 4 digits ('1234').
  static bool verifyDelegationCode(String code) {
    if (_activeDelegationCode == null || _delegationCodeExpiresAt == null) {
      return false;
    }
    if (DateTime.now().isAfter(_delegationCodeExpiresAt!)) {
      _activeDelegationCode = null;
      _delegationCodeExpiresAt = null;
      return false;
    }
    final clean = code.trim().toUpperCase();
    final active = _activeDelegationCode!;
    final digitsOnly = active.replaceFirst('DEL-', '');

    final matches = clean == active || clean == digitsOnly;
    if (matches) {
      _activeDelegationCode = null;
      _delegationCodeExpiresAt = null;
      _failedAttempts = 0;
      _lockedUntil = null;
      return true;
    }
    return false;
  }

  static void _recordFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
    } else if (_failedAttempts >= 3) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  /// True only when the PIN matches the stored hash. Unset, unreadable,
  /// locked out, or wrong all return false — failing closed by design.
  Future<bool> verify(String pin) async {
    if (isLocked) {
      return false;
    }

    if (_testPin != null) {
      final matches = pin.trim() == _testPin;
      if (matches) {
        _failedAttempts = 0;
        _lockedUntil = null;
        return true;
      } else {
        _recordFailedAttempt();
        return false;
      }
    }

    final data = await _read();
    final hash = data?['hash'];
    final salt = data?['salt'];
    if (hash is! String || salt is! String || hash.isEmpty || salt.isEmpty) {
      // Security fix (SEC-002): Fail closed. Unconfigured or unreachable backend
      // must NEVER allow hardcoded fallback '1234'.
      _recordFailedAttempt();
      return false;
    }

    final matches = _hash(pin.trim(), salt) == hash;
    if (matches) {
      _failedAttempts = 0;
      _lockedUntil = null;
      return true;
    } else {
      _recordFailedAttempt();
      return false;
    }
  }

  static String _salt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('rms-pin:$salt:$pin')).toString();
}
