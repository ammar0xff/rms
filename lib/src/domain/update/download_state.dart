/// The outcome of verifying a downloaded artifact against the release manifest.
enum ArtifactVerificationStatus {
  /// The file matches the manifest's checksum and is ready for installation.
  verified('تم التحقق بنجاح'),

  /// No checksum is present in the manifest to verify against.
  noChecksum('لا يوجد بصمة للتحقق'),

  /// The downloaded file was not found or could not be read.
  notFound('لم يُعثر على الملف المحمل'),

  /// The file's SHA-256 does not match the manifest.
  checksumMismatch('بصمة الحزمة غير مطابقة'),

  /// The file could not be hashed because it is too large or an I/O error
  /// occurred.
  ioError('فشل في قراءة الحزمة للتحقق');

  const ArtifactVerificationStatus(this.label);

  final String label;
}

/// The result of verifying a downloaded artifact.
class ArtifactVerification {
  const ArtifactVerification({
    required this.status,
    required this.downloadedBytes,
    this.sha256 = '',
  });

  final ArtifactVerificationStatus status;
  final int downloadedBytes;
  final String sha256;

  bool get isOk => status == ArtifactVerificationStatus.verified;
}

/// The stage of downloading a release artifact.
enum DownloadStage {
  idle('خامل'),
  starting('جاري البدء'),
  downloading('جاري التنزيل'),
  verifying('جاري التحقق'),
  completed('اكتمل التنزيل'),
  failed('فشل التنزيل'),
  cancelled('أُلغي التنزيل');

  const DownloadStage(this.label);

  final String label;
}

/// The state of an in-progress or completed artifact download.
class DownloadState {
  const DownloadState({
    required this.stage,
    required this.totalBytes,
    this.downloadedBytes = 0,
    this.bytesPerSecond = 0,
    this.progress = 0.0,
    this.error = '',
    this.verification,
    this.startedAt,
    this.endedAt,
  });

  final DownloadStage stage;
  final int totalBytes;
  final int downloadedBytes;
  final int bytesPerSecond;
  final double progress;
  final String error;
  final ArtifactVerification? verification;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isActive =>
      stage == DownloadStage.starting ||
      stage == DownloadStage.downloading ||
      stage == DownloadStage.verifying;

  bool get isTerminal =>
      stage == DownloadStage.completed ||
      stage == DownloadStage.failed ||
      stage == DownloadStage.cancelled;
}
