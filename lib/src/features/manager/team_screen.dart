import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/permissions.dart';

/// Screen 22: Team roster, roles, shift status, and permission matrix.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  // Demo team roster representing all 4 operational roles
  final List<_TeamMember> _members = [
    _TeamMember(
      user: const AppUser(
        uid: 'usr-1',
        displayName: 'أحمد محمود',
        email: 'ahmed.cashier@pie.eg',
        role: AppRole.cashier,
      ),
      shiftActive: true,
      shiftOpenedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 15)),
      permissions: {Permissions.orderVoid, Permissions.paymentReprint},
    ),
    _TeamMember(
      user: const AppUser(
        uid: 'usr-2',
        displayName: 'محمد صابر',
        email: 'mohamed.cashier@pie.eg',
        role: AppRole.cashier,
      ),
      shiftActive: false,
      permissions: {Permissions.orderVoid, Permissions.paymentReprint},
    ),
    _TeamMember(
      user: const AppUser(
        uid: 'usr-3',
        displayName: 'طارق حسام',
        email: 'tarek.driver@pie.eg',
        role: AppRole.driver,
      ),
      shiftActive: true,
      shiftOpenedAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 40)),
      permissions: {},
    ),
    _TeamMember(
      user: const AppUser(
        uid: 'usr-4',
        displayName: 'كريم عثمان',
        email: 'karim.driver@pie.eg',
        role: AppRole.driver,
      ),
      shiftActive: true,
      shiftOpenedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 10)),
      permissions: {},
    ),
    _TeamMember(
      user: const AppUser(
        uid: 'usr-5',
        displayName: 'سارة إبراهيم (أنت)',
        email: 'sara.manager@pie.eg',
        role: AppRole.manager,
      ),
      shiftActive: true,
      shiftOpenedAt: DateTime.now().subtract(const Duration(hours: 6)),
      permissions: Set.of(Permissions.all),
    ),
    _TeamMember(
      user: const AppUser(
        uid: 'usr-6',
        displayName: 'مهندس النظام',
        email: 'sysadmin@pie.eg',
        role: AppRole.developer,
      ),
      shiftActive: false,
      permissions: Set.of(Permissions.all),
    ),
  ];

  AppRole? _selectedRoleFilter;
  _TeamMember? _selectedMember;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services.firebaseReady) {
      _members.clear();
    }
    _listenToLiveUsers();
  }

  void _listenToLiveUsers() {
    final services = AppScope.of(context);
    if (!services.firebaseReady) return;

    _usersSub?.cancel();
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        final List<_TeamMember> live = [];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final email = (data['email'] as String? ?? '').trim();
          final roleStr = data['role'] as String?;
          final role = AppRole.tryParse(roleStr) ?? inferRoleFromEmail(email);
          final displayName = (data['displayName'] as String? ?? '').trim();
          final name = displayName.isNotEmpty
              ? displayName
              : (email.isNotEmpty ? email.split('@').first : 'موظف');
          final rawPerms = (data['permissions'] as List?)?.cast<String>() ?? [];
          final perms = rawPerms.isNotEmpty
              ? rawPerms.toSet()
              : (role == AppRole.manager || role == AppRole.developer
                  ? Set.of(Permissions.all)
                  : <String>{Permissions.orderVoid, Permissions.paymentReprint});

          live.add(
            _TeamMember(
              user: AppUser(
                uid: doc.id,
                displayName: name,
                email: email,
                role: role,
              ),
              shiftActive: true,
              shiftOpenedAt: (data['updatedAt'] is Timestamp)
                  ? (data['updatedAt'] as Timestamp).toDate()
                  : null,
              permissions: perms,
            ),
          );
        }

        setState(() {
          _members.clear();
          _members.addAll(live);
          if (_selectedMember != null) {
            final match = _members.where((m) => m.user.uid == _selectedMember!.user.uid);
            _selectedMember = match.isNotEmpty ? match.first : null;
          }
        });
      },
      onError: (_) {},
    );
  }

  Future<void> _showAddMemberDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    AppRole chosenRole = AppRole.cashier;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: PieColors.surfaceOverlay,
            shape: const RoundedRectangleBorder(
              borderRadius: PieRadius.borderLg,
              side: BorderSide(color: PieColors.border),
            ),
            title: const Row(
              children: [
                Icon(Icons.person_add_rounded, color: PieColors.roleManager, size: 24),
                SizedBox(width: 10),
                Text('إضافة موظف جديد للفريق', style: PieTypography.heading),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'اسم الموظف بالكامل',
                      filled: true,
                      fillColor: PieColors.well,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني للموظف',
                      filled: true,
                      fillColor: PieColors.well,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('الدور الوظيفي:', style: PieTypography.caption),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: AppRole.values.map((r) {
                      return ChoiceChip(
                        label: Text(r.label),
                        selected: chosenRole == r,
                        selectedColor: PieColors.roleManager.withValues(alpha: 0.25),
                        onSelected: (_) => setDialogState(() => chosenRole = r),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('إلغاء', style: TextStyle(color: PieColors.inkSecondary)),
              ),
              PieButton.primary(
                label: isSaving ? 'جاري الحفظ...' : 'حفظ الموظف',
                accentColor: PieColors.roleManager,
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final email = emailCtrl.text.trim();
                        if (name.isEmpty || email.isEmpty) return;
                        setDialogState(() => isSaving = true);
                        try {
                          final uid = 'usr_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
                          final services = AppScope.of(context);
                          if (services.firebaseReady) {
                            await FirebaseFirestore.instance.collection('users').doc(uid).set({
                              'uid': uid,
                              'displayName': name,
                              'email': email,
                              'role': chosenRole.name,
                              'updatedAt': FieldValue.serverTimestamp(),
                              'createdAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          } else {
                            setState(() {
                              _members.add(_TeamMember(
                                user: AppUser(uid: uid, displayName: name, email: email, role: chosenRole),
                                shiftActive: true,
                                permissions: chosenRole == AppRole.manager || chosenRole == AppRole.developer
                                    ? Set.of(Permissions.all)
                                    : <String>{Permissions.orderVoid, Permissions.paymentReprint},
                              ));
                            });
                          }
                          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    super.dispose();
  }

  List<_TeamMember> get _filteredMembers {
    if (_selectedRoleFilter == null) return _members;
    return _members.where((m) => m.user.role == _selectedRoleFilter).toList();
  }

  void _openPermissionsDialog(_TeamMember member) {
    final services = AppScope.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => _PermissionMatrixDialog(
        member: member,
        onMemberUpdated: (newRole, newPerms) async {
          setState(() {
            member.permissions = newPerms;
            member.user = member.user.copyWith(role: newRole);
          });
          if (services.firebaseReady) {
            try {
              await FirebaseFirestore.instance.collection('users').doc(member.user.uid).set({
                'role': newRole.name,
                'permissions': newPerms.toList(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (_) {}
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final activeShiftCount = _members.where((m) => m.shiftActive).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: PieColors.surface1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'فريق العمل والصلاحيات',
                  style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: PieColors.roleManager.withValues(alpha: 0.15),
                        borderRadius: PieRadius.borderSm,
                        border: Border.all(color: PieColors.roleManager.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: PieColors.roleManager, size: 8),
                          const SizedBox(width: 6),
                          Text(
                            '$activeShiftCount في الوردية الآن',
                            style: PieTypography.caption.copyWith(
                              color: PieColors.roleManager,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PieButton.primary(
                      onPressed: () => _showAddMemberDialog(context),
                      label: 'إضافة موظف',
                      icon: Icons.person_add_rounded,
                      accentColor: PieColors.roleManager,
                      height: 36,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Pills Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: PieColors.surface2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                      label: Text('الكل (${_members.length})'),
                      selected: _selectedRoleFilter == null,
                      selectedColor: PieColors.roleManager.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedRoleFilter == null
                            ? PieColors.roleManager
                            : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedRoleFilter = null),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('كاشير (${_members.where((m) => m.user.role == AppRole.cashier).length})'),
                      selected: _selectedRoleFilter == AppRole.cashier,
                      selectedColor: PieColors.roleCashier.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedRoleFilter == AppRole.cashier
                            ? PieColors.roleCashier
                            : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedRoleFilter = AppRole.cashier),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('طيار (${_members.where((m) => m.user.role == AppRole.driver).length})'),
                      selected: _selectedRoleFilter == AppRole.driver,
                      selectedColor: PieColors.roleDriver.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedRoleFilter == AppRole.driver
                            ? PieColors.roleDriver
                            : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedRoleFilter = AppRole.driver),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('إدارة (${_members.where((m) => m.user.role == AppRole.manager).length})'),
                      selected: _selectedRoleFilter == AppRole.manager,
                      selectedColor: PieColors.roleManager.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedRoleFilter == AppRole.manager
                            ? PieColors.roleManager
                            : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedRoleFilter = AppRole.manager),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            Expanded(
              child: _filteredMembers.isEmpty
                  ? const PieEmptyState(
                      icon: Icons.people_outline,
                      title: 'لا يوجد أعضاء في هذا الدور',
                    )
                  : isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filteredMembers.length,
                                itemBuilder: (ctx, i) => _buildMemberCard(
                                  _filteredMembers[i],
                                  isSelected: _selectedMember?.user.uid == _filteredMembers[i].user.uid,
                                  onTap: () => setState(() => _selectedMember = _filteredMembers[i]),
                                ),
                              ),
                            ),
                            Container(width: 1, color: PieColors.borderSubtle),
                            Expanded(
                              flex: 2,
                              child: _selectedMember == null
                                  ? const Center(
                                      child: Text(
                                        'اختر موظفاً لعرض مصفوفة صلاحياته وتاريخ وريدته',
                                        style: TextStyle(color: PieColors.textMuted),
                                      ),
                                    )
                                  : _buildMemberDetailPane(_selectedMember!),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredMembers.length,
                          itemBuilder: (ctx, i) => _buildMemberCard(_filteredMembers[i]),
                        ),
            ),
          ],
        ),
    );
  }

  Widget _buildMemberCard(
    _TeamMember member, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final roleColor = _getRoleColor(member.user.role);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PieCard(
        surface: isSelected ? PieColors.surface3 : PieColors.surface2,
        borderColor: isSelected ? PieColors.roleManager : null,
        onTap: onTap ?? () => _openPermissionsDialog(member),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  child: Text(
                    member.user.initials,
                    style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            member.user.displayName ?? member.user.uid,
                            style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                          ),
                          const SizedBox(width: 8),
                          if (member.shiftActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: PieColors.stateSynced.withValues(alpha: 0.15),
                                borderRadius: PieRadius.borderSm,
                              ),
                              child: Text(
                                'وردية جارية',
                                style: PieTypography.caption.copyWith(color: PieColors.stateSynced),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: PieColors.well,
                                borderRadius: PieRadius.borderSm,
                              ),
                              child: Text(
                                'خارج الوردية',
                                style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member.user.email ?? member.user.uid,
                        style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: PieRadius.borderSm,
                    border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    member.user.role.label,
                    style: PieTypography.caption.copyWith(
                      color: roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PieColors.well,
                borderRadius: PieRadius.borderMd,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الصلاحيات الخاصة الممنوحة:', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                          member.permissions.isEmpty
                              ? 'الافتراضية للدور فقط'
                              : '${member.permissions.length} صلاحيات مفعلة',
                          style: PieTypography.body.copyWith(
                            color: member.permissions.isEmpty ? PieColors.textMuted : PieColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PieButton(
                    label: 'تعديل الصلاحيات',
                    variant: PieButtonVariant.ghost,
                    icon: Icons.security,
                    role: AppRole.manager,
                    onPressed: () => _openPermissionsDialog(member),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberDetailPane(_TeamMember member) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مصفوفة صلاحيات: ${member.user.displayName}',
            style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
          ),
          const SizedBox(height: 12),
          PieCard(
            surface: PieColors.surface2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الصلاحيات المباشرة',
                  style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                ),
                const SizedBox(height: 12),
                ...Permissions.all.map((key) {
                  final has = member.permissions.contains(key);
                  return CheckboxListTile(
                    title: Text(
                      Permissions.labels[key] ?? key,
                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    ),
                    subtitle: Text(
                      key,
                      style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                    ),
                    value: has,
                    activeColor: PieColors.roleManager,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          member.permissions.add(key);
                        } else {
                          member.permissions.remove(key);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PieButton(
            label: 'إعادة تعيين إلى افتراضيات الدور',
            variant: PieButtonVariant.secondary,
            role: AppRole.manager,
            onPressed: () {
              setState(() {
                member.permissions = Permissions.defaultsFor(member.user.role);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تمت استعادة الصلاحيات الافتراضية')),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(AppRole role) {
    return switch (role) {
      AppRole.cashier => PieColors.roleCashier,
      AppRole.driver => PieColors.roleDriver,
      AppRole.manager => PieColors.roleManager,
      AppRole.developer => PieColors.roleSystem,
    };
  }
}

class _TeamMember {
  _TeamMember({
    required this.user,
    required this.shiftActive,
    this.shiftOpenedAt,
    required this.permissions,
  });

  AppUser user;
  final bool shiftActive;
  final DateTime? shiftOpenedAt;
  Set<String> permissions;
}

class _PermissionMatrixDialog extends StatefulWidget {
  const _PermissionMatrixDialog({
    required this.member,
    required this.onMemberUpdated,
  });

  final _TeamMember member;
  final void Function(AppRole role, Set<String> perms) onMemberUpdated;

  @override
  State<_PermissionMatrixDialog> createState() => _PermissionMatrixDialogState();
}

class _PermissionMatrixDialogState extends State<_PermissionMatrixDialog> {
  late Set<String> _perms;
  late AppRole _role;

  @override
  void initState() {
    super.initState();
    _perms = Set.of(widget.member.permissions);
    _role = widget.member.user.role;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: PieColors.surface2,
        title: Text(
          'تعديل دور وصلاحيات ${widget.member.user.displayName}',
          style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الدور الوظيفي للموظف:', style: PieTypography.label),
                const SizedBox(height: 6),
                DropdownButtonFormField<AppRole>(
                  value: _role,
                  dropdownColor: PieColors.surface3,
                  style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: PieColors.well,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: AppRole.cashier, child: Text('كاشير (Cashier)')),
                    DropdownMenuItem(value: AppRole.driver, child: Text('كابتن توصيل (Driver)')),
                    DropdownMenuItem(value: AppRole.manager, child: Text('مدير فرع (Manager)')),
                    DropdownMenuItem(value: AppRole.developer, child: Text('مسؤول نظام (Developer)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _role = val);
                  },
                ),
                const SizedBox(height: 16),
                Text('مصفوفة الصلاحيات الخاصة:', style: PieTypography.label),
                const SizedBox(height: 8),
                ...Permissions.all.map((key) {
                  final has = _perms.contains(key);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Permissions.labels[key] ?? key,
                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    ),
                    subtitle: Text(
                      key,
                      style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                    ),
                    value: has,
                    activeColor: PieColors.roleManager,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _perms.add(key);
                        } else {
                          _perms.remove(key);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: PieColors.textMuted)),
          ),
          PieButton(
            label: 'حفظ التعديلات',
            role: AppRole.manager,
            onPressed: () {
              widget.onMemberUpdated(_role, _perms);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
