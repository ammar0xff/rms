import 'release_audit_event.dart';

/// A sink for update audit events (AC-39).
///
/// The domain layer only depends on this contract; the data layer supplies the
/// durable implementation. Keeping it abstract means the lifecycle coordinator
/// stays pure and testable without a database.
abstract class UpdateAuditSink {
  Future<void> append(ReleaseAuditEvent event);
}
