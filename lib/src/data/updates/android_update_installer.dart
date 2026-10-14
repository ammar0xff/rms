import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/update_manifest.dart';
import '../../domain/update/update_installer.dart';
import 'artifact_paths.dart';

/// Hands a downloaded APK to the Android system package installer.
///
/// Android never lets an app replace itself silently. The only supported route
/// is to start an install intent for the downloaded file and let the user
/// confirm, which is why [InstallResult.cancelled] is a normal outcome rather
/// than an error.
///
/// The file handed over is the one [HttpArtifactDownloader] wrote, located via
/// [artifactFileName] in the app's temporary directory. The manifest's
/// `artifact.reference` is the remote Storage path and would not exist on disk.
class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller({
    this.channel = const MethodChannel('dev.rms.app/update'),
  });

  final MethodChannel channel;

  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, artifactFileName(manifest)));

      if (!await file.exists()) {
        // The download did not complete, or was cleaned up. Never hand the
        // platform a path that is not there.
        return InstallResult.failed;
      }

      final outcome = await channel.invokeMethod<String>('installApk', {
        'path': file.path,
        'releaseId': manifest.releaseId,
      });
      return switch (outcome) {
        'ok' => InstallResult.ok,
        'cancelled' => InstallResult.cancelled,
        _ => InstallResult.failed,
      };
    } catch (_) {
      // Any failure here means the same thing to the caller: the update could
      // not be handed to the platform. That covers a missing plugin (a test, or
      // a platform whose installer has not been written yet), a platform
      // exception from the channel, and a missing temporary directory. The
      // lifecycle coordinator turns this into a terminal failed status with a
      // reason, so nothing is swallowed silently.
      return InstallResult.failed;
    }
  }
}