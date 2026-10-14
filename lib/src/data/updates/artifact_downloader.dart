/// Resolves the artifact downloader for the current platform.
///
/// Mobile and desktop get the real HTTP downloader. Web gets a stub that
/// reports a failure, because artifact delivery is not supported there.
export 'artifact_downloader_stub.dart'
    if (dart.library.io) 'artifact_downloader_io.dart';