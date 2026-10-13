import '../models/update_manifest.dart';

/// The outcome of an installation attempt.
enum InstallResult {
  ok('نجح التثبيت'),
  cancelled('أُلغي التثبيت'),
  failed('فشل التثبيت');

  const InstallResult(this.label);

  final String label;
}

/// An abstraction over the platform installer.
///
/// The web/mobile layer supplies the real implementation; the domain layer
/// never installs directly.
abstract class UpdateInstaller {
  Future<InstallResult> install({required UpdateManifest manifest});
}
