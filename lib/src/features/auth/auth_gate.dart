import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_shell.dart';
import '../../domain/models/app_user.dart';
import 'sign_in_screen.dart';

/// Gates the shell behind an authenticated session. When there is no user it
/// shows the sign-in screen; otherwise it renders the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Stream<AppUser?>? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= AppScope.of(context).auth.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return StreamBuilder<AppUser?>(
      stream: _session,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        // While waiting, honor the synchronously-known user: Firebase restores
        // persisted sessions asynchronously and typically emits null first, so
        // showing the sign-in form in that window flashes (and admits
        // interaction with) a form the signed-in user should never see.
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const _Splash();
        }
        return snapshot.data == null ? const SignInScreen() : const AppShell();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.base,
      child: Center(
        child: Text('نظام إدارة المطاعم', style: AppText.bodyStrong),
      ),
    );
  }
}
