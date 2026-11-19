import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../shared/widgets/feedback.dart';
import 'finance_providers.dart';

const _kindLabels = {'cash': 'Cash', 'bank': 'Bank account', 'mobile_wallet': 'Mobile wallet'};
const _bookLabels = {'cash': 'Cashbook', 'bank': 'Bankbook', 'mobile_wallet': 'Wallet book'};

IconData _kindIcon(String kind) => switch (kind) {
      'bank' => Icons.account_balance_outlined,
      'mobile_wallet' => Icons.smartphone_outlined,
      _ => Icons.payments_outlined,
    };

String _masked(String? number) {
  if (number == null || number.isEmpty) return '';
  final tail = number.length <= 4 ? number : number.substring(number.length - 4);
  return 'ending $tail';
}

class CashBankPage extends ConsumerWidget {
  const CashBankPage({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, [Map<String, dynamic>? account]) async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => _FinAccountForm(account: account));
    if (saved == true) {
      ref.invalidate(financialAccountsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(balancesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.finance)) return const NoAccessView();
    final canCreate = perms.can(Modules.finance, PermAction.create);
    final canEdit = perms.can(Modules.finance, PermAction.edit);
    final showMoney = perms.canView(Modules.financialData);

    final async = ref.watch(financialAccountsProvider);
    final balances = showMoney ? ref.watch(balancesProvider).valueOrNull : null;

    double balanceOf(Map<String, dynamic> a) {
      final b = balances?[a['account_id']];
      return b == null ? 0 : b.debit - b.credit;
    }

    return AppPage(
      title: 'Cash and bank',
      subtitle: 'Where your money is, and how it moves',
      actions: [
        if (canCreate) ...[
          AppButton(label: 'Receive money', icon: Icons.south_west_rounded, kind: AppButtonKind.secondary, onPressed: () => context.go('/finance/vouchers/new?type=receipt')),
          AppButton(label: 'Pay money', icon: Icons.north_east_rounded, kind: AppButtonKind.secondary, onPressed: () => context.go('/finance/vouchers/new?type=payment')),
          AppButton(label: 'Transfer', icon: Icons.swap_horiz_rounded, kind: AppButtonKind.secondary, onPressed: () => context.go('/finance/vouchers/new?type=contra')),
          AppButton(label: 'Add account', icon: Icons.add_rounded, onPressed: () => _openForm(context, ref)),
        ],
      ],
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(financialAccountsProvider)),
          data: (rows) {
            final active = rows.where((a) => a['is_active'] == true).toList();
            final total = active.fold<double>(0, (s, a) => s + balanceOf(a));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMoney)
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total across ${active.length} ${active.length == 1 ? 'account' : 'accounts'}', style: AppText.small),
                            Text(Fmt.money(total, currency: m.currency), style: AppText.kpi),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (showMoney) const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, cons) {
                    final cols = cons.maxWidth >= 980 ? 3 : (cons.maxWidth >= 620 ? 2 : 1);
                    const gap = 14.0;
                    final w = (cons.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final a in rows)
                          SizedBox(
                            width: w,
                            child: _AccountCard(
                              account: a,
                              balance: showMoney ? Fmt.money(balanceOf(a), currency: m.currency) : null,
                              onBook: () => context.go('/finance/ledger?account=${a['account_id']}'),
                              onEdit: canEdit ? () => _openForm(context, ref, a) : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.balance, required this.onBook, this.onEdit});

  final Map<String, dynamic> account;
  final String? balance;
  final VoidCallback onBook;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final kind = '${account['kind']}';
    final archived = account['is_active'] != true;
    final detail = [
      if ((account['bank_name'] as String?)?.isNotEmpty == true) account['bank_name'],
      if (_masked(account['account_number'] as String?).isNotEmpty) _masked(account['account_number'] as String?),
    ].join(', ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(_kindIcon(kind), size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${account['name']}', style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(detail.isEmpty ? _kindLabels[kind] ?? '' : detail, style: AppText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (archived) const StatusBadge('Archived'),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (balance != null) FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(balance!, style: AppText.kpi)),
          if (balance != null) const SizedBox(height: 4),
          if (balance != null) Text('Current balance', style: AppText.small),
          const SizedBox(height: 14),
          AppButton(label: _bookLabels[kind] ?? 'Ledger', icon: Icons.menu_book_outlined, kind: AppButtonKind.secondary, compact: true, onPressed: onBook),
        ],
      ),
    );
  }
}

class _FinAccountForm extends ConsumerStatefulWidget {
  const _FinAccountForm({this.account});
  final Map<String, dynamic>? account;

  @override
  ConsumerState<_FinAccountForm> createState() => _FinAccountFormState();
}

class _FinAccountFormState extends ConsumerState<_FinAccountForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${widget.account?['name'] ?? ''}');
  late final _bank = TextEditingController(text: '${widget.account?['bank_name'] ?? ''}');
  late final _branch = TextEditingController(text: '${widget.account?['branch_name'] ?? ''}');
  late final _number = TextEditingController(text: '${widget.account?['account_number'] ?? ''}');
  final _opening = TextEditingController(text: '0');
  late String _kind = widget.account?['kind'] as String? ?? 'bank';
  late bool _active = widget.account?['is_active'] != false;
  String? _openingDate;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.account != null;

  @override
  void dispose() {
    for (final c in [_name, _bank, _branch, _number, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nullable(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

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
      if (_isEdit) {
        await client.from('financial_accounts').update({
          'name': _name.text.trim(),
          'bank_name': _nullable(_bank),
          'branch_name': _nullable(_branch),
          'account_number': _nullable(_number),
          'is_active': _active,
        }).eq('id', widget.account!['id'] as Object);
        await client.from('accounts').update({'name': _name.text.trim(), 'is_active': _active}).eq('id', widget.account!['account_id'] as Object);
      } else {
        await client.rpc('create_financial_account', params: {
          'p_org': m.orgId,
          'p_kind': _kind,
          'p_name': _name.text.trim(),
          'p_bank_name': _nullable(_bank),
          'p_branch_name': _nullable(_branch),
          'p_account_number': _nullable(_number),
          'p_opening_balance': num.tryParse(_opening.text.trim()) ?? 0,
          'p_opening_date': _openingDate,
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
    return Form(
      key: _key,
      child: FormShell(
        title: _isEdit ? 'Edit account' : 'Add cash or bank account',
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
              label: 'Type',
              required: true,
              value: _kind,
              items: [for (final e in _kindLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: _isEdit ? null : (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _name,
              label: 'Account name',
              required: true,
              hint: 'For example City Bank current account',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            if (_kind != 'cash') ...[
              const SizedBox(height: 16),
              AppTextField(controller: _bank, label: _kind == 'bank' ? 'Bank name' : 'Provider'),
              if (_kind == 'bank') ...[
                const SizedBox(height: 16),
                AppTextField(controller: _branch, label: 'Branch'),
              ],
              const SizedBox(height: 16),
              AppTextField(controller: _number, label: _kind == 'bank' ? 'Account number' : 'Wallet number'),
            ],
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              AppTextField(
                controller: _opening,
                label: 'Opening balance',
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                hint: 'Balance when you start using EZ ERP',
                validator: (v) => (v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) ? 'Enter a valid number' : null,
              ),
              const SizedBox(height: 16),
              AppDateField(label: 'Opening balance date', value: _openingDate, onChanged: (v) => setState(() => _openingDate = v)),
            ] else ...[
              const SizedBox(height: 16),
              AppSwitchRow(label: 'Active', subtitle: 'Archived accounts are not offered for new entries', value: _active, onChanged: (v) => setState(() => _active = v)),
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
