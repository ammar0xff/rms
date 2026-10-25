import '../../domain/models/cash_session.dart';

/// Local-first access to cashier drawer sessions.
abstract class CashSessionRepository {
  /// All sessions, oldest first.
  Future<List<CashSession>> listSessions();

  /// The single open session, or null when the drawer has not been opened.
  Future<CashSession?> currentSession();

  /// Opens a drawer session. If one is already open it is returned untouched.
  Future<CashSession> openSession({
    required double openingFloat,
    String? cashierUid,
    String? cashierName,
    String? branchId,
    String? branchName,
    bool createdOffline = false,
  });

  /// Counts and closes a session, recording the variance from expected cash.
  Future<CashSession> closeSession(
    String id, {
    required double countedCash,
    String? note,
    String? cashierUid,
    String? cashierName,
  });

  /// Expected drawer total (opening float + cash movements) for [session].
  Future<double> expectedCash(CashSession session);

  /// Real-time stream of the current open drawer session, or null when closed.
  Stream<CashSession?> watchCurrentSession() => Stream.fromFuture(currentSession());
}
