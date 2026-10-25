import '../../domain/models/semantic_version.dart';

/// Single source of truth for build/version metadata surfaced to the UI and to
/// the update engine.
///
/// Keep the compiled fallbacks in sync with `pubspec.yaml` (the `version:`
/// line). They are only used when the platform cannot be asked — but see
/// [number] for why that fallback is not the value the update engine should be
/// trusting.
abstract final class AppVersion {
  /// The version compiled into the binary. Overridden at runtime by
  /// [apply] from the installed package.
  static const String compiledNumber = '0.36.0';

  /// The build number compiled into the binary. Overridden at runtime by
  /// [apply].
  static const int compiledBuild = 37;

  /// The running version, e.g. `0.10.0`.
  ///
  /// This is read from the installed package at startup rather than taken from
  /// [compiledNumber], because the release workflow sets the version with
  /// `--build-name`/`--build-number` at build time. A compiled constant cannot
  /// track that: it would keep reporting whatever was written here, so a device
  /// that had just installed the current release would still consider that
  /// release to be newer than itself and prompt to update, forever.
  static String number = compiledNumber;

  /// The running build number, monotonic within a [number].
  static int build = compiledBuild;

  /// The release channel this build tracks (see `UpdateChannel`). Compiled in so
  /// an offline device cannot switch itself onto a different channel.
  static const String channel = 'production';

  static const String localSchema = 'v5';
  static const int localSchemaVersion = 5;
  static const String apiContract = '2026-10-11';

  /// Records the version reported by the platform.
  ///
  /// Blank or implausible values are ignored rather than applied, so a
  /// malformed platform response degrades to the compiled fallback instead of
  /// making the app claim to be something it is not. "Implausible" means "not
  /// a three-part semantic version" — the update engine compares these
  /// strings, so a garbage version would produce garbage verdicts.
  static void apply({required String version, required int build}) {
    final trimmed = version.trim();
    if (trimmed.isNotEmpty && SemanticVersion.tryParse(trimmed) != null) {
      number = trimmed;
    }
    if (build > 0) AppVersion.build = build;
  }

  /// Restores the compiled values. Tests only — a hydrated version is process
  /// state and would otherwise leak between test cases.
  static void reset() {
    number = compiledNumber;
    build = compiledBuild;
  }

  static String get string => '$number · build $build';
}
