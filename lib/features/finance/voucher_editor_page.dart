import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/option_sources.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/search_select.dart';
import 'finance_providers.dart';
import 'voucher_detail_page.dart';
import 'voucher_pdf.dart';

class _Line {
  _Line({this.accountId, this.partyId, String description = '', String amount = '', String debit = '', String credit = ''})
      : description = TextEditingController(text: description),
        amount = TextEditingController(text: amount),
        debit = TextEditingController(text: debit),
        credit = TextEditingController(text: credit);

  String? accountId;
  String? partyId;
  final TextEditingController description;
  final TextEditingController amount;
  final TextEditingController debit;
  final TextEditingController credit;

  void dispose() {
    description.dispose();
    amount.dispose();
    debit.dispose();
    credit.dispose();
  }
}

double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;
String _plain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

const _types = ['payment', 'receipt', 'contra', 'journal'];

/// Creates or edits a draft voucher. Payment and receipt vouchers are entered
/// the way people think about them (money out of, or into, one account);
/// journal vouchers use free debit and credit lines.
class VoucherEditorPage extends ConsumerStatefulWidget {
  const VoucherEditorPage({super.key, this.type, this.voucherId});

  final String? type;
  final String? voucherId;

  @override
  ConsumerState<VoucherEditorPage> createState() => _VoucherEditorPageState();
}

class _VoucherEditorPageState extends ConsumerState<VoucherEditorPage> {
  late final String _id = widget.voucherId ?? newUuid();
  late String _type = _types.contains(widget.type) ? widget.type! : 'payment';
  String? _date;
  String? _branch;
  String? _finId;
  String? _toFinId;
  final _reference = TextEditingController();
  final _narration = TextEditingController();
  final _contraAmount = TextEditingController();
  final List<_Line> _lines = [];
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _error;

  bool get _isEdit => widget.voucherId != null;

