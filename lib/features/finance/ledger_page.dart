import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/search_select.dart';
import 'finance_providers.dart';

typedef _LedgerKey = ({String org, String account, String from, String to});

final _ledgerProvider = FutureProvider.autoDispose.family<Rows, _LedgerKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('account_ledger', params: {
    'p_org': k.org,
    'p_account': k.account,
    'p_from': k.from,
    'p_to': k.to,
  });
  return List<Map<String, dynamic>>.from(rows as List);
});

/// Account ledger. For cash and bank accounts it is the cashbook or bankbook.
class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key, this.accountId});
  final String? accountId;

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  static const _presets = ['This month', 'Last month', 'This financial year', 'All time', 'Custom'];
  String? _account;
  int _preset = 0;
  DateTimeRange? _custom;

  @override
  void initState() {
    super.initState();
    _account = widget.accountId;
  }

  @override
  void didUpdateWidget(covariant LedgerPage old) {
    super.didUpdateWidget(old);
    if (widget.accountId != old.accountId && widget.accountId != null) _account = widget.accountId;
  }

  DateTimeRange _range(int fiscalStart) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case 1:
        return DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0));
      case 2:
        final startYear = now.month >= fiscalStart ? now.year : now.year - 1;
        return DateTimeRange(start: DateTime(startYear, fiscalStart, 1), end: today);
      case 3:
        return DateTimeRange(start: DateTime(2000), end: today);
      case 4:
        return _custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      default:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
    }
  }

  Future<void> _onPreset(int i) async {
    if (i == 4) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _custom,
      );
      if (picked == null) return;
      setState(() {
        _custom = picked;
        _preset = 4;
      });
      return;
    }
    setState(() => _preset = i);
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.finance)) return const NoAccessView();

    final options = ref.watch(postingAccountOptions).valueOrNull ?? const [];
    final fin = ref.watch(financialAccountsProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    _account ??= fin.isNotEmpty ? fin.first['account_id'] as String : null;

    final finMatch = fin.where((f) => f['account_id'] == _account).toList();
    final kind = finMatch.isEmpty ? null : finMatch.first['kind'] as String;
    final title = switch (kind) { 'cash' => 'Cashbook', 'bank' => 'Bankbook', 'mobile_wallet' => 'Wallet book', _ => 'Account ledger' };
    final debitLabel = kind == null ? 'Debit' : 'Received';
    final creditLabel = kind == null ? 'Credit' : 'Paid';
    final range = _range(m.fiscalStartMonth);
    final fmt = DateFormat('yyyy-MM-dd');

    return AppPage(
      title: title,
      subtitle: '${Fmt.date(range.start)} to ${Fmt.date(range.end)}',
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: context.isMobile ? double.infinity : 360,
              child: SearchSelectField(
                label: 'Account',
                options: options,
                value: _account,
                onChanged: (v) => setState(() => _account = v),
              ),
            ),
            PillTabs(labels: _presets, index: _preset, onChanged: _onPreset),
          ],
        ),
        const SizedBox(height: 18),
        if (_account == null)
          const AppCard(child: EmptyState(icon: Icons.menu_book_outlined, title: 'Choose an account', message: 'Pick an account to see its ledger.'))
        else
          ref.watch(_ledgerProvider((org: m.orgId, account: _account!, from: fmt.format(range.start), to: fmt.format(range.end)))).when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_ledgerProvider)),
                data: (rows) => _body(rows, m.currency, debitLabel, creditLabel),
              ),
      ],
    );
  }

  Widget _body(Rows rows, String currency, String debitLabel, String creditLabel) {
    double num0(Object? v) => (v as num?)?.toDouble() ?? 0;
    final opening = rows.isEmpty ? 0.0 : num0(rows.first['balance']);
    final entries = rows.where((r) => r['row_type'] == 'entry').toList();
    final debit = entries.fold<double>(0, (s, r) => s + num0(r['debit']));
    final credit = entries.fold<double>(0, (s, r) => s + num0(r['credit']));
    final closing = entries.isEmpty ? opening : num0(entries.last['balance']);
    String money(double v) => Fmt.money(v, currency: currency);

    Widget summary(String label, String value) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.small),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppText.h3)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              summary('Opening balance', money(opening)),
              summary(debitLabel, money(debit)),
              summary(creditLabel, money(credit)),
              summary('Closing balance', money(closing)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          const AppCard(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions in this period'))
        else if (context.isMobile)
          Column(children: [for (final r in entries) _mobileRow(r, currency, debitLabel, creditLabel)])
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  color: const Color(0xFFF7F9F8),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _cell('Date', 2, header: true),
                      _cell('Voucher', 2, header: true),
                      _cell('Details', 5, header: true),
                      _cell(debitLabel, 2, header: true, right: true),
                      _cell(creditLabel, 2, header: true, right: true),
                      _cell('Balance', 2, header: true, right: true),
                    ],
                  ),
                ),
                for (final r in entries) ...[
                  const Divider(),
                  InkWell(
                    onTap: () => context.go('/finance/vouchers/${r['voucher_id']}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          _cell(Fmt.date(DateTime.tryParse('${r['entry_date']}')), 2),
                          _cell('${r['voucher_no']}', 2, strong: true),
                          _cell([if (r['narration'] != null) r['narration'], if (r['party_name'] != null) '(${r['party_name']})'].join(' '), 5),
                          _cell(num0(r['debit']) == 0 ? '' : money(num0(r['debit'])), 2, right: true),
                          _cell(num0(r['credit']) == 0 ? '' : money(num0(r['credit'])), 2, right: true),
                          _cell(money(num0(r['balance'])), 2, right: true, strong: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(String text, int flex, {bool header = false, bool right = false, bool strong = false}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: header ? AppText.small.copyWith(fontWeight: FontWeight.w600) : (strong ? AppText.bodyStrong : AppText.body),
        ),
      ),
    );
  }

  Widget _mobileRow(Map<String, dynamic> r, String currency, String debitLabel, String creditLabel) {
    final d = (r['debit'] as num?)?.toDouble() ?? 0;
    final c = (r['credit'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go('/finance/vouchers/${r['voucher_id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${r['voucher_no']}', style: AppText.bodyStrong)),
                Text(Fmt.date(DateTime.tryParse('${r['entry_date']}')), style: AppText.small),
              ],
            ),
            if (r['narration'] != null) Text('${r['narration']}', style: AppText.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(d > 0 ? '$debitLabel ${Fmt.money(d, currency: currency)}' : '$creditLabel ${Fmt.money(c, currency: currency)}', style: AppText.label)),
                Text('Balance ${Fmt.money((r['balance'] as num).toDouble(), currency: currency)}', style: AppText.small),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
