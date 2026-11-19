import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/option_sources.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/search_select.dart';
import 'finance_providers.dart';

typedef _TKey = ({String org, String kind});

final transactionsProvider = FutureProvider.autoDispose.family<Rows, _TKey>((ref, k) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('income_expenses')
      .select('*, accounts(code, name), requester:profiles!requested_by(full_name)')
      .eq('org_id', k.org)
      .eq('kind', k.kind)
      .order('txn_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(300);
  return List<Map<String, dynamic>>.from(rows);
});

final transactionDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('income_expenses').select(
        '*, accounts(code, name), requester:profiles!requested_by(full_name), approver:profiles!approved_by(full_name), '
        'fin:financial_accounts(name), departments(name), branches(name)',
      ).eq('id', id).maybeSingle();
});

final departmentOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return const <Option>[];
  final rows = await ref.watch(supabaseProvider).from('departments').select('id, name').eq('org_id', orgId).eq('is_active', true).order('name');
  return [for (final r in rows) Option(r['id'] as String, r['name'] as String)];
});

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class IncomeExpensePage extends ConsumerStatefulWidget {
  const IncomeExpensePage({super.key, this.openId});
  final String? openId;

  @override
  ConsumerState<IncomeExpensePage> createState() => _IncomeExpensePageState();
}

