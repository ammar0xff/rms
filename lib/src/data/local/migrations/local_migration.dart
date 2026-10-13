import 'package:sembast/sembast.dart';

/// A single forward migration of the on-device schema.
///
/// [run] executes inside a transaction together with the version bump, so a
/// failure rolls the whole step back and the recorded version never advances
/// past data that was not transformed.
class LocalMigration {
  const LocalMigration({
    required this.from,
    required this.to,
    required this.id,
    required this.run,
    this.description = '',
  }) : assert(to > from, 'a migration must advance the version');

  final int from;
  final int to;
  final String id;
  final String description;
  final Future<void> Function(Transaction txn) run;
}
