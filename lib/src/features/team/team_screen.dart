import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/app_role.dart';

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
        const SectionHeader(
          title: 'الفريق',
          subtitle: 'الحساب هو مفتاح ما يُعرض: الدور يحدد التطبيق',
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
          SurfaceCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _members.length; i++) ...[
                  _MemberRow(
                    member: _members[i],
                    isSelf: _members[i].uid == me?.uid,
                    canEdit: canEdit && !_saving,
                    onRole: (role) => _setRole(_members[i], role),
                  ),
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
  });

  final String uid;
  final String email;
  final String displayName;
  final AppRole role;

  factory _Member.fromDoc(String uid, Map<String, dynamic> data) {
    final email = data['email'];
    final displayName = data['displayName'];
    return _Member(
      uid: uid,
      email: email is String ? email : uid,
      displayName: displayName is String ? displayName : '',
      role: AppRole.tryParse(data['role']) ?? AppRole.cashier,
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.canEdit,
    required this.onRole,
  });

  final _Member member;
  final bool isSelf;
  final bool canEdit;
  final ValueChanged<AppRole> onRole;

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
        ],
      ),
    );
  }
}
