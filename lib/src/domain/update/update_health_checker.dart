import '../models/update_manifest.dart';
import 'device_update_status.dart';

/// An abstraction over the post-install health check.
///
/// A health check that returns anything other than [UpdateHealthStatus.passed]
/// must not be treated as success: the coordinator treats it as a failure so
/// the release can be rolled back rather than left half-applied.
abstract class UpdateHealthChecker {
  Future<UpdateHealthStatus> check({required UpdateManifest manifest});
}