  @override
  void initState() {
    super.initState();
    _date = _iso(DateTime.now());
    _resetLines();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _narration.dispose();
    _contraAmount.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _resetLines() {
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll([for (var i = 0; i < (_type == 'journal' ? 2 : 1); i++) _Line()]);
  }

  Future<void> _load() async {
    try {
      final client = ref.read(supabaseProvider);
      final v = await client
          .from('vouchers')
          .select('*, voucher_lines(line_no, account_id, party_id, description, debit, credit)')
          .eq('id', _id)
          .single();
      if (v['status'] != 'draft' && v['status'] != 'rejected') {
        throw 'Only draft or rejected vouchers can be edited.';
      }
      final fin = await ref.read(financialAccountsProvider.future);
      String? finFor(Object? accountId) {
        for (final f in fin) {
          if (f['account_id'] == accountId) return f['id'] as String;
        }
        return null;
      }

      final lines = List<Map<String, dynamic>>.from(v['voucher_lines'] as List)..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));
      double d(Map<String, dynamic> l) => (l['debit'] as num).toDouble();
      double c(Map<String, dynamic> l) => (l['credit'] as num).toDouble();

      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      final type = v['voucher_type'] as String;

      if (type == 'payment' || type == 'receipt') {
        final isPay = type == 'payment';
        final finLines = lines.where((l) => (isPay ? c(l) > 0 : d(l) > 0) && finFor(l['account_id']) != null).toList();
        if (finLines.length != 1) throw 'This voucher was not created with the standard form and cannot be edited here.';
        _finId = finFor(finLines.first['account_id']);
        for (final l in lines.where((l) => l != finLines.first)) {
          _lines.add(_Line(accountId: l['account_id'] as String, partyId: l['party_id'] as String?, description: '${l['description'] ?? ''}', amount: _plain(isPay ? d(l) : c(l))));
        }
      } else if (type == 'contra') {
        final to = lines.where((l) => d(l) > 0).toList();
        final from = lines.where((l) => c(l) > 0).toList();
        if (to.length != 1 || from.length != 1 || finFor(to.first['account_id']) == null || finFor(from.first['account_id']) == null) {
          throw 'This voucher was not created with the standard form and cannot be edited here.';
        }
        _toFinId = finFor(to.first['account_id']);
        _finId = finFor(from.first['account_id']);
        _contraAmount.text = _plain(d(to.first));
        _lines.add(_Line());
      } else {
        for (final l in lines) {
          _lines.add(_Line(accountId: l['account_id'] as String, partyId: l['party_id'] as String?, description: '${l['description'] ?? ''}', debit: d(l) > 0 ? _plain(d(l)) : '', credit: c(l) > 0 ? _plain(c(l)) : ''));
        }
      }
      if (_lines.isEmpty) _lines.add(_Line());

      if (mounted) {
        setState(() {
          _type = type;
          _date = v['voucher_date'] as String;
          _branch = v['branch_id'] as String?;
          _reference.text = '${v['reference'] ?? ''}';
          _narration.text = '${v['narration'] ?? ''}';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e is String ? e : friendlyError(e);
        });
      }
    }
  }

  double get _lineTotal => _lines.fold(0, (s, l) => s + _num(l.amount));
  double get _debitTotal => _lines.fold(0, (s, l) => s + _num(l.debit));
  double get _creditTotal => _lines.fold(0, (s, l) => s + _num(l.credit));

  /// Builds the debit and credit lines sent to the database, or throws a message for the user.
  List<Map<String, dynamic>> _buildLines(Rows fin) {
    String gl(String? finId) {
      for (final f in fin) {
        if (f['id'] == finId) return f['account_id'] as String;
      }
      throw 'Choose a valid account.';
    }

    switch (_type) {
      case 'payment':
      case 'receipt':
        final isPay = _type == 'payment';
        if (_finId == null) throw isPay ? 'Choose the account the money is paid from.' : 'Choose the account the money is received in.';
        final used = _lines.where((l) => l.accountId != null || _num(l.amount) > 0).toList();
        if (used.isEmpty) throw 'Add at least one line.';
        for (final l in used) {
          if (l.accountId == null) throw 'Every line needs an account.';
          if (_num(l.amount) <= 0) throw 'Every line needs an amount greater than zero.';
        }
        final total = used.fold<double>(0, (s, l) => s + _num(l.amount));
        return [
          for (final l in used)
            {'account_id': l.accountId, 'party_id': l.partyId, 'description': l.description.text.trim(), (isPay ? 'debit' : 'credit'): _num(l.amount)},
          {'account_id': gl(_finId), 'description': _narration.text.trim(), (isPay ? 'credit' : 'debit'): total},
        ];
      case 'contra':
        if (_finId == null || _toFinId == null) throw 'Choose both accounts.';
        if (_finId == _toFinId) throw 'Choose two different accounts.';
        final amount = _num(_contraAmount);
        if (amount <= 0) throw 'Enter an amount greater than zero.';
        return [
          {'account_id': gl(_toFinId), 'debit': amount},
          {'account_id': gl(_finId), 'credit': amount},
        ];
      default:
        final rows = _lines.where((l) => l.accountId != null || _num(l.debit) > 0 || _num(l.credit) > 0).toList();
        if (rows.length < 2) throw 'A journal needs at least two lines.';
        for (final l in rows) {
          if (l.accountId == null) throw 'Every line needs an account.';
          if ((_num(l.debit) > 0) == (_num(l.credit) > 0)) throw 'Each line needs either a debit or a credit amount.';
        }
        final d = rows.fold<double>(0, (s, l) => s + _num(l.debit));
        final c = rows.fold<double>(0, (s, l) => s + _num(l.credit));
        if ((d - c).abs() > 0.004) throw 'Debits and credits must be equal. They differ by ${(d - c).abs().toStringAsFixed(2)}.';
        return [
          for (final l in rows)
            {'account_id': l.accountId, 'party_id': l.partyId, 'description': l.description.text.trim(), 'debit': _num(l.debit), 'credit': _num(l.credit)},
        ];
    }
  }

  Future<void> _save() async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() => _error = null);
    final List<Map<String, dynamic>> lines;
    try {
      lines = _buildLines(await ref.read(financialAccountsProvider.future));
    } catch (e) {
      setState(() => _error = e is String ? e : friendlyError(e));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(supabaseProvider).rpc('save_voucher', params: {
        'p_id': _id,
        'p_org': m.orgId,
        'p_type': _type,
        'p_date': _date,
        'p_narration': _narration.text.trim(),
        'p_reference': _reference.text.trim(),
        'p_branch': _branch,
        'p_lines': lines,
      });
      ref.invalidate(voucherDetailProvider);
      if (mounted) context.go('/finance/vouchers/$_id');
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
    final m = ref.watch(activeMembershipProvider);
    if (m == null || _loading) return const LoadingView();
    if (!perms.canView(Modules.finance) || !perms.can(Modules.finance, PermAction.create)) return const NoAccessView();
    if (_loadError != null) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'This voucher cannot be edited',
        message: _loadError,
        actionLabel: 'Back to voucher',
        onAction: () => context.go('/finance/vouchers/$_id'),
      );
    }

    final fin = ref.watch(financialAccountOptions).valueOrNull ?? const <Option>[];
    final accounts = ref.watch(postingAccountOptions).valueOrNull ?? const <Option>[];
    final parties = ref.watch(partyOptions).valueOrNull ?? const <Option>[];
    final branches = ref.watch(branchOptions).valueOrNull ?? const <Option>[];

    return AppPage(
      title: _isEdit ? 'Edit voucher' : 'New voucher',
      subtitle: voucherTypeLabels[_type],
      maxWidth: 1000,
      children: [
        if (!_isEdit) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: PillTabs(
              labels: const ['Payment', 'Receipt', 'Transfer', 'Journal'],
              index: _types.indexOf(_type),
              onChanged: (i) => setState(() {
                _type = _types[i];
                _finId = null;
                _toFinId = null;
                _resetLines();
              }),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          title: 'Voucher details',
          child: LayoutBuilder(
            builder: (context, cons) {
              final w = cons.maxWidth >= 640 ? (cons.maxWidth - 16) / 2 : cons.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(width: w, child: AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
                  SizedBox(width: w, child: AppTextField(controller: _reference, label: 'Reference', hint: 'Cheque, invoice or slip number')),
                  SizedBox(
                    width: w,
                    child: SearchSelectField(label: 'Branch', hint: 'Not specified', clearable: true, options: branches, value: _branch, onChanged: (v) => setState(() => _branch = v)),
                  ),
                  SizedBox(width: cons.maxWidth, child: AppTextField(controller: _narration, label: 'Narration', hint: 'What is this for?', maxLines: 2)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _body(fin, accounts, parties, m.currency),
        const SizedBox(height: 16),
        AttachmentsPanel(entityType: 'voucher', entityId: _id),
        const SizedBox(height: 16),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Row(children: [const Icon(Icons.error_outline_rounded, size: 19, color: AppColors.danger), const SizedBox(width: 10), Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13.5)))]),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => context.go(_isEdit ? '/finance/vouchers/$_id' : '/finance/vouchers')),
            const SizedBox(width: 12),
            AppButton(label: 'Save draft', loading: _saving, onPressed: _save),
          ],
        ),
      ],
    );
  }

  Widget _body(List<Option> fin, List<Option> accounts, List<Option> parties, String currency) {
    if (_type == 'contra') {
      return SectionCard(
        title: 'Transfer',
        subtitle: 'Move money between your own cash and bank accounts. Use this for deposits and withdrawals.',
        child: LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth >= 640 ? (cons.maxWidth - 16) / 2 : cons.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(width: w, child: SearchSelectField(label: 'From account', required: true, options: fin, value: _finId, onChanged: (v) => setState(() => _finId = v))),
                SizedBox(width: w, child: SearchSelectField(label: 'To account', required: true, options: fin, value: _toFinId, onChanged: (v) => setState(() => _toFinId = v))),
                SizedBox(
                  width: w,
                  child: AppTextField(controller: _contraAmount, label: 'Amount', required: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
                ),
              ],
            );
          },
        ),
      );
    }

    final isJournal = _type == 'journal';
    final isPay = _type == 'payment';
    final total = isJournal ? _debitTotal : _lineTotal;

    return SectionCard(
      title: isJournal ? 'Journal lines' : (isPay ? 'Payment' : 'Receipt'),
      subtitle: isJournal ? 'Total debits must equal total credits' : (isPay ? 'What the money was spent on' : 'Where the money came from'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isJournal) ...[
            SearchSelectField(
              label: isPay ? 'Paid from' : 'Received in',
              required: true,
              options: fin,
              value: _finId,
              onChanged: (v) => setState(() => _finId = v),
            ),
            const SizedBox(height: 18),
          ],
          for (var i = 0; i < _lines.length; i++) ...[
            _lineEditor(i, accounts, parties, isJournal, isPay),
            const SizedBox(height: 12),
          ],
          AppButton(label: 'Add line', icon: Icons.add_rounded, kind: AppButtonKind.ghost, compact: true, onPressed: () => setState(() => _lines.add(_Line()))),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          if (isJournal)
            Wrap(
              spacing: 28,
              runSpacing: 8,
              children: [
                Text('Debit ${Fmt.money(_debitTotal, currency: currency)}', style: AppText.bodyStrong),
                Text('Credit ${Fmt.money(_creditTotal, currency: currency)}', style: AppText.bodyStrong),
                Text(
                  (_debitTotal - _creditTotal).abs() < 0.005 ? 'Balanced' : 'Difference ${Fmt.money((_debitTotal - _creditTotal).abs(), currency: currency)}',
                  style: AppText.bodyStrong.copyWith(color: (_debitTotal - _creditTotal).abs() < 0.005 && total > 0 ? AppColors.success : AppColors.warning),
                ),
              ],
            )
          else
            Align(alignment: Alignment.centerRight, child: Text('Total ${Fmt.money(total, currency: currency)}', style: AppText.h3)),
        ],
      ),
    );
  }

  Widget _lineEditor(int i, List<Option> accounts, List<Option> parties, bool isJournal, bool isPay) {
    final l = _lines[i];
    final amountFields = isJournal
        ? [
            _money(l.debit, 'Debit', (v) => setState(() {
                  if (_num(l.debit) > 0) l.credit.clear();
                })),
            _money(l.credit, 'Credit', (v) => setState(() {
                  if (_num(l.credit) > 0) l.debit.clear();
                })),
          ]
        : [_money(l.amount, 'Amount', (_) => setState(() {}))];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFA), borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: AppColors.border)),
      child: LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= 720;
          final account = SearchSelectField(label: isJournal ? 'Account' : (isPay ? 'Expense or account' : 'Income or account'), required: true, options: accounts, value: l.accountId, onChanged: (v) => setState(() => l.accountId = v));
          final party = SearchSelectField(label: 'Party', hint: 'Optional', clearable: true, options: parties, value: l.partyId, onChanged: (v) => setState(() => l.partyId = v));
          final desc = AppTextField(controller: l.description, label: 'Details');
          final remove = IconButton(
            tooltip: 'Remove line',
            onPressed: _lines.length <= 1 ? null : () => setState(() => _lines.removeAt(i).dispose()),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
          );
          if (wide) {
            return Column(
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 4, child: account), const SizedBox(width: 12), Expanded(flex: 3, child: party), const SizedBox(width: 12), ...[for (final f in amountFields) ...[SizedBox(width: 130, child: f), const SizedBox(width: 12)]], remove]),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: desc), const SizedBox(width: 52)]),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              account,
              const SizedBox(height: 12),
              party,
              const SizedBox(height: 12),
              desc,
              const SizedBox(height: 12),
              Row(children: [for (final f in amountFields) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: f)), remove]),
            ],
          );
        },
      ),
    );
  }

  Widget _money(TextEditingController c, String label, ValueChanged<String> onChanged) => AppTextField(
        controller: c,
        label: label,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
      );
}
