import '../../domain/models/app_user.dart';

/// Authentication boundary. Implementations may be backend-backed (Firebase)
/// or local (demo). The UI and domain depend only on this interface.
abstract class AuthRepository {
  /// Emits the current user (or `null` when signed out) and on every change.
  Stream<AppUser?> authStateChanges();

  /// The synchronously-known current user, if any.
  AppUser? get currentUser;

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException($message)';
}
