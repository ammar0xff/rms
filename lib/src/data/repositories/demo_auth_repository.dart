import 'dart:async';

import '../../domain/models/app_role.dart';
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
    final address = email.trim();
    final user = AppUser(
      uid: 'demo-${address.hashCode.toUnsigned(20)}',
      email: address,
      displayName: address.split('@').first,
      isDemo: true,
      role: _inferRole(address),
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

  /// Demo convention: the email local part names the role
  /// (`driver.ahmed@…`, `dev@…`). Anything else signs in as a manager, so
  /// demo mode stays fully explorable without configuration.
  @override
  Future<AppRole> roleFor(AppUser user) async => _inferRole(user.email);

  static AppRole _inferRole(String? email) {
    final local = (email ?? '').trim().toLowerCase().split('@').first;
    for (final entry in const [
      ('driver', AppRole.driver),
      ('cashier', AppRole.cashier),
      ('chef', AppRole.chef),
      ('manager', AppRole.manager),
      ('developer', AppRole.developer),
      ('dev', AppRole.developer),
    ]) {
      if (local == entry.$1 ||
          local.startsWith('${entry.$1}.') ||
          local.startsWith('${entry.$1}_')) {
        return entry.$2;
      }
    }
    return AppRole.manager;
  }
}
