import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';

typedef _Rows = List<Map<String, dynamic>>;

final _membersProvider = FutureProvider.autoDispose<_Rows>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('organization_members')
      .select('id, user_id, role_id, status, branch_ids, joined_at, profiles(full_name, email), roles(name, is_owner)')
      .eq('org_id', m.orgId)
      .order('joined_at');
  return List<Map<String, dynamic>>.from(rows);
});

final _invitesProvider = FutureProvider.autoDispose<_Rows>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('invitations')
      .select('id, email, status, branch_ids, created_at, roles(name)')
      .eq('org_id', m.orgId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

final _rolesProvider = FutureProvider.autoDispose<_Rows>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('roles')
      .select('id, name, description, is_system, is_owner')
      .eq('org_id', m.orgId)
      .order('is_owner', ascending: false)
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});

final _allBranchesProvider = FutureProvider.autoDispose<_Rows>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('branches')
      .select('id, name')
      .eq('org_id', m.orgId)
      .eq('is_active', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});

class UsersRolesPage extends ConsumerStatefulWidget {
  const UsersRolesPage({super.key});

  @override
  ConsumerState<UsersRolesPage> createState() => _UsersRolesPageState();
}

class _UsersRolesPageState extends ConsumerState<UsersRolesPage> {
  int _tab = 0;

  Future<void> _invite() async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => const _InviteForm());
    if (saved == true) {
      ref.invalidate(_invitesProvider);
      if (mounted) showToast(context, 'Invitation created');
    }
  }

  Future<void> _newRole() async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => const _RoleForm());
    if (saved == true) ref.invalidate(_rolesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(activeMembershipProvider);
    final perms = ref.watch(permsProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.users)) return const NoAccessView();
    final canCreate = perms.can(Modules.users, PermAction.create);

    return AppPage(
      title: 'Users and roles',
      subtitle: 'Control who can do what in ${m.orgName}',
      actions: [
        if (_tab == 1 && canCreate) AppButton(label: 'Invite user', icon: Icons.person_add_alt_1_outlined, onPressed: _invite),
        if (_tab == 2 && canCreate) AppButton(label: 'New role', icon: Icons.add_rounded, onPressed: _newRole),
      ],
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PillTabs(labels: const ['Members', 'Invitations', 'Roles'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          0 => const _MembersTab(),
          1 => const _InvitesTab(),
          _ => const _RolesTab(),
        },
      ],
    );
  }
}

// ---------------------------------------------------------------- Members

class _MembersTab extends ConsumerWidget {
  const _MembersTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic> row) async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => _MemberForm(member: row));
    if (saved == true) {
      ref.invalidate(_membersProvider);
      ref.invalidate(membershipsProvider);
      ref.invalidate(permissionsProvider);
      ref.invalidate(branchesProvider);
      if (context.mounted) showToast(context, 'Member updated');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_membersProvider);
    final myId = ref.watch(currentUserIdProvider);
    final canEdit = ref.watch(permsProvider).can(Modules.users, PermAction.edit);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_membersProvider)),
      data: (rows) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(),
              _memberRow(context, ref, rows[i], myId, canEdit),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(BuildContext context, WidgetRef ref, Map<String, dynamic> r, String? myId, bool canEdit) {
    final profile = (r['profiles'] as Map?) ?? const {};
    final role = (r['roles'] as Map?) ?? const {};
    final name = (profile['full_name'] as String?) ?? (profile['email'] as String?) ?? 'Member';
    final branches = ((r['branch_ids'] as List?) ?? const []).length;
    final isMe = r['user_id'] == myId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(name: name, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '$name (you)' : name, style: AppText.bodyStrong),
                Text('${profile['email'] ?? ''}', style: AppText.small),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge('${role['name'] ?? 'No role'}', tone: role['is_owner'] == true ? BadgeTone.primary : BadgeTone.neutral),
                    StatusBadge.status('${r['status']}'),
                    Text(branches == 0 ? 'All branches' : '$branches ${branches == 1 ? 'branch' : 'branches'}', style: AppText.small),
                  ],
                ),
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Edit member',
              onPressed: () => _edit(context, ref, r),
              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _BranchScope extends ConsumerWidget {
  const _BranchScope({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(_allBranchesProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Branch access'),
        Text('Leave empty to allow every branch.', style: AppText.small),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in branches)
              FilterChip(
                label: Text('${b['name']}'),
                selected: selected.contains(b['id']),
                showCheckmark: false,
                selectedColor: AppColors.primarySoft,
                backgroundColor: Colors.white,
                side: BorderSide(color: selected.contains(b['id']) ? AppColors.primary : AppColors.border),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected.contains(b['id']) ? AppColors.primary : AppColors.textSecondary,
                ),
                onSelected: (on) {
                  final next = {...selected};
                  if (on) {
                    next.add(b['id'] as String);
                  } else {
                    next.remove(b['id']);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm({required this.member});
  final Map<String, dynamic> member;

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  late String _roleId;
  late String _status;
  late Set<String> _branches;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roleId = widget.member['role_id'] as String;
    _status = widget.member['status'] as String;
    _branches = ((widget.member['branch_ids'] as List?) ?? const []).map((e) => '$e').toSet();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).from('organization_members').update({
        'role_id': _roleId,
        'status': _status,
        'branch_ids': _branches.toList(),
      }).eq('id', widget.member['id'] as Object);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(_rolesProvider).valueOrNull ?? const [];
    final profile = (widget.member['profiles'] as Map?) ?? const {};
    final isSelf = widget.member['user_id'] == ref.watch(currentUserIdProvider);
    return FormShell(
      title: 'Edit member',
      subtitle: '${profile['full_name'] ?? profile['email'] ?? ''}',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          AppButton(label: 'Save changes', loading: _saving, onPressed: _save),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSelf) ...[
            Text('You cannot change your own role or status. Ask another owner or administrator.', style: AppText.small),
            const SizedBox(height: 12),
          ],
          AppDropdown<String>(
            label: 'Role',
            value: roles.any((r) => r['id'] == _roleId) ? _roleId : null,
            items: [for (final r in roles) DropdownMenuItem(value: r['id'] as String, child: Text('${r['name']}'))],
            onChanged: isSelf ? null : (v) => setState(() => _roleId = v ?? _roleId),
          ),
          const SizedBox(height: 16),
          AppDropdown<String>(
            label: 'Status',
            value: _status,
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'suspended', child: Text('Suspended (temporarily blocked)')),
              DropdownMenuItem(value: 'revoked', child: Text('Revoked (access removed)')),
            ],
            onChanged: isSelf ? null : (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 16),
          _BranchScope(selected: _branches, onChanged: (s) => setState(() => _branches = s)),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Invitations

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab();

  Future<void> _revoke(BuildContext context, WidgetRef ref, Map<String, dynamic> row) async {
    final ok = await confirmDialog(
      context,
      title: 'Revoke invitation?',
      message: '${row['email']} will no longer be able to join with this invitation.',
      confirmLabel: 'Revoke',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from('invitations').update({'status': 'revoked'}).eq('id', row['id'] as Object);
      ref.invalidate(_invitesProvider);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_invitesProvider);
    final canEdit = ref.watch(permsProvider).can(Modules.users, PermAction.edit);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_invitesProvider)),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppCard(
            child: EmptyState(
              icon: Icons.mail_outline_rounded,
              title: 'No invitations yet',
              message: 'Invite colleagues by email. They join automatically when they register or sign in with that address.',
            ),
          );
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${rows[i]['email']}', style: AppText.bodyStrong),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusBadge('${(rows[i]['roles'] as Map?)?['name'] ?? 'Role'}'),
                                StatusBadge.status('${rows[i]['status']}'),
                                Text(Fmt.timeAgo(Fmt.parse(rows[i]['created_at'] as String?)), style: AppText.small),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (canEdit && rows[i]['status'] == 'pending')
                        AppButton(label: 'Revoke', kind: AppButtonKind.ghost, compact: true, onPressed: () => _revoke(context, ref, rows[i])),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InviteForm extends ConsumerStatefulWidget {
  const _InviteForm();

  @override
  ConsumerState<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends ConsumerState<_InviteForm> {
  final _key = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _roleId;
  Set<String> _branches = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final m = ref.read(activeMembershipProvider);
    final uid = ref.read(currentUserIdProvider);
    if (m == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).from('invitations').insert({
        'org_id': m.orgId,
        'email': _email.text.trim().toLowerCase(),
        'role_id': _roleId,
        'branch_ids': _branches.toList(),
        'invited_by': uid,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.code == '23505' ? 'This email already has a pending invitation.' : friendlyError(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = (ref.watch(_rolesProvider).valueOrNull ?? const <Map<String, dynamic>>[]).where((r) => r['is_owner'] != true).toList();
    return Form(
      key: _key,
      child: FormShell(
        title: 'Invite user',
        subtitle: 'They join automatically when they register or sign in with this email.',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: 'Send invitation', loading: _saving, onPressed: _save),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _email,
              label: 'Email address',
              required: true,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email address' : null,
            ),
            const SizedBox(height: 16),
            AppDropdown<String>(
              label: 'Role',
              required: true,
              hint: 'Select a role',
              value: _roleId,
              items: [for (final r in roles) DropdownMenuItem(value: r['id'] as String, child: Text('${r['name']}'))],
              onChanged: (v) => setState(() => _roleId = v),
              validator: (v) => v == null ? 'Choose a role' : null,
            ),
            const SizedBox(height: 16),
            _BranchScope(selected: _branches, onChanged: (s) => setState(() => _branches = s)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Roles

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  Future<void> _permissions(BuildContext context, WidgetRef ref, Map<String, dynamic> role, bool canEdit) async {
    final saved = await showAdaptiveForm<bool>(
      context,
      maxWidth: 840,
      builder: (_) => _PermissionMatrix(role: role, readOnly: !canEdit || role['is_owner'] == true),
    );
    if (saved == true) {
      ref.invalidate(permissionsProvider);
      if (context.mounted) showToast(context, 'Permissions updated');
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic> role) async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => _RoleForm(role: role));
    if (saved == true) ref.invalidate(_rolesProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Map<String, dynamic> role) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete role?',
      message: 'The "${role['name']}" role will be removed. Roles that still have members cannot be deleted.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from('roles').delete().eq('id', role['id'] as Object);
      ref.invalidate(_rolesProvider);
    } on PostgrestException catch (e) {
      if (context.mounted) {
        showToast(
          context,
          e.code == '23503' ? 'This role is assigned to members or invitations. Move them to another role first.' : friendlyError(e),
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_rolesProvider);
    final perms = ref.watch(permsProvider);
    final canEdit = perms.can(Modules.users, PermAction.edit);
    final canDelete = perms.can(Modules.users, PermAction.delete);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_rolesProvider)),
      data: (rows) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(),
              _roleRow(context, ref, rows[i], canEdit, canDelete),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roleRow(BuildContext context, WidgetRef ref, Map<String, dynamic> r, bool canEdit, bool canDelete) {
    final isOwner = r['is_owner'] == true;
    final isSystem = r['is_system'] == true;
    final desc = r['description'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('${r['name']}', style: AppText.bodyStrong)),
                    const SizedBox(width: 8),
                    StatusBadge(isOwner ? 'Owner' : (isSystem ? 'Standard' : 'Custom'), tone: isOwner ? BadgeTone.primary : BadgeTone.neutral),
                  ],
                ),
                if (desc != null && desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(desc, style: AppText.small)),
              ],
            ),
          ),
          AppButton(
            label: canEdit && !isOwner ? 'Permissions' : 'View',
            kind: AppButtonKind.ghost,
            compact: true,
            onPressed: () => _permissions(context, ref, r, canEdit),
          ),
          if (!isSystem && (canEdit || canDelete))
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
              onSelected: (v) {
                if (v == 'edit') _edit(context, ref, r);
                if (v == 'delete') _delete(context, ref, r);
              },
              itemBuilder: (_) => [
                if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Rename')),
                if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _RoleForm extends ConsumerStatefulWidget {
  const _RoleForm({this.role});
  final Map<String, dynamic>? role;

  @override
  ConsumerState<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends ConsumerState<_RoleForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: (widget.role?['name'] as String?) ?? '');
  late final TextEditingController _desc = TextEditingController(text: (widget.role?['description'] as String?) ?? '');
  String? _copyFrom;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.role != null;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = ref.read(supabaseProvider);
    final desc = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    try {
      if (_isEdit) {
        await client.from('roles').update({'name': _name.text.trim(), 'description': desc}).eq('id', widget.role!['id'] as Object);
      } else {
        final created = await client
            .from('roles')
            .insert({'org_id': m.orgId, 'name': _name.text.trim(), 'description': desc})
            .select('id')
            .single();
        if (_copyFrom != null) {
          final source = await client.from('role_permissions').select().eq('role_id', _copyFrom!);
          if (source.isNotEmpty) {
            await client.from('role_permissions').insert([
              for (final row in source) {...row, 'role_id': created['id']},
            ]);
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(_rolesProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    return Form(
      key: _key,
      child: FormShell(
        title: _isEdit ? 'Rename role' : 'New role',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: _isEdit ? 'Save changes' : 'Create role', loading: _saving, onPressed: _save),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _name,
              label: 'Role name',
              required: true,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a role name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(controller: _desc, label: 'Description', maxLines: 3),
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              AppDropdown<String>(
                label: 'Start from an existing role',
                hint: 'Start with no permissions',
                value: _copyFrom,
                items: [for (final r in roles.where((r) => r['is_owner'] != true)) DropdownMenuItem(value: r['id'] as String, child: Text('${r['name']}'))],
                onChanged: (v) => setState(() => _copyFrom = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------ Permission matrix

class _PermissionMatrix extends ConsumerStatefulWidget {
  const _PermissionMatrix({required this.role, required this.readOnly});

  final Map<String, dynamic> role;
  final bool readOnly;

  @override
  ConsumerState<_PermissionMatrix> createState() => _PermissionMatrixState();
}

class _PermissionMatrixState extends ConsumerState<_PermissionMatrix> {
  Map<String, Set<PermAction>>? _grants;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final grants = {for (final m in Modules.all) m.key: <PermAction>{}};
    if (widget.role['is_owner'] == true) {
      for (final s in grants.values) {
        s.addAll(PermAction.values);
      }
    } else {
      try {
        final rows = await ref.read(supabaseProvider).from('role_permissions').select().eq('role_id', widget.role['id'] as Object);
        for (final row in rows) {
          final s = grants[row['module']];
          if (s == null) continue;
          for (final a in PermAction.values) {
            if (row['can_${a.name}'] == true) s.add(a);
          }
        }
      } catch (e) {
        _error = friendlyError(e);
      }
    }
    if (mounted) setState(() => _grants = grants);
  }

  void _toggle(String module, PermAction a, bool on) {
    final s = _grants![module]!;
    if (on) {
      s.add(a);
      if (a != PermAction.view) s.add(PermAction.view);
    } else {
      s.remove(a);
      if (a == PermAction.view) s.clear();
    }
  }

  void _toggleColumn(PermAction a) {
    setState(() {
      final all = Modules.all.every((m) => _grants![m.key]!.contains(a));
      for (final m in Modules.all) {
        _toggle(m.key, a, !all);
      }
    });
  }

  Future<void> _save() async {
    final m = ref.read(activeMembershipProvider);
    if (m == null || _grants == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rows = [
        for (final mod in Modules.all)
          {
            'org_id': m.orgId,
            'role_id': widget.role['id'],
            'module': mod.key,
            for (final a in PermAction.values) 'can_${a.name}': _grants![mod.key]!.contains(a),
          },
      ];
      await ref.read(supabaseProvider).from('role_permissions').upsert(rows, onConflict: 'role_id,module');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grants = _grants;
    return FormShell(
      title: 'Permissions: ${widget.role['name']}',
      subtitle: widget.role['is_owner'] == true
          ? 'The owner role has full access and cannot be restricted.'
          : (widget.readOnly ? 'You can view but not change these permissions.' : 'Choose what this role can do in each area.'),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: widget.readOnly ? 'Close' : 'Cancel',
            kind: AppButtonKind.secondary,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 12),
            AppButton(label: 'Save permissions', loading: _saving, onPressed: grants == null ? null : _save),
          ],
        ],
      ),
      child: grants == null
          ? const LoadingView()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 790,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(width: 270, child: Text('Area', style: AppText.small.copyWith(fontWeight: FontWeight.w600))),
                            for (final a in PermAction.values)
                              SizedBox(
                                width: 86,
                                child: InkWell(
                                  onTap: widget.readOnly ? null : () => _toggleColumn(a),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Center(child: Text(Fmt.humanize(a.name), style: AppText.small.copyWith(fontWeight: FontWeight.w600))),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Divider(),
                        for (final mod in Modules.all) ...[
                          Row(
                            children: [
                              SizedBox(
                                width: 270,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(mod.label, style: AppText.label),
                                      Text(mod.description, style: AppText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ),
                              for (final a in PermAction.values)
                                SizedBox(
                                  width: 86,
                                  child: Center(
                                    child: Checkbox(
                                      value: grants[mod.key]!.contains(a),
                                      visualDensity: VisualDensity.compact,
                                      onChanged: widget.readOnly ? null : (v) => setState(() => _toggle(mod.key, a, v ?? false)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
    );
  }
}
