import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import 'finance_providers.dart';

class ChartOfAccountsPage extends ConsumerStatefulWidget {
  const ChartOfAccountsPage({super.key});

  @override
  ConsumerState<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends ConsumerState<ChartOfAccountsPage> {
  final Set<String> _collapsed = {};
  String _search = '';
  bool _showArchived = false;

  Future<void> _openForm(Rows accounts, {Map<String, dynamic>? account, String? parentId}) async {
    final saved = await showAdaptiveForm<bool>(
      context,
      builder: (_) => _AccountForm(accounts: accounts, account: account, parentId: parentId),
    );
    if (saved == true) {
      ref.invalidate(accountsProvider);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> a) async {
    final active = a['is_active'] == true;
    final ok = await confirmDialog(
      context,
      title: active ? 'Archive account?' : 'Restore account?',
      message: active
          ? '${a['name']} will no longer be offered for new entries. Past transactions stay in your books.'
          : '${a['name']} will be available again.',
      confirmLabel: active ? 'Archive' : 'Restore',
      danger: active,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from('accounts').update({'is_active': !active}).eq('id', a['id'] as Object);
      ref.invalidate(accountsProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete account?',
      message: 'This removes ${a['name']} permanently. Accounts with transactions cannot be deleted; archive them instead.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from('accounts').delete().eq('id', a['id'] as Object);
      ref.invalidate(accountsProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.finance)) return const NoAccessView();
    final canCreate = perms.can(Modules.finance, PermAction.create);
    final canEdit = perms.can(Modules.finance, PermAction.edit);
    final canDelete = perms.can(Modules.finance, PermAction.delete);
    final showMoney = perms.canView(Modules.financialData);

    final async = ref.watch(accountsProvider);
    final balances = showMoney ? ref.watch(balancesProvider).valueOrNull : null;

    return AppPage(
      title: 'Chart of accounts',
      subtitle: 'Every account your books are kept in',
      actions: [
        if (canCreate)
          AppButton(
            label: 'Add account',
            icon: Icons.add_rounded,
            onPressed: () => _openForm(async.valueOrNull ?? const []),
          ),
      ],
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                hint: 'Search by code or name',
                prefixIcon: Icons.search_rounded,
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 12),
            FilterChip(
              label: const Text('Show archived'),
              selected: _showArchived,
              onSelected: (v) => setState(() => _showArchived = v),
              showCheckmark: false,
              selectedColor: AppColors.primarySoft,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border),
            ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(accountsProvider)),
          data: (all) => _tree(all, balances, m.currency, canCreate, canEdit, canDelete),
        ),
      ],
    );
  }

  Widget _tree(Rows all, Map<String, ({double debit, double credit})>? balances, String currency, bool canCreate, bool canEdit, bool canDelete) {
    final visible = all.where((a) => _showArchived || a['is_active'] == true).toList();
    final children = <String?, Rows>{};
    for (final a in visible) {
      children.putIfAbsent(a['parent_id'] as String?, () => []).add(a);
    }

    double total(Map<String, dynamic> a) {
      if (a['is_group'] == true) {
        return (children[a['id']] ?? const []).fold<double>(0, (s, c) => s + total(c));
      }
      final b = balances?[a['id']];
      return b == null ? 0 : signedBalance(a['account_type'] as String, b.debit, b.credit);
    }

    final q = _search.trim().toLowerCase();
    final rows = <Widget>[];

    void addRow(Map<String, dynamic> a, int depth) {
      final isGroup = a['is_group'] == true;
      final id = a['id'] as String;
      final collapsed = _collapsed.contains(id);
      rows.add(_row(a, depth, isGroup, collapsed, balances == null ? null : Fmt.money(total(a), currency: currency), all, canCreate, canEdit, canDelete));
      if (isGroup && !collapsed) {
        for (final c in children[id] ?? const <Map<String, dynamic>>[]) {
          addRow(c, depth + 1);
        }
      }
    }

    if (q.isNotEmpty) {
      for (final a in visible.where((a) => '${a['code']} ${a['name']}'.toLowerCase().contains(q))) {
        rows.add(_row(a, 0, a['is_group'] == true, false, balances == null || a['is_group'] == true ? null : Fmt.money(total(a), currency: currency), all, canCreate, canEdit, canDelete));
      }
      if (rows.isEmpty) {
        return const AppCard(child: EmptyState(icon: Icons.search_off_rounded, title: 'No matching accounts'));
      }
    } else {
      for (final type in accountTypeOrder) {
        final roots = (children[null] ?? const <Map<String, dynamic>>[]).where((a) => a['account_type'] == type).toList();
        for (final r in roots) {
          addRow(r, 0);
        }
      }
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(), rows[i]]]),
    );
  }

  Widget _row(
    Map<String, dynamic> a,
    int depth,
    bool isGroup,
    bool collapsed,
    String? balanceText,
    Rows all,
    bool canCreate,
    bool canEdit,
    bool canDelete,
  ) {
    final archived = a['is_active'] != true;
    final system = a['is_system'] == true;
    final items = <PopupMenuEntry<String>>[
      if (!isGroup) const PopupMenuItem(value: 'ledger', child: Text('View ledger')),
      if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
      if (canCreate && isGroup) const PopupMenuItem(value: 'child', child: Text('Add sub-account')),
      if (canEdit) PopupMenuItem(value: 'toggle', child: Text(archived ? 'Restore' : 'Archive')),
      if (canDelete && !system) const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ];
    return InkWell(
      onTap: isGroup ? () => setState(() => collapsed ? _collapsed.remove(a['id']) : _collapsed.add(a['id'] as String)) : (canEdit ? () => _openForm(all, account: a) : null),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + depth * 22.0, 10, 4, 10),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: isGroup
                  ? Icon(collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 20, color: AppColors.textMuted)
                  : const SizedBox.shrink(),
            ),
            SizedBox(width: 56, child: Text('${a['code']}', style: AppText.small.copyWith(fontWeight: FontWeight.w600))),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${a['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: (isGroup ? AppText.bodyStrong : AppText.body).copyWith(color: archived ? AppColors.textMuted : null),
                    ),
                  ),
                  if (archived) ...[const SizedBox(width: 8), const StatusBadge('Archived')],
                ],
              ),
            ),
            if (balanceText != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text(balanceText, style: (isGroup ? AppText.bodyStrong : AppText.body).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            if (items.isEmpty)
              const SizedBox(width: 40)
            else
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                itemBuilder: (_) => items,
                onSelected: (v) {
                  if (v == 'ledger') context.go('/finance/ledger?account=${a['id']}');
                  if (v == 'edit') _openForm(all, account: a);
                  if (v == 'child') _openForm(all, parentId: a['id'] as String);
                  if (v == 'toggle') _toggleActive(a);
                  if (v == 'delete') _delete(a);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({required this.accounts, this.account, this.parentId});

  final Rows accounts;
  final Map<String, dynamic>? account;
  final String? parentId;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  final _key = GlobalKey<FormState>();
  late final _code = TextEditingController(text: '${widget.account?['code'] ?? ''}');
  late final _name = TextEditingController(text: '${widget.account?['name'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.account?['description'] ?? ''}');
  late String? _type = widget.account?['account_type'] as String? ?? _parentOf(widget.parentId)?['account_type'] as String?;
  late String? _parent = widget.account?['parent_id'] as String? ?? widget.parentId;
  late bool _isGroup = widget.account?['is_group'] == true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.account != null;

  Map<String, dynamic>? _parentOf(String? id) {
    if (id == null) return null;
    for (final a in widget.accounts) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  List<Option> get _parentOptions => [
        for (final a in widget.accounts)
          if (a['is_group'] == true && a['is_active'] == true && a['account_type'] == _type && a['id'] != widget.account?['id'])
            Option(a['id'] as String, '${a['code']}  ${a['name']}'),
      ];

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      final desc = _desc.text.trim().isEmpty ? null : _desc.text.trim();
      if (_isEdit) {
        await client.from('accounts').update({
          'code': _code.text.trim(),
          'name': _name.text.trim(),
          'parent_id': _parent,
          'description': desc,
        }).eq('id', widget.account!['id'] as Object);
      } else {
        await client.from('accounts').insert({
          'org_id': m.orgId,
          'code': _code.text.trim(),
          'name': _name.text.trim(),
          'account_type': _type,
          'parent_id': _parent,
          'is_group': _isGroup,
          'description': desc,
        });
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
    final system = widget.account?['is_system'] == true;
    return Form(
      key: _key,
      child: FormShell(
        title: _isEdit ? 'Edit account' : 'Add account',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: _isEdit ? 'Save changes' : 'Create account', loading: _saving, onPressed: _save),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<String>(
              label: 'Account type',
              required: true,
              hint: 'Select',
              value: _type,
              items: [for (final t in accountTypeOrder) DropdownMenuItem(value: t, child: Text(accountTypeLabels[t]!))],
              onChanged: (_isEdit || widget.parentId != null) ? null : (v) => setState(() {
                    _type = v;
                    _parent = null;
                  }),
              validator: (v) => v == null ? 'Choose a type' : null,
            ),
            const SizedBox(height: 16),
            SearchSelectField(
              label: 'Parent group',
              hint: 'None (top level)',
              clearable: true,
              enabled: _type != null && !system,
              options: _parentOptions,
              value: _parent,
              onChanged: (v) => setState(() => _parent = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _code,
              label: 'Account code',
              required: true,
              hint: 'For example 5410',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a code' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _name,
              label: 'Account name',
              required: true,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(controller: _desc, label: 'Description', maxLines: 3),
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              AppSwitchRow(
                label: 'Group account',
                subtitle: 'A group holds other accounts and cannot be posted to directly',
                value: _isGroup,
                onChanged: (v) => setState(() => _isGroup = v),
              ),
            ],
            if (system) ...[
              const SizedBox(height: 12),
              Text('This is a standard account. You can rename it, but its type and purpose are fixed.', style: AppText.small),
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
