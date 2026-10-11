import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const SectionHeader(
          title: 'الإعدادات والنظام',
          subtitle: 'إظهار الإصدار والترقيات والمؤشرات وسياسة العمل دون اتصال',
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _VersionCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _UpdateCard()),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MigrationCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _OfflinePolicyCard()),
          ],
        ),
        const _FlagsCard(),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'إظهار الإصدار', subtitle: 'المسؤولون المصرحون فقط'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('إصدار التطبيق', '0.9.4 · build 812'),
            ('مخطط البيانات المحلي', 'v7'),
            ('عقد الـ API', '2024-09-01'),
            ('إصدار الخادم', '2024.10.2'),
            ('مخطط بيانات السحابة', 'v12'),
            ('التهيئة', 'v24'),
            ('معرّف الجهاز', 'dev_a81f…c3'),
          ])
            KeyValue(label: k, value: v, mono: true),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'التحديثات',
            trailing: const Tag(label: 'مستقر', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('قناة الإصدار', 'stable'),
            ('الإصدار الحالي', '0.9.4'),
            ('الحد الأدنى المدعوم', '0.9.0'),
            ('آخر فحص للإصدارات', '12:40'),
            ('مجموعة النشر', '25%'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.system_update_alt, size: 15, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تحديث اختياري متاح · 0.9.5',
                          style: AppText.tableCellPrimary.copyWith(color: AppColors.info)),
                      const SizedBox(height: 3),
                      Text(
                        'يُسمح بالتأجيل. تُحفظ المعاملات المحلية المعلقة وتُجرى الترحيلات بشكل متصل.',
                        style: AppText.caption.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const RmsButton(label: 'تحديث', variant: BtnVariant.primary, onPressed: null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationCard extends StatelessWidget {
  const _MigrationCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'الترحيل المحلي',
            trailing: const StatusText(label: 'مكتمل', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('الحالة', 'v6 ← v7 مطبق'),
            ('اكتمل', '2024-10-08 09:14'),
            ('صندوق الصادر محفوظ', 'نعم — 0 مفقود'),
            ('نقاط التحقق', 'سليمة'),
            ('نسخة التراجع', 'محفوظة'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Text(
            'تُجرى الترحيلات قبل الوصول إلى المخطط الجديد، وتحافظ على إدخالات صندوق الصادر ومفاتيح التكرار، ولا تتقدم بالإصدار إلا عند النجاح.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _OfflinePolicyCard extends StatelessWidget {
  const _OfflinePolicyCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'سياسة العمل دون اتصال'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('المدة المسموحة دون اتصال', '24 ساعة'),
            ('أقصى عمر لنسخة القائمة', '12 ساعة'),
            ('سلوك النسخة القديمة', 'تحذير الكاشير'),
            ('العمليات عالية الخطورة دون اتصال', 'محظورة'),
            ('إعادة الطباعة عند الاتصال', 'يدوية فقط'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'لا يمكن للجهاز المنفصل معرفة وجود تحديث إلزامي. تُخزَّن سياسة آخر إصدار صالح، ويتتبع التطبيق عمرها، ولا تُهمل السجلات غير المتزامنة أبدًا.',
              style: AppText.caption.copyWith(fontSize: 10.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard();

  static const _flags = [
    ('تخطيط نقطة البيع الجديد', 'عام · مفعّل', true),
    ('الإسناد التلقائي للتوصيل', 'مجموعة 25%', false),
    ('سير عمل التسوية v2', 'الفرع · متوقف', false),
    ('تنسيق تذكرة مضغوط', 'الدور · المطبخ', true),
    ('محرك المخزون v2', 'عام · متوقف', false),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SectionHeader(
              title: 'مؤشرات الميزات',
              subtitle: 'تُدار من الخادم · ليست بديلاً عن صلاحية الواجهة الخلفية',
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _flags.length; i++) ...[
            _FlagRow(name: _flags[i].$1, scope: _flags[i].$2, on: _flags[i].$3),
            if (i != _flags.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.borderFaint),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.name, required this.scope, required this.on});

  final String name;
  final String scope;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.tableCellPrimary),
                Text(scope, style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 18,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: on ? AppColors.brandSoft : AppColors.surfaceSunken,
              border: Border.all(color: on ? AppColors.brandLine : AppColors.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Align(
              alignment: on ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: on ? AppColors.brand : AppColors.fgGhost,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
