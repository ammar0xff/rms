import '../../domain/models/app_role.dart';
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

  /// Registers a new real user account.
  Future<AppUser> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
    AppRole? role,
  });

  Future<void> signOut();

  /// Resolves the operator's role. Never throws: unknown or unreadable roles
  /// fall back to [AppRole.cashier], because a role lookup failure must not
  /// lock anyone out — nor silently promote them.
  Future<AppRole> roleFor(AppUser user);

  /// Updates the currently signed-in operator's profile (name and/or password).
  Future<void> updateProfile({String? displayName, String? newPassword});
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException($message)';
}
