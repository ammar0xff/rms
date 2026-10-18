import 'app_role.dart';

/// Identity of the authenticated user, decoupled from Firebase types so the
/// domain and UI layers never import the backend SDK directly.
class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isDemo = false,
    this.role = AppRole.cashier,
  });

  final String uid;
  final String? email;
  final String? displayName;

  /// True when the session is a local, non-backend demo session.
  final bool isDemo;

  /// Resolved at sign-in ([AuthRepository.roleFor]); cashier until then.
  final AppRole role;

  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : uid;
    return source.isEmpty ? '؟' : source.substring(0, 1);
  }

  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    bool? isDemo,
    AppRole? role,
  }) =>
      AppUser(
        uid: uid ?? this.uid,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        isDemo: isDemo ?? this.isDemo,
        role: role ?? this.role,
      );
}
