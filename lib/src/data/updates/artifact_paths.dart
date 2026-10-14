import '../../domain/models/update_manifest.dart';

/// The canonical on-disk name for a downloaded release artifact.
///
/// The downloader writes the artifact and the installer later hands that same
/// file to the platform, but the two are constructed independently and the
/// manifest only carries the remote Storage reference. Both therefore derive
/// the same local path from the build number, which is unique per release.
///
/// Keeping the derivation here — rather than inline in each side — is what stops
/// the downloader and installer from quietly disagreeing about which file to
/// open.
String artifactFileName(UpdateManifest manifest) =>
    'rms-update-${manifest.buildNumber}.artifact';