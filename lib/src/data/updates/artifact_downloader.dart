/// Resolves the artifact downloader for the current platform.
///
/// Mobile and desktop get the real HTTP downloader. Web gets a stub that
/// reports a failure, because artifact delivery is not supported there.
///
/// Callers use [createArtifactDownloader] rather than naming a concrete class:
/// the type differs per platform, so code shared by every platform — the DI
/// bootstrap among them — cannot reference one directly.
export 'artifact_downloader_stub.dart'
    if (dart.library.io) 'artifact_downloader_io.dart';