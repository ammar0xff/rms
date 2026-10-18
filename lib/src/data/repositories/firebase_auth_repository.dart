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

/// Infers an operator role from their email address convention.
/// Used as a fallback when Firestore is offline or before server lookup completes.
AppRole inferRoleFromEmail(String? email) {
  final local = (email ?? '').trim().toLowerCase().split('@').first;
  if (local.isEmpty) return AppRole.cashier;

  // Courier / Driver detection (e.g. driver1, pilot_alex, courier, delivery, tayar)
  if (local.contains('driver') ||
      local.contains('pilot') ||
      local.contains('courier') ||
      local.contains('delivery') ||
      local.contains('tayyar') ||
      local.contains('tayar')) {
    return AppRole.driver;
  }

  // Developer / System Admin detection (e.g. admin, sysadmin, dev, root, superadmin)
  if (local.contains('admin') ||
      local.contains('dev') ||
      local.contains('root') ||
      local.contains('super')) {
    return AppRole.developer;
  }

  // Manager detection (e.g. manager, modir, supervisor, gm, branch_lead)
  if (local.contains('manager') ||
      local.contains('modir') ||
      local.contains('supervis') ||
      local.contains('lead') ||
      local.contains('head')) {
    return AppRole.manager;
  }

  // Cashier detection (e.g. cashier, cahier, pos, till, teller)
  if (local.contains('cashier') ||
      local.contains('cahier') ||
      local.contains('pos') ||
      local.contains('till') ||
      local.contains('teller')) {
    return AppRole.cashier;
  }

  return AppRole.cashier;
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
        role: roles[user.uid] ?? inferRoleFromEmail(user.email),
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
  Future<void> signOut() {
    roles.clear();
    return _auth.signOut();
  }
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
  AppUser? get currentUser {
    final user = _backend.currentUser;
    if (user == null) return null;
    final backend = _backend;
    if (backend is _FirebaseAuthBackend) {
      final cachedRole = backend.roles[user.uid];
      if (cachedRole != null) {
        return user.copyWith(role: cachedRole);
      }
    }
    return user.role != AppRole.cashier
        ? user
        : user.copyWith(role: inferRoleFromEmail(user.email));
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _backend.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      final role = await roleFor(user);
      return user.copyWith(role: role);
    });
  }

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
    final role = await roleFor(user);
    return user.copyWith(role: role);
  }

  @override
  Future<void> signOut() => _backend.signOut();

  /// Reads the operator's role from `users/{uid}`. If missing or without a role,
  /// infers from the email convention and initializes the user profile doc.
  /// Any failure — offline, denied rules — safely falls back to inferring
  /// from email rather than locking the operator out.
  @override
  Future<AppRole> roleFor(AppUser user) async {
    try {
      final db = _firestore ?? FirebaseFirestore.instance;
      final docRef = db.collection('users').doc(user.uid);
      final doc = await docRef.get();
      final data = doc.data();
      final parsedRole = AppRole.tryParse(data?['role']);

      if (parsedRole != null) {
        final backend = _backend;
        if (backend is _FirebaseAuthBackend) backend.roles[user.uid] = parsedRole;
        return parsedRole;
      }

      // No role on the document, by design. The rules let an operator create
      // and maintain their own profile but refuse a self-assigned `role`,
      // because that field is what `isPrivileged()` reads — writing it would be
      // a privilege escalation, not a profile. Sending it anyway would get the
      // whole write denied and leave no profile at all. Until a manager assigns
      // a real role, the email inference below stands in, which is what this
      // method has always fallen back to.
      final inferredRole = inferRoleFromEmail(user.email);
      try {
        await docRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName':
              user.displayName ?? (user.email?.split('@').first ?? ''),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-fatal if offline or Firestore uninitialized
      }

      final backend = _backend;
      if (backend is _FirebaseAuthBackend) backend.roles[user.uid] = inferredRole;
      return inferredRole;
    } catch (_) {
      final role = inferRoleFromEmail(user.email);
      final backend = _backend;
      if (backend is _FirebaseAuthBackend) backend.roles[user.uid] = role;
      return role;
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
