import 'package:flutter/foundation.dart';

import '../../domain/models/update_manifest.dart';
import '../../domain/update/update_decision.dart';
import 'app_version.dart';

/// The platform this build is running on.
///
/// Web is checked first because [defaultTargetPlatform] reports the host
/// platform under Flutter web; the remaining targets map one-to-one.
UpdatePlatform currentUpdatePlatform() {
  if (kIsWeb) return UpdatePlatform.web;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return UpdatePlatform.android;
    case TargetPlatform.iOS:
      return UpdatePlatform.ios;
    case TargetPlatform.macOS:
      return UpdatePlatform.macos;
    case TargetPlatform.windows:
      return UpdatePlatform.windows;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return UpdatePlatform.linux;
  }
}

/// The channel this build tracks.
///
/// A compile-time constant, so an offline device cannot talk itself onto a
/// different channel; the backend still decides what is published.
UpdateChannel currentUpdateChannel() =>
    UpdateChannel.tryParse(AppVersion.channel) ?? UpdateChannel.production;

/// Builds the device facts a release manifest is classified against.
///
/// Kept in `core` because resolving the running platform needs Flutter's
/// foundation layer; the decision that consumes it stays pure.
UpdateContext buildUpdateContext({
  required DateTime now,
  String backendVersion = '',
  String branchId = '',
  String cohortSeed = '',
  String architecture = '',
  String deviceGroup = '',
  int localSchemaVersion = AppVersion.localSchemaVersion,
}) =>
    UpdateContext(
      installedVersion: AppVersion.number,
      installedBuild: AppVersion.build,
      platform: currentUpdatePlatform(),
      channel: currentUpdateChannel(),
      architecture: architecture,
      deviceGroup: deviceGroup,
      now: now,
      backendVersion: backendVersion,
      localSchemaVersion: localSchemaVersion,
      branchId: branchId,
      cohortSeed: cohortSeed,
    );
