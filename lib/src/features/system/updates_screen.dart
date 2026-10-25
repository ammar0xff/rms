import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_version.dart';
import '../../core/pwa/pwa_cache_service.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/update_manifest.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/download_state.dart';

/// Screen 24: Safe Update Gateway, unsynced-work guard (AC-35), and lifecycle progress.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  bool _isLoading = true;
  bool _isChecking = false;
  bool _isInstalling = false;
  double _installProgress = 0.0;
  String _installStatusText = '';

  // Local device version & status
  final String _currentVersion = AppVersion.number;
  UpdateManifest? _availableRelease;
  int _unsyncedOutboxCount = 0;
  bool _acknowledgedRisk = false;
  StreamSubscription<DownloadState>? _downloadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    setState(() => _isChecking = true);
    final services = AppScope.of(context);

    // Check unsynced local work
    int unsynced = 0;
    if (services.outbox != null) {
      final entries = await services.outbox!.all();
      unsynced = entries.where((e) =>
          e.syncStatus == OutboxStatus.pending ||
          e.syncStatus == OutboxStatus.inProgress ||
          e.syncStatus == OutboxStatus.retryableFailure ||
          e.syncStatus == OutboxStatus.conflict).length;
    }

    // Manifest
    UpdateManifest? release;
    if (services.updateRuntime != null) {
      try {
        release = await services.updateRuntime!.manifest();
      } catch (_) {}
    }
    if (release == null && services.updates != null) {
      release = await services.updates!.cached();
    }

    // If running in demo mode and no manifest cached, create realistic mock update for preview
    if (services.isDemo) {
      release ??= UpdateManifest(
        releaseId: 'rel-1-2-4',
        version: '1.2.4',
        buildNumber: 24,
        platform: UpdatePlatform.android,
        channel: UpdateChannel.production,
        status: ReleaseStatus.active,
        rolloutPercent: 100,
        severity: UpdateSeverity.recommended,
        publishedAt: DateTime(2026, 10, 1),
        artifact: const ReleaseArtifact(
          reference: 'gs://pie-releases/pie-1.2.4.apk',
          sizeBytes: 32000000,
          sha256: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
        ),
        minSupportedVersion: '1.1.0',
        releaseNotes: 'تحسينات في أداء المزامنة التلقائية ومعالجة أوامر التوصيل.',
      );
    }

    if (mounted) {
      setState(() {
        _availableRelease = release;
        _unsyncedOutboxCount = unsynced;
        _isChecking = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _launchDirectDownload() async {
    final ref = _availableRelease?.artifact.reference;
    if (ref != null && ref.isNotEmpty) {
      final uri = Uri.tryParse(ref);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    final releaseVersion = _availableRelease?.version ?? AppVersion.number;
    final releasesUri = Uri.parse('https://github.com/ammar0xff/rms/releases/tag/v$releaseVersion');
    await launchUrl(releasesUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startUpdate() async {
    if (_unsyncedOutboxCount > 0 && !_acknowledgedRisk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب إقرار المخاطرة أو مزامنة العمليات المعلقة قبل التثبيت'),
          backgroundColor: PieColors.stateError,
        ),
      );
      return;
    }

    final services = AppScope.of(context);
    final manifest = _availableRelease;
    if (manifest == null) return;

    if (kIsWeb) {
      setState(() {
        _isInstalling = true;
        _installProgress = 0.5;
        _installStatusText = 'جاري تحديث كاش النظام وإعادة التحميل...';
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      PwaCacheService.instance.clearCacheAndReload();
      return;
    }

    setState(() {
      _isInstalling = true;
      _installProgress = 0.05;
      _installStatusText = 'بدء عملية التحديث الآمن...';
    });

    try {
      if (services.updateRuntime != null) {
        final runtime = services.updateRuntime!;
        final service = await runtime.service();
        final check = await runtime.checkManifest(manifest);

        if (!check.canInstall) {
          setState(() {
            _isInstalling = false;
            _installStatusText = 'لا يمكن التثبيت الآن: ${check.readiness.status.label}';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('لا يمكن التثبيت الآن: ${check.readiness.status.label}'),
                backgroundColor: PieColors.stateError,
              ),
            );
          }
          return;
        }

        // Listen to live download progress
        await _downloadSub?.cancel();
        _downloadSub = service.deps.downloader.progress().listen((download) {
          if (!mounted) return;
          if (download.stage == DownloadStage.downloading) {
            final progress = download.progress;
            final mbDownloaded = (download.downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (download.totalBytes / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _installProgress = (progress * 0.75).clamp(0.05, 0.75);
              _installStatusText = 'جاري تنزيل التحديث ($mbDownloaded MB / $mbTotal MB)...';
            });
          } else if (download.stage == DownloadStage.verifying) {
            setState(() {
              _installProgress = 0.85;
              _installStatusText = 'التحقق من بصمة الأمان الرقمية (SHA-256)...';
            });
          }
        });

        setState(() {
          _installProgress = 0.10;
          _installStatusText = 'جاري الاتصال وتنزيل حزمة التحديث...';
        });

        final outcome = await service.apply(check);
        await _downloadSub?.cancel();

        if (!mounted) return;

        if (outcome.state == UpdateLifecycleState.failed) {
          setState(() {
            _isInstalling = false;
            _installProgress = 0.0;
            _installStatusText = 'تعذر التثبيت التلقائي: ${outcome.errorMessage.isNotEmpty ? outcome.errorMessage : outcome.failureReason.name}';
          });

          // Show dialog with direct download fallback
          showDialog<void>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: PieColors.surface2,
                title: const Text('تثبيت يدوي للتحديث', style: TextStyle(color: PieColors.textPrimary)),
                content: Text(
                  'التثبيت التلقائي المباشر غير مكتمل على هذه المنصة (${outcome.errorMessage.isNotEmpty ? outcome.errorMessage : outcome.failureReason.name}).\nيمكنك تحميل الحزمة مباشرة وتثبيتها بنقرة واحدة.',
                  style: const TextStyle(color: PieColors.textSecondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء', style: TextStyle(color: PieColors.textMuted)),
                  ),
                  PieButton(
                    label: 'تحميل الحزمة مباشرة',
                    icon: Icons.open_in_browser,
                    role: AppRole.developer,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _launchDirectDownload();
                    },
                  ),
                ],
              ),
            ),
          );
          return;
        }

        // Success outcome
        setState(() {
          _installProgress = 1.0;
          _installStatusText = 'اكتمل تنزيل الحزمة وتم تحويلها لمثبت النظام بنجاح.';
          _isInstalling = false;
        });

        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: PieColors.surface2,
              title: const Text('بدء تثبيت التحديث', style: TextStyle(color: PieColors.textPrimary)),
              content: const Text(
                'تم التحقق من سلامة الحزمة وجاري بدء التثبيت عبر نظام التشغيل.\nيرجى تأكيد التثبيت عند ظهور نافذة النظام.',
                style: TextStyle(color: PieColors.textSecondary),
              ),
              actions: [
                PieButton(
                  label: 'حسناً',
                  role: AppRole.developer,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      } else {
        // Fallback when updateRuntime is null (e.g. demo mode)
        await _launchDirectDownload();
        setState(() {
          _isInstalling = false;
          _installProgress = 1.0;
          _installStatusText = 'تم فتح رابط التحميل المباشر في المتصفح.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installStatusText = 'حدث خطأ: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء التحديث: $e'),
          backgroundColor: PieColors.stateError,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: PieColors.surface1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'بوابة التحديثات الآمنة',
                  style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: PieColors.textSecondary),
                  tooltip: 'التحقق من وجود تحديثات',
                  onPressed: _isChecking ? null : _checkUpdate,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: PieColors.roleSystem),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current vs Available Version Header
                    PieCard(
                      role: AppRole.developer,
                      surface: PieColors.surface2,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'الإصدار الحالي المثبت',
                                    style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'v$_currentVersion',
                                    style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_back, color: PieColors.textMuted),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'الإصدار المتوفر',
                                    style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'v${_availableRelease?.version ?? _currentVersion}',
                                    style: PieTypography.h2.copyWith(
                                      color: PieColors.roleSystem,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: PieColors.borderSubtle),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'حالة التحديث:',
                                style: PieTypography.body.copyWith(color: PieColors.textSecondary),
                              ),
                              _availableRelease == null
                                  ? const PieBadge(
                                      label: 'النظام محدث بالكامل',
                                      variant: PieBadgeVariant.synced,
                                    )
                                  : _buildSeverityBadge(_availableRelease!.severity),
                            ],
                          ),
                          if (_availableRelease?.releaseNotes != null && _availableRelease!.releaseNotes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: PieColors.well,
                                borderRadius: PieRadius.borderMd,
                              ),
                              child: Text(
                                _availableRelease!.releaseNotes,
                                style: PieTypography.body.copyWith(color: PieColors.textSecondary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // AC-35 Unsynced Work Guard Card
                    Text(
                      'حارس سلامة البيانات المحلية (AC-35)',
                      style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    PieCard(
                      surface: _unsyncedOutboxCount > 0
                          ? PieColors.surface2
                          : PieColors.surface2,
                      borderColor: _unsyncedOutboxCount > 0
                          ? PieColors.stateError.withValues(alpha: 0.5)
                          : PieColors.stateSynced.withValues(alpha: 0.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _unsyncedOutboxCount > 0
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline,
                                color: _unsyncedOutboxCount > 0
                                    ? PieColors.stateError
                                    : PieColors.stateSynced,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _unsyncedOutboxCount > 0
                                          ? 'توجد عمليات محلية غير متزامنة ($_unsyncedOutboxCount)'
                                          : 'جميع العمليات متزامنة ومحمية',
                                      style: PieTypography.body.copyWith(
                                        color: PieColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _unsyncedOutboxCount > 0
                                          ? 'تثبيت التحديث الآن قد يؤدي لفقدان أو تعارض العمليات غير المرفوعة.'
                                          : 'النظام في حالة آمنة تماماً لتطبيق التحديث وترحيل المخطط.',
                                      style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_unsyncedOutboxCount > 0) ...[
                            const SizedBox(height: 16),
                            CheckboxListTile(
                              value: _acknowledgedRisk,
                              activeColor: PieColors.stateError,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'أقر بوجود عمليات غير متزامنة وأتحمل مسؤولية التثبيت الإجباري',
                                style: PieTypography.caption.copyWith(color: PieColors.textPrimary),
                              ),
                              onChanged: (val) => setState(() => _acknowledgedRisk = val ?? false),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Installation Progress
                    if (_isInstalling || _installProgress > 0) ...[
                      PieCard(
                        surface: PieColors.surface3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _installStatusText,
                                  style: PieTypography.body.copyWith(color: PieColors.roleSystem),
                                ),
                                Text(
                                  '${(_installProgress * 100).toInt()}%',
                                  style: PieTypography.body.copyWith(
                                    color: PieColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _installProgress,
                              backgroundColor: PieColors.well,
                              color: PieColors.roleSystem,
                              minHeight: 8,
                              borderRadius: PieRadius.borderSm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: PieButton(
                        label: _availableRelease == null
                            ? 'التحقق من التحديثات'
                            : (_isInstalling
                                ? 'جاري التنزيل والتثبيت الآمن...'
                                : 'تطبيق التحديث وإعادة التشغيل'),
                        icon: _availableRelease == null
                            ? Icons.refresh_rounded
                            : Icons.system_update_alt,
                        role: AppRole.developer,
                        variant: PieButtonVariant.primary,
                        onPressed: _availableRelease == null
                            ? _checkUpdate
                            : (_isInstalling || (_unsyncedOutboxCount > 0 && !_acknowledgedRisk)
                                ? null
                                : _startUpdate),
                      ),
                    ),
                    if (_availableRelease != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download_rounded, color: PieColors.roleSystem),
                          label: Text(
                            'تحميل حزمة التحديث مباشرة (${_availableRelease!.platform.name.toUpperCase()})',
                            style: PieTypography.body.copyWith(
                              color: PieColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: PieColors.border),
                            shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderMd),
                          ),
                          onPressed: _launchDirectDownload,
                        ),
                      ),
                    ],
                  ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(UpdateSeverity severity) {
    return switch (severity) {
      UpdateSeverity.mandatory => const PieBadge(
          label: 'إلزامي وفوري',
          variant: PieBadgeVariant.error,
        ),
      UpdateSeverity.recommended => const PieBadge(
          label: 'موصى به',
          variant: PieBadgeVariant.pending,
        ),
      UpdateSeverity.optional => const PieBadge(
          label: 'اختياري',
          variant: PieBadgeVariant.synced,
        ),
    };
  }
}
