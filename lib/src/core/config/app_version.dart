/// Single source of truth for build/version metadata surfaced in the UI.
///
/// Keep in sync with `pubspec.yaml` (the `version:` line). Phase 0 has no
/// platform channel, so these are compiled constants rather than reading
/// `package_info_plus`.
abstract final class AppVersion {
  static const String number = '0.4.0';
  static const int build = 1;
  static const String localSchema = 'v3';
  static const int localSchemaVersion = 3;
  static const String apiContract = '2026-10-11';

  static String get string => '$number · build $build';
}
