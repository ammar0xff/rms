/// Identity of the authenticated user, decoupled from Firebase types so the
/// domain and UI layers never import the backend SDK directly.
class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isDemo = false,
  });

  final String uid;
  final String? email;
  final String? displayName;

  /// True when the session is a local, non-backend demo session.
  final bool isDemo;

  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : uid;
    return source.isEmpty ? '؟' : source.substring(0, 1);
  }
}
