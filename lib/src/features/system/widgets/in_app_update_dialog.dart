import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_version.dart';
import '../../../core/di/app_services.dart';
import '../../../core/theme/pie_colors.dart';
import '../../../core/theme/pie_radius.dart';
import '../../../core/theme/pie_typography.dart';
import '../../../core/widgets/pie_button.dart';
import '../../../domain/models/app_role.dart';
import '../../../domain/models/update_manifest.dart';
import '../../../domain/update/device_update_status.dart';
import '../../../domain/update/download_state.dart';
import '../../../core/pwa/pwa_cache_service.dart';

/// Modal dialog that performs 100% in-app updates without kicking the user out
/// to an external browser or third-party store.
class InAppUpdateDialog extends StatefulWidget {
  const InAppUpdateDialog({
    super.key,
    required this.manifest,
    this.onComplete,
  });

  final UpdateManifest manifest;
  final VoidCallback? onComplete;

  static Future<void> show(
    BuildContext context, {
    required UpdateManifest manifest,
    VoidCallback? onComplete,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InAppUpdateDialog(
        manifest: manifest,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<InAppUpdateDialog> createState() => _InAppUpdateDialogState();
}

class _InAppUpdateDialogState extends State<InAppUpdateDialog> {
  bool _isUpdating = false;
  double _progress = 0.0;
  String _statusText = 'جاهز لبدء التحديث مباشرة دون مغادرة التطبيق.';
  String? _errorMessage;
  StreamSubscription<DownloadState>? _downloadSub;

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _startInAppUpdate() async {
    if (kIsWeb) {
      setState(() {
        _isUpdating = true;
        _statusText = 'جاري تحديث كاش النظام وإعادة التحميل...';
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      PwaCacheService.instance.clearCacheAndReload();
      return;
    }

    final services = AppScope.of(context);
    final runtime = services.updateRuntime;
    if (runtime == null) {
      setState(() {
        _errorMessage = 'خدمة التحديث التلقائي غير مفعلة في هذه الجلسة.';
      });
      return;
    }

    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _progress = 0.05;
      _statusText = 'الاتصال بخادم التحديثات...';
    });

    try {
      final service = await runtime.service();
      final check = await runtime.checkManifest(widget.manifest);

      if (!check.canInstall) {
        setState(() {
          _isUpdating = false;
          _errorMessage =
              'لا يمكن التثبيت الآن: ${check.readiness.status.label}';
        });
        return;
      }

      await _downloadSub?.cancel();
      _downloadSub = service.deps.downloader.progress().listen((download) {
        if (!mounted) return;
        if (download.stage == DownloadStage.downloading) {
          final p = download.progress;
          final mbDownloaded =
              (download.downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal =
              (download.totalBytes / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _progress = (p * 0.80).clamp(0.05, 0.80);
            _statusText =
                'جاري تنزيل الحزمة ($mbDownloaded MB / $mbTotal MB)...';
          });
        } else if (download.stage == DownloadStage.verifying) {
          setState(() {
            _progress = 0.90;
            _statusText = 'التحقق من بصمة الأمان الرقمية (SHA-256)...';
          });
        }
      });

      setState(() {
        _progress = 0.10;
        _statusText = 'بدء تنزيل ملف التحديث في الخلفية...';
      });

      final outcome = await service.apply(check);
      await _downloadSub?.cancel();

      if (!mounted) return;

      if (outcome.state == UpdateLifecycleState.failed) {
        setState(() {
          _isUpdating = false;
          _progress = 0.0;
          _errorMessage = outcome.errorMessage.isNotEmpty
              ? outcome.errorMessage
              : outcome.failureReason.name;
        });
        return;
      }

      // Success
      setState(() {
        _isUpdating = false;
        _progress = 1.0;
        _statusText =
            'اكتمل التنزيل! جاري فتح مثبت النظام لتأكيد التحديث فوراً.';
      });

      widget.onComplete?.call();

      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _progress = 0.0;
        _errorMessage = 'حدث خطأ غير متوقع: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;
    final current = AppVersion.number;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surface2,
        shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderLg),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with icon and version tags
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: PieColors.roleSystem.withValues(alpha: 0.15),
                        borderRadius: PieRadius.borderMd,
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: PieColors.roleSystem,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تحديث جديد للنظام',
                            style: PieTypography.subheading,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ترقية من v$current إلى v${manifest.version}',
                            style: PieTypography.caption.copyWith(
                              color: PieColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: PieColors.roleSystem.withValues(alpha: 0.2),
                        borderRadius: PieRadius.borderSm,
                        border: Border.all(
                          color: PieColors.roleSystem.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'v${manifest.version}',
                        style: const TextStyle(
                          color: PieColors.roleSystem,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (manifest.severity == UpdateSeverity.mandatory) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: PieColors.stateError.withValues(alpha: 0.12),
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(
                        color: PieColors.stateError.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: PieColors.stateError,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تحديث إجباري: هذا التحديث إلزامي لمتابعة العمل واستقرار المزامنة.',
                            style: PieTypography.caption.copyWith(
                              color: PieColors.stateError,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(color: PieColors.border, height: 1),
                const SizedBox(height: 14),

                // Release notes if available
                if (manifest.releaseNotes.isNotEmpty) ...[
                  Text(
                    'ما الجديد في هذا التحديث:',
                    style: PieTypography.bodyStrong.copyWith(
                      color: PieColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PieColors.well,
                      borderRadius: PieRadius.borderMd,
                      border: Border.all(color: PieColors.border),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        manifest.releaseNotes,
                        style: PieTypography.body.copyWith(
                          color: PieColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Live Progress & Status
                if (_isUpdating || _progress > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _statusText,
                          style: PieTypography.caption.copyWith(
                            color: PieColors.roleSystem,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: PieTypography.bodyStrong.copyWith(
                          color: PieColors.roleSystem,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: PieColors.surface3,
                    color: PieColors.roleSystem,
                    minHeight: 8,
                    borderRadius: PieRadius.borderSm,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Text(
                    _statusText,
                    style: PieTypography.body.copyWith(
                      color: PieColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Error Message if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PieColors.stateError.withValues(alpha: 0.12),
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(
                        color: PieColors.stateError.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: PieColors.stateError,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: PieTypography.caption.copyWith(
                              color: PieColors.stateError,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_isUpdating && manifest.severity != UpdateSeverity.mandatory)
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        child: const Text(
                          'تأجيل',
                          style: TextStyle(color: PieColors.textMuted),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: PieButton(
                          label: _isUpdating
                              ? 'جاري التحديث...'
                              : (_errorMessage != null
                                  ? 'إعادة المحاولة'
                                  : 'تثبيت التحديث الآن'),
                          icon: _isUpdating
                              ? Icons.hourglass_top_rounded
                              : Icons.download_rounded,
                          role: AppRole.developer,
                          variant: PieButtonVariant.primary,
                          onPressed: _isUpdating ? null : _startInAppUpdate,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
