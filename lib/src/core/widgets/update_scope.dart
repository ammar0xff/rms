import 'package:flutter/widgets.dart';

import '../../features/updates/update_controller.dart';

/// Publishes the one [UpdateController] for the session.
///
/// Owned above the auth gate rather than inside the shell: a signed-out
/// device still has to learn that a release exists, otherwise it can sit on a
/// stale build indefinitely and never be told otherwise. Sign-in, the shell,
/// and Settings all read the same controller, so a check started at the gate
/// is the check every surface sees.
class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({
    required UpdateController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The session controller, or null when the build/runtime has none.
  static UpdateController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UpdateScope>()
      ?.notifier;
}
