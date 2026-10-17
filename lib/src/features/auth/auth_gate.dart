import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/update_scope.dart';
import '../../features/updates/update_controller.dart';
import '../../domain/update/update_prompt_mode.dart';
import '../../features/updates/update_prompt.dart';
import '../../domain/models/app_user.dart';
import 'sign_in_screen.dart';

/// Gates the shell behind an authenticated session. When there is no user it
/// shows the sign-in screen; otherwise it renders the app.
///
/// Also owns the update poll, which has to live here rather than in the shell:
/// a device parked on the sign-in screen is exactly the device that goes
/// stale without ever being told a new release exists.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Stream<AppUser?>? _session;
  UpdateController? _updates;
  DateTime? _lastCheck;
  bool _dismissedOptional = false;

  /// Resume re-checks, but not on every foreground flip: an operator
  /// backgrounding the app to answer a call must not spend the rate limit.
  static const _resumeInterval = Duration(minutes: 5);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= AppScope.of(context).auth.authStateChanges();
    if (_updates != null) return;
    final runtime = AppScope.of(context).updateRuntime;
    if (runtime == null) return;
    final controller = UpdateController(runtime: runtime);
    _updates = controller;
    // A check after the first frame, so startup is never blocked on the
    // network. Never on a build with no runtime to ask.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _restoreSnooze();
  }

  /// A persisted snooze survives restarts: dismissing the optional prompt
  /// shelves it for the rest of the shift (8h), not just the session.
  Future<void> _snoozeOptional() async {
    final store = AppScope.of(context).updateStatus;
    if (store != null) {
      await store.setSnoozedUntil(
        DateTime.now().add(const Duration(hours: 8)),
      );
    }
    if (!mounted) return;
    setState(() => _dismissedOptional = true);
  }

  Future<void> _restoreSnooze() async {
    final store = AppScope.of(context).updateStatus;
    final until = await store?.snoozedUntil();
    if (!mounted) return;
    if (until != null && until.isAfter(DateTime.now())) {
      setState(() => _dismissedOptional = true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null &&
        DateTime.now().difference(last) < _resumeInterval) {
      return;
    }
    _check();
  }

  void _check() {
    _lastCheck = DateTime.now();
    _updates?.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final controller = _updates;
    final body = StreamBuilder<AppUser?>(
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
    if (controller == null) return body;
    return UpdateScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Stack(
          children: [
            body,
            // A mandatory update, an update in flight, or a finished attempt is
            // laid over the whole app: there is nothing useful to do until it
            // is resolved. Deferring an optional release lasts 8h — but only
            // for the dismissible prompt. A deferral must never suppress a
            // mandatory release, an in-flight update, or a failure.
            if (!(_dismissedOptional &&
                controller.state.mode == UpdatePromptMode.dismissible))
              UpdatePrompt(
                controller: controller,
                onDismissed: _snoozeOptional,
              ),
          ],
        ),
      ),
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
