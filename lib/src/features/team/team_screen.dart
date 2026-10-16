import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../data/services/pin_service.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/permissions.dart';

/// Who may use the app, and as what.
///
/// Operators sign in with email/password; this screen maps each account to a
/// role, and the shell builds that role's app around them. Only privileged
/// roles (manager, developer) can open it — the shell never links here
/// otherwise — and nobody can change their own role, so a manager cannot
/// lock themselves out or quietly promote themselves mid-incident.
///
/// The first account has no document yet (nothing can write one), so it is
/// created directly in the console: a `users/{uid}` document with
/// `{email, role, displayName}`. Everything after that happens here.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<_Member> _members = const [];
  bool _loaded = false;
  String? _error;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    if (!services.firebaseReady) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('email')
          .get()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _members = [
          for (final doc in snapshot.docs) _Member.fromDoc(doc.id, doc.data()),
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  /// Sets or replaces the manager PIN (4-8 digits, twice to confirm).
  /// Privileged roles only; the hash lives in Firestore, never on device.
  Future<void> _setPin() async {
    final messenger = ScaffoldMessenger.of(context);
    final first = await showDialog<String>(
      context: context,
      builder: (_) => const _PinEntrySheet(title: 'PIN جديد للمدير'),
    );
    if (first == null || first.isEmpty) return;
    if (!mounted) return;
    final second = await showDialog<String>(
      context: context,
      builder: (_) => const _PinEntrySheet(title: 'أكّد الـ PIN الجديد'),
    );
    if (second == null || second.isEmpty) return;
    if (first != second) {
      messenger.showSnackBar(
        const SnackBar(content: Text('الرقمين مش زي بعض — جرّب تاني')),
      );
      return;
    }
    try {
      await PinService().setPin(first);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الـ PIN — تحقق من الاتصال')),
      );
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('اتحفظ الـ PIN الجديد')),
    );
  }

  /// Edits one member's permission set. Explicit list replaces role
  /// defaults; saving writes the list, never the role.
  Future<void> _editPermissions(_Member member) async {
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _PermissionsSheet(initial: member.permissions),
    );
    if (updated == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(member.uid)
          .set({'permissions': updated.toList()}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الصلاحيات اتحفظت')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الصلاحيات — جرّب تاني')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setRole(_Member member, AppRole role) async {
    if (_saving || role == member.role) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(member.uid)
          .set({'role': role.name}, SetOptions(merge: true)).timeout(
                const Duration(seconds: 15),
              );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حفظ الدور فشل: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final me = services.auth.currentUser;
    final canEdit = (me?.role ?? AppRole.cashier).isPrivileged;
    return PageBody(
      children: [
        SectionHeader(
          title: 'الفريق',
          subtitle: 'الحساب هو مفتاح ما يُعرض: الدور يحدد التطبيق',
          trailing: canEdit && services.firebaseReady
              ? RmsButton(
                  label: 'PIN المدير',
                  icon: Icons.pin_outlined,
                  onPressed: _setPin,
                )
              : null,
        ),
        if (!services.firebaseReady)
          const SurfaceCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'إدارة الفريق تتطلب Firebase. في وضع العرض مفيش حسابات حقيقية تُدار.',
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          )
        else if (_error != null)
          SurfaceCard(
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: AppColors.negative),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تحميل الفريق فشل: $_error',
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          )
        else if (_members.isEmpty)
          const SurfaceCard(
            child: Text(
              'مفيش حسابات بعد. أنشئ أول مستخدم من الكونسول ثم أسند الأدوار هنا.',
              style: AppText.body,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              Widget row(int i) => _MemberRow(
                    member: _members[i],
                    isSelf: _members[i].uid == me?.uid,
                    canEdit: canEdit && !_saving,
                    onRole: (role) => _setRole(_members[i], role),
                    onPermissions:
                        canEdit && _members[i].uid != me?.uid
                            ? () => _editPermissions(_members[i])
                            : null,
                  );
              // Phones get the single divided list; wide screens get a
              // two-column card grid of the same rows.
              if (c.maxWidth < 700) {
                return SurfaceCard(
                  padding: EdgeInsets.zero,
                  clip: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _members.length; i++) ...[
                        row(i),
                        if (i != _members.length - 1)
                          const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: AppColors.borderFaint,
                          ),
                      ],
                    ],
                  ),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 84,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _members.length,
                itemBuilder: (context, i) => SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: row(i),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// PIN entry with confirmation display. Returns the digits, or null.
class _PinEntrySheet extends StatefulWidget {
  const _PinEntrySheet({required this.title});

  final String title;

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: widget.title,
      subtitle: 'من ٤ لـ ٨ أرقام.',
      content: TextField(
        controller: _pin,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: '••••',
          border: OutlineInputBorder(),
          counterText: '',
        ),
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'تأكيد',
          onPressed: _pin.text.trim().length >= 4
              ? () => Navigator.of(context).pop(_pin.text.trim())
              : null,
        ),
      ],
    );
  }
}

class _Member {
  const _Member({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.permissions,
  });

  final String uid;
  final String email;
  final String displayName;
  final AppRole role;
  final Set<String> permissions;

  factory _Member.fromDoc(String uid, Map<String, dynamic> data) {
    final email = data['email'];
    final displayName = data['displayName'];
    final role = AppRole.tryParse(data['role']) ?? AppRole.cashier;
    return _Member(
      uid: uid,
      email: email is String ? email : uid,
      displayName: displayName is String ? displayName : '',
      role: role,
      permissions: Permissions.parse(data['permissions'], role),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.canEdit,
    required this.onRole,
    required this.onPermissions,
  });

  final _Member member;
  final bool isSelf;
  final bool canEdit;
  final ValueChanged<AppRole> onRole;
  final VoidCallback? onPermissions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.hover,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              member.displayName.isNotEmpty
                  ? member.displayName.substring(0, 1)
              : member.email.isNotEmpty
                  ? member.email.substring(0, 1)
                  : '؟',
              style: AppText.bodyStrong,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName.isNotEmpty
                      ? member.displayName
                      : member.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.tableCellPrimary,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      const Tag(label: 'أنت', tone: StatusTone.info),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (canEdit && !isSelf)
            DropdownButton<AppRole>(
              value: member.role,
              underline: const SizedBox.shrink(),
              style: AppText.tableCellPrimary,
              items: [
                for (final role in AppRole.values)
                  DropdownMenuItem(
                    value: role,
                    child: Text(role.label),
                  ),
              ],
              onChanged: (role) {
                if (role != null) onRole(role);
              },
            )
          else
            Tag(
              label: member.role.label,
              tone: member.role.isPrivileged
                  ? StatusTone.positive
                  : StatusTone.neutral,
            ),
          if (onPermissions != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onPermissions,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.tune_outlined,
                    size: 18, color: AppColors.fgMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Permission matrix: one switch per action, explicit list replaces role
/// defaults on save (empty means nothing allowed).
class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet({required this.initial});

  final Set<String> initial;

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late Set<String> _picked = Set.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: 'صلاحيات العضو',
      subtitle: 'القائمة الصريحة بتحل محل صلاحيات الدور.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in Permissions.all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(Permissions.labels[key] ?? key,
                        style: AppText.tableCellPrimary),
                  ),
                  Switch.adaptive(
                    value: _picked.contains(key),
                    onChanged: (v) => setState(() {
                      if (v) {
                        _picked.add(key);
                      } else {
                        _picked.remove(key);
                      }
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'احفظ الصلاحيات',
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
