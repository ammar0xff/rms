import 'dart:async';

import '../../domain/models/app_user.dart';
import 'auth_repository.dart';

/// Local, backend-free authentication used when Firebase is not configured
/// (live demo + widget tests). Any non-empty credentials sign in a demo user.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({AppUser? initialUser}) : _current = initialUser;

  AppUser? _current;
  final _controller = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() {
    return Stream<AppUser?>.multi((listener) {
      listener.add(_current);
      final sub = _controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('أدخل البريد الإلكتروني وكلمة المرور.');
    }
    final user = AppUser(
      uid: 'demo-${email.trim().hashCode.toUnsigned(20)}',
      email: email.trim(),
      displayName: email.trim().split('@').first,
      isDemo: true,
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }
}
