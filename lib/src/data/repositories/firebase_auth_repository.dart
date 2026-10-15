import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/app_role.dart';
import '../../domain/models/app_user.dart';
import 'auth_repository.dart';

/// A failure reported by the auth backend, carrying its code.
///
/// The codes are Firebase's own vocabulary. The repository translates them into
/// something an operator can act on, so the raw code stops here.
class AuthBackendFailure implements Exception {
  const AuthBackendFailure(this.code);

  final String code;

  @override
  String toString() => 'AuthBackendFailure($code)';
}

/// The auth operations this repository needs, in domain terms.
///
/// `FirebaseAuth` cannot be constructed without a configured Firebase app, so
/// the calls are narrowed behind this interface. That is what makes the error
/// mapping, the email trimming, and the guards testable without a live project —
/// none of which were reachable before, because `FirebaseAuthRepository` had
/// zero tests.
abstract interface class AuthBackend {
  AppUser? get currentUser;
  Stream<AppUser?> authStateChanges();
  Future<AppUser?> signIn({required String email, required String password});
  Future<void> signOut();
}

/// Wraps [FirebaseAuth], translating its exceptions into [AuthBackendFailure].
class _FirebaseAuthBackend implements AuthBackend {
  _FirebaseAuthBackend(FirebaseAuth auth) : _auth = auth;

  final FirebaseAuth _auth;

  /// Last resolved role per uid. The synchronous mapping reads through here
  /// so `currentUser` carries the role once known, instead of permanently
  /// reporting the cashier default to UI gates.
  final Map<String, AppRole> roles = {};

  AppUser? _map(User user) => AppUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        role: roles[user.uid] ?? AppRole.cashier,
      );

  @override
  AppUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _map(user);
  }

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map((user) => user == null ? null : _map(user));

  @override
  Future<AppUser?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      return user == null ? null : _map(user);
    } on FirebaseAuthException catch (e) {
      throw AuthBackendFailure(e.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Backend-backed authentication using Firebase Auth (email/password).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
      {FirebaseAuth? auth, AuthBackend? backend, FirebaseFirestore? firestore})
      : _backend = backend ?? _FirebaseAuthBackend(auth ?? FirebaseAuth.instance),
        _firestore = firestore;

  final AuthBackend _backend;

  /// Explicit Firestore for tests. Production leaves it null and the instance
  /// is resolved lazily at call time — never in the constructor — so an
  /// uninitialized Firebase cannot crash startup through this class.
  final FirebaseFirestore? _firestore;

  @override
  AppUser? get currentUser => _backend.currentUser;

  @override
  Stream<AppUser?> authStateChanges() => _backend.authStateChanges();

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final AppUser? user;
    try {
      user = await _backend.signIn(email: email.trim(), password: password);
    } on AuthBackendFailure catch (e) {
      throw AuthException(authFailureMessage(e.code));
    }
    if (user == null) {
      // The backend accepted the call but produced no session, which is not
      // something the form can explain.
      throw const AuthException('تعذّر إنشاء الجلسة.');
    }
    return user;
  }

  @override
  Future<void> signOut() => _backend.signOut();

  /// Reads the operator's role from `users/{uid}`. Any failure — missing
  /// document, offline, denied rules — falls back to cashier rather than
  /// locking the operator out or promoting them.
  @override
  Future<AppRole> roleFor(AppUser user) async {
    try {
      final db = _firestore ?? FirebaseFirestore.instance;
      final doc = await db.collection('users').doc(user.uid).get();
      final role = AppRole.tryParse(doc.data()?['role']) ?? AppRole.cashier;
      final backend = _backend;
      if (backend is _FirebaseAuthBackend) backend.roles[user.uid] = role;
      return role;
    } catch (_) {
      return AppRole.cashier;
    }
  }
}

/// The operator-facing message for a Firebase Auth error [code].
///
/// `user-not-found` and `wrong-password` deliberately share a message: telling
/// them apart would turn the sign-in form into a way to discover which email
/// addresses have accounts.
String authFailureMessage(String code) => switch (code) {
      'invalid-email' => 'صيغة البريد الإلكتروني غير صحيحة.',
      'user-disabled' => 'تم تعطيل هذا الحساب.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
      'too-many-requests' => 'محاولات كثيرة. حاول لاحقًا.',
      'network-request-failed' => 'تعذّر الاتصال. تحقق من الشبكة.',
      'weak-password' => 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل.',
      'email-already-in-use' => 'هذا البريد مسجّل بالفعل. سجّل الدخول.',
      'operation-not-allowed' => 'تسجيل الدخول بالبريد غير مفعّل. راجع الإعدادات.',
      'requires-recent-login' => 'سجّل الدخول مجددًا لإتمام هذا الإجراء.',
      _ => 'فشل تسجيل الدخول ($code).',
    };