class _IncomeExpensePageState extends ConsumerState<IncomeExpensePage> {
  int _tab = 0;
  String _status = '';
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (widget.openId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openDetail(widget.openId!));
  }

  @override
  void didUpdateWidget(covariant IncomeExpensePage old) {
    super.didUpdateWidget(old);
    if (widget.openId != null && widget.openId != old.openId) _openDetail(widget.openId!);
  }

  void _refresh() {
    ref.invalidate(transactionsProvider);
    ref.invalidate(transactionDetailProvider);
    ref.invalidate(balancesProvider);
  }

  Future<void> _openDetail(String id) async {
    if (!mounted) return;
    await showAdaptiveForm<void>(context, maxWidth: 680, builder: (_) => _DetailView(id: id));
    _refresh();
  }

  Future<void> _newExpense() async {
    final saved = await showAdaptiveForm<bool>(context, maxWidth: 680, builder: (_) => const _ExpenseForm());
    if (saved == true) {
      _refresh();
      if (mounted) showToast(context, 'Expense saved');
    }
  }

  Future<void> _newIncome() async {
    final saved = await showAdaptiveForm<bool>(context, maxWidth: 680, builder: (_) => const _IncomeForm());
    if (saved == true) {
      _refresh();
      if (mounted) showToast(context, 'Income recorded');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    final canIncome = perms.canView(Modules.finance);
    if (!perms.canView(Modules.expenses) && !canIncome) return const NoAccessView();

    final tab = canIncome ? _tab : 0;
    final kind = tab == 0 ? 'expense' : 'income';
    final async = ref.watch(transactionsProvider((org: m.orgId, kind: kind)));

    return AppPage(
      title: 'Income and expense',
      subtitle: 'Expense requests, approvals and income entries',
      actions: [
        if (perms.can(Modules.expenses, PermAction.create)) AppButton(label: 'New expense', icon: Icons.add_rounded, onPressed: _newExpense),
        if (perms.can(Modules.finance, PermAction.create)) AppButton(label: 'Record income', icon: Icons.south_west_rounded, kind: AppButtonKind.secondary, onPressed: _newIncome),
      ],
      children: [
        if (canIncome)
          Align(alignment: Alignment.centerLeft, child: PillTabs(labels: const ['Expenses', 'Income'], index: tab, onChanged: (i) => setState(() { _tab = i; _status = ''; }))),
        if (canIncome) const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(width: context.isMobile ? double.infinity : 320, child: AppTextField(hint: 'Search number, payee or details', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v))),
            if (tab == 0)
              SizedBox(
                width: context.isMobile ? double.infinity : 200,
                child: AppDropdown<String>(
                  value: _status,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All statuses')),
                    for (final s in const ['draft', 'pending', 'approved', 'rejected', 'paid', 'cancelled']) DropdownMenuItem(value: s, child: Text(Fmt.humanize(s))),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? ''),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(transactionsProvider)),
          data: (all) {
            final q = _search.trim().toLowerCase();
            final rows = all.where((r) {
              if (_status.isNotEmpty && r['status'] != _status) return false;
              if (q.isEmpty) return true;
              return '${r['number']} ${r['payee'] ?? ''} ${r['description'] ?? ''} ${(r['accounts'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q);
            }).toList();
            if (rows.isEmpty) {
              return AppCard(
                child: EmptyState(
                  icon: Icons.swap_vert_outlined,
                  title: all.isEmpty ? (tab == 0 ? 'No expenses yet' : 'No income recorded yet') : 'No matching entries',
                  message: all.isEmpty ? (tab == 0 ? 'Raise an expense request, attach the bill, and it goes to your approver.' : 'Record money you receive that is not a sales invoice.') : 'Try a different search or filter.',
                ),
              );
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(), _row(rows[i], m.currency, tab == 0)]]),
            );
          },
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r, String currency, bool isExpense) {
    final head = (r['accounts'] as Map?)?['name'] ?? '';
    final who = (r['requester'] as Map?)?['full_name'];
    return InkWell(
      onTap: () => _openDetail(r['id'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['number']}  $head', style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [Fmt.date(DateTime.tryParse('${r['txn_date']}')), if (r['payee'] != null) r['payee'], if (who != null) 'by $who'].join(', '),
                    style: AppText.small,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.money((r['amount'] as num).toDouble(), currency: currency), style: AppText.bodyStrong),
                const SizedBox(height: 4),
                StatusBadge.status('${r['status']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Forms

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({this.existing});
  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _key = GlobalKey<FormState>();
  late final String _id = (widget.existing?['id'] as String?) ?? newUuid();
  late final _amount = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!['amount']}');
  late final _payee = TextEditingController(text: '${widget.existing?['payee'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.existing?['description'] ?? ''}');
  late final _ref = TextEditingController(text: '${widget.existing?['reference'] ?? ''}');
  late String? _date = (widget.existing?['txn_date'] as String?) ?? _iso(DateTime.now());
  late String? _head = widget.existing?['account_id'] as String?;
  late String? _branch = widget.existing?['branch_id'] as String?;
  late String? _dept = widget.existing?['department_id'] as String?;
  String? _payFrom;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _payee, _desc, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool submit) async {
    if (!_key.currentState!.validate()) return;
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('save_expense', params: {
        'p_id': _id,
        'p_org': m.orgId,
        'p_date': _date,
        'p_account': _head,
        'p_amount': double.parse(_amount.text.trim()),
        'p_payee': _payee.text.trim(),
        'p_party': null,
        'p_description': _desc.text.trim(),
        'p_reference': _ref.text.trim(),
        'p_branch': _branch,
        'p_department': _dept,
        'p_submit': submit,
        'p_pay_from': submit ? _payFrom : null,
      });
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
    final perms = ref.watch(permsProvider);
    final canPayNow = perms.can(Modules.expenses, PermAction.approve) && perms.can(Modules.finance, PermAction.create);
    final heads = ref.watch(expenseHeadOptions).valueOrNull ?? const <Option>[];
    final fin = ref.watch(financialAccountOptions).valueOrNull ?? const <Option>[];
    final branches = ref.watch(branchOptions).valueOrNull ?? const <Option>[];
    final depts = ref.watch(departmentOptions).valueOrNull ?? const <Option>[];
    final paying = _payFrom != null;

    return Form(
      key: _key,
      child: FormShell(
        title: widget.existing == null ? 'New expense' : 'Edit expense',
        subtitle: 'Attach the bill so your approver can verify it',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Save draft', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => _save(false)),
            const SizedBox(width: 12),
            AppButton(label: paying ? 'Pay now' : 'Submit request', loading: _saving, onPressed: () => _save(true)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth >= 520 ? (cons.maxWidth - 16) / 2 : cons.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(width: w, child: AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
                    SizedBox(width: w, child: AppTextField(controller: _amount, label: 'Amount', required: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter an amount greater than zero' : null)),
                    SizedBox(width: cons.maxWidth, child: SearchSelectField(label: 'Expense head', required: true, options: heads, value: _head, onChanged: (v) => setState(() => _head = v), validator: (v) => v == null ? 'Choose an expense head' : null)),
                    SizedBox(width: w, child: AppTextField(controller: _payee, label: 'Paid to', hint: 'Shop, person or company')),
                    SizedBox(width: w, child: AppTextField(controller: _ref, label: 'Bill or reference number')),
                    SizedBox(width: w, child: SearchSelectField(label: 'Department', hint: 'Not specified', clearable: true, options: depts, value: _dept, onChanged: (v) => setState(() => _dept = v))),
                    SizedBox(width: w, child: SearchSelectField(label: 'Branch', hint: 'Not specified', clearable: true, options: branches, value: _branch, onChanged: (v) => setState(() => _branch = v))),
                    SizedBox(width: cons.maxWidth, child: AppTextField(controller: _desc, label: 'Details', maxLines: 3, hint: 'What was this for?')),
                    if (canPayNow)
                      SizedBox(
                        width: cons.maxWidth,
                        child: SearchSelectField(label: 'Pay now from', hint: 'Leave empty to send for approval', clearable: true, options: fin, value: _payFrom, onChanged: (v) => setState(() => _payFrom = v)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                AttachmentsPanel(entityType: 'expense', entityId: _id),
                if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IncomeForm extends ConsumerStatefulWidget {
  const _IncomeForm();

  @override
  ConsumerState<_IncomeForm> createState() => _IncomeFormState();
}

class _IncomeFormState extends ConsumerState<_IncomeForm> {
  final _key = GlobalKey<FormState>();
  final String _id = newUuid();
  final _amount = TextEditingController();
  final _payer = TextEditingController();
  final _desc = TextEditingController();
  final _ref = TextEditingController();
  String? _date = _iso(DateTime.now());
  String? _head;
  String? _fin;
  String? _party;
  String? _branch;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _payer, _desc, _ref]) {
      c.dispose();
    }
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
    try {
      await ref.read(supabaseProvider).rpc('record_income', params: {
        'p_id': _id,
        'p_org': m.orgId,
        'p_date': _date,
        'p_account': _head,
        'p_amount': double.parse(_amount.text.trim()),
        'p_fin': _fin,
        'p_payer': _payer.text.trim(),
        'p_party': _party,
        'p_description': _desc.text.trim(),
        'p_reference': _ref.text.trim(),
        'p_branch': _branch,
      });
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
    final heads = ref.watch(incomeHeadOptions).valueOrNull ?? const <Option>[];
    final fin = ref.watch(financialAccountOptions).valueOrNull ?? const <Option>[];
    final parties = ref.watch(partyOptions).valueOrNull ?? const <Option>[];
    final branches = ref.watch(branchOptions).valueOrNull ?? const <Option>[];
    return Form(
      key: _key,
      child: FormShell(
        title: 'Record income',
        subtitle: 'For money received that is not a sales invoice. It is posted to your books immediately.',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: 'Record income', loading: _saving, onPressed: _save),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth >= 520 ? (cons.maxWidth - 16) / 2 : cons.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(width: w, child: AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
                    SizedBox(width: w, child: AppTextField(controller: _amount, label: 'Amount', required: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter an amount greater than zero' : null)),
                    SizedBox(width: w, child: SearchSelectField(label: 'Income head', required: true, options: heads, value: _head, onChanged: (v) => setState(() => _head = v), validator: (v) => v == null ? 'Choose an income head' : null)),
                    SizedBox(width: w, child: SearchSelectField(label: 'Received in', required: true, options: fin, value: _fin, onChanged: (v) => setState(() => _fin = v), validator: (v) => v == null ? 'Choose an account' : null)),
                    SizedBox(width: w, child: AppTextField(controller: _payer, label: 'Received from')),
                    SizedBox(width: w, child: SearchSelectField(label: 'Party', hint: 'Optional', clearable: true, options: parties, value: _party, onChanged: (v) => setState(() => _party = v))),
                    SizedBox(width: w, child: AppTextField(controller: _ref, label: 'Reference')),
                    SizedBox(width: w, child: SearchSelectField(label: 'Branch', hint: 'Not specified', clearable: true, options: branches, value: _branch, onChanged: (v) => setState(() => _branch = v))),
                    SizedBox(width: cons.maxWidth, child: AppTextField(controller: _desc, label: 'Details', maxLines: 3)),
                  ],
                ),
                const SizedBox(height: 18),
                AttachmentsPanel(entityType: 'income', entityId: _id),
                if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Detail

class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({required this.id});
  final String id;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  bool _busy = false;

  Future<void> _run(Future<dynamic> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(transactionDetailProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(balancesProvider);
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rpc(String fn, [Map<String, dynamic> extra = const {}]) =>
      ref.read(supabaseProvider).rpc(fn, params: {'p_id': widget.id, ...extra});

  Future<void> _reject() async {
    final reason = await promptDialog(context, title: 'Reject expense', label: 'Reason', confirmLabel: 'Reject', message: 'The requester will see this reason.', danger: true);
    if (reason == null) return;
    await _run(() => _rpc('reject_expense', {'p_reason': reason}), 'Expense rejected');
  }

  Future<void> _cancel(bool posted) async {
    final reason = await promptDialog(
      context,
      title: posted ? 'Cancel posted entry' : 'Cancel entry',
      label: 'Reason',
      confirmLabel: 'Cancel entry',
      required: posted,
      message: posted ? 'The entry is reversed in your books with an equal and opposite voucher.' : null,
      danger: true,
    );
    if (reason == null) return;
    await _run(() => _rpc('cancel_transaction', {'p_reason': reason}), 'Entry cancelled');
  }

  Future<void> _pay() async {
    final paid = await showAdaptiveForm<bool>(context, builder: (_) => _PayForm(id: widget.id));
    if (paid == true) {
      ref.invalidate(transactionDetailProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(balancesProvider);
      if (mounted) showToast(context, 'Payment recorded');
    }
  }

  Future<void> _edit(Map<String, dynamic> t) async {
    final saved = await showAdaptiveForm<bool>(context, maxWidth: 680, builder: (_) => _ExpenseForm(existing: t));
    if (saved == true) {
      ref.invalidate(transactionDetailProvider);
      ref.invalidate(transactionsProvider);
    }
  }

  Widget _info(String label, String value) => SizedBox(
        width: 190,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.small), const SizedBox(height: 2), Text(value, style: AppText.bodyStrong)]),
      );

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final me = ref.watch(currentUserIdProvider);
    final m = ref.watch(activeMembershipProvider);
    final async = ref.watch(transactionDetailProvider(widget.id));

    return async.when(
      loading: () => const SizedBox(height: 200, child: LoadingView()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: ErrorView(message: friendlyError(e))),
      data: (t) {
        if (t == null) return const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.search_off_rounded, title: 'Entry not found'));
        final isExpense = t['kind'] == 'expense';
        final status = '${t['status']}';
        final mine = t['requested_by'] == me;
        final canApprove = perms.can(Modules.expenses, PermAction.approve);
        final canPay = perms.can(Modules.finance, PermAction.create);
        final canReverse = perms.can(Modules.finance, PermAction.approve);
        final currency = m?.currency ?? 'BDT';
        String who(String k) => ((t[k] as Map?)?['full_name'] as String?) ?? '--';

        return FormShell(
          title: '${t['number']}',
          subtitle: isExpense ? 'Expense' : 'Income',
          footer: Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (isExpense && mine && (status == 'draft' || status == 'rejected')) AppButton(label: 'Edit and resubmit', kind: AppButtonKind.secondary, onPressed: _busy ? null : () => _edit(t)),
              if (isExpense && status == 'pending' && canApprove) AppButton(label: 'Approve', loading: _busy, onPressed: () => _run(() => _rpc('approve_expense'), 'Expense approved')),
              if (isExpense && status == 'pending' && canApprove) AppButton(label: 'Reject', kind: AppButtonKind.danger, onPressed: _busy ? null : _reject),
              if (isExpense && status == 'approved' && canPay) AppButton(label: 'Record payment', onPressed: _busy ? null : _pay),
              if (isExpense && (status == 'draft' || status == 'pending' || status == 'rejected' || status == 'approved') && (mine || canApprove))
                AppButton(label: 'Cancel request', kind: AppButtonKind.ghost, onPressed: _busy ? null : () => _cancel(false)),
              if ((status == 'paid' || status == 'received') && canReverse) AppButton(label: 'Cancel entry', kind: AppButtonKind.ghost, onPressed: _busy ? null : () => _cancel(true)),
              if (t['voucher_id'] != null)
                AppButton(
                  label: 'View voucher',
                  kind: AppButtonKind.secondary,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/finance/vouchers/${t['voucher_id']}');
                  },
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [StatusBadge.status(status), const Spacer(), Text(Fmt.money((t['amount'] as num).toDouble(), currency: currency), style: AppText.kpi)]),
              const SizedBox(height: 18),
              if (status == 'rejected' && t['rejection_reason'] != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Text('Rejected: ${t['rejection_reason']}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              Wrap(
                spacing: 20,
                runSpacing: 14,
                children: [
                  _info('Date', Fmt.date(DateTime.tryParse('${t['txn_date']}'))),
                  _info(isExpense ? 'Expense head' : 'Income head', '${(t['accounts'] as Map?)?['name'] ?? '--'}'),
                  _info(isExpense ? 'Paid to' : 'Received from', '${t['payee'] ?? '--'}'),
                  _info('Reference', '${t['reference'] ?? '--'}'),
                  _info('Department', '${(t['departments'] as Map?)?['name'] ?? '--'}'),
                  _info('Branch', '${(t['branches'] as Map?)?['name'] ?? '--'}'),
                  _info(isExpense ? 'Requested by' : 'Recorded by', who('requester')),
                  if (t['approved_at'] != null) _info('Approved by', '${who('approver')}, ${Fmt.date(Fmt.parse(t['approved_at'] as String?))}'),
                  if (t['fin'] != null) _info(isExpense ? 'Paid from' : 'Received in', '${(t['fin'] as Map)['name']}'),
                ],
              ),
              if (t['description'] != null) ...[
                const SizedBox(height: 16),
                Text('Details', style: AppText.small),
                const SizedBox(height: 2),
                Text('${t['description']}', style: AppText.body),
              ],
              const SizedBox(height: 18),
              AttachmentsPanel(
                entityType: isExpense ? 'expense' : 'income',
                entityId: widget.id,
                canUpload: (mine && (status == 'draft' || status == 'rejected' || status == 'pending')) || canPay,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PayForm extends ConsumerStatefulWidget {
  const _PayForm({required this.id});
  final String id;

  @override
  ConsumerState<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends ConsumerState<_PayForm> {
  String? _fin;
  String? _date = _iso(DateTime.now());
  bool _saving = false;
  String? _error;

  Future<void> _pay() async {
    if (_fin == null) {
      setState(() => _error = 'Choose the account the payment is made from.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('pay_expense', params: {'p_id': widget.id, 'p_fin': _fin, 'p_date': _date});
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
    final fin = ref.watch(financialAccountOptions).valueOrNull ?? const <Option>[];
    return FormShell(
      title: 'Record payment',
      subtitle: 'The payment is posted to your books immediately',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
          AppButton(label: 'Pay', loading: _saving, onPressed: _pay),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchSelectField(label: 'Pay from', required: true, options: fin, value: _fin, onChanged: (v) => setState(() => _fin = v)),
          const SizedBox(height: 16),
          AppDateField(label: 'Payment date', value: _date, onChanged: (v) => setState(() => _date = v)),
          if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))],
        ],
      ),
    );
  }
}
