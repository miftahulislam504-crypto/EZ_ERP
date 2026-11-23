import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/stat_card.dart';
import 'opening_balance_dialog.dart';
import 'payment_access.dart';
import 'payment_models.dart';
import 'payment_providers.dart';
import 'record_payment_dialog.dart';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Receivables (what customers owe) or Payables (what you owe suppliers):
/// aging by party, and the receipts or payments recorded against them.
class PartyLedgerPage extends ConsumerStatefulWidget {
  const PartyLedgerPage({super.key, required this.side});

  final LedgerSide side;

  @override
  ConsumerState<PartyLedgerPage> createState() => _PartyLedgerPageState();
}

class _PartyLedgerPageState extends ConsumerState<PartyLedgerPage> {
  int _tab = 0;
  String _asOf = _iso(DateTime.now());
  String _search = '';

  LedgerSide get side => widget.side;

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!canViewLedger(perms, side)) return const NoAccessView();
    final canRecord = canRecordPayment(perms, side);
    final canOpening = canEnterOpening(perms);

    return AppPage(
      title: side.title,
      subtitle: side.isReceivable
          ? 'What customers owe you, how overdue it is, and the receipts you have recorded.'
          : 'What you owe suppliers, how overdue it is, and the payments you have made.',
      actions: [
        if (canRecord) AppButton(label: side.recordLabel, icon: Icons.add_rounded, onPressed: () => showRecordPayment(context, side: side)),
        if (canOpening) AppButton(label: 'Add opening balance', icon: Icons.history_rounded, kind: AppButtonKind.secondary, onPressed: () => showOpeningBalance(context, side: side)),
      ],
      children: [
        PillTabs(labels: ['Aging', side.paymentsTabLabel], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        const SizedBox(height: 16),
        if (_tab == 0) _aging(m.orgId, m.currency, perms) else _payments(m.orgId, m.currency),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Aging
  // ---------------------------------------------------------------------
  Widget _aging(String org, String currency, PermissionSet perms) {
    final async = ref.watch(agingProvider((org: org, side: side.key, asOf: _asOf)));
    final control = perms.canView(Modules.finance) ? ref.watch(controlCheckProvider(org)).valueOrNull : null;

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(agingProvider)),
      data: (all) {
        final q = _search.trim().toLowerCase();
        final rows = all.where((r) => q.isEmpty || '${r['party_name']} ${r['party_code']}'.toLowerCase().contains(q)).toList();
        double sum(String key) => all.fold<double>(0, (s, r) => s + _n(r[key]));
        final totalDue = sum('total_due');
        final overdue = sum('overdue_total');
        final advance = sum('advance');
        final owing = all.where((r) => _n(r['total_due']) > 0).length;

        String? controlNote;
        if (control != null && _asOf == _iso(DateTime.now())) {
          for (final c in control) {
            if (c['side'] != side.key) continue;
            final openDiff = _n(c['ledger_open']) - _n(c['documents_open']);
            final advDiff = _n(c['ledger_advance']) - _n(c['advances_open']);
            if (openDiff.abs() > 0.004 || advDiff.abs() > 0.004) {
              controlNote = 'The ledger control account differs from the open documents by ${Fmt.money(openDiff.abs() > 0.004 ? openDiff : advDiff, currency: currency)}. '
                  'This usually means a manual journal was posted straight to the control account.';
            }
          }
        }

        final cards = <Widget>[
          StatCard(label: side.isReceivable ? 'Total receivable' : 'Total payable', value: Fmt.money(totalDue, currency: currency), icon: Icons.account_balance_wallet_outlined),
          StatCard(label: 'Overdue', value: Fmt.money(overdue, currency: currency), icon: Icons.event_busy_outlined, tone: overdue > 0 ? BadgeTone.danger : BadgeTone.neutral, hint: 'Past the due date'),
          StatCard(label: side.advanceLabel == 'Customer advance' ? 'Customer advances' : 'Advances to suppliers', value: Fmt.money(advance, currency: currency), icon: Icons.savings_outlined, tone: BadgeTone.info, hint: 'Received or paid, not yet applied'),
          StatCard(label: side.isReceivable ? 'Customers owing' : 'Suppliers owed', value: '$owing', icon: Icons.groups_2_outlined, tone: BadgeTone.primary),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
                final w = (c.maxWidth - (cols - 1) * 14) / cols;
                return Wrap(spacing: 14, runSpacing: 14, children: [for (final s in cards) SizedBox(width: w, child: s)]);
              },
            ),
            if (controlNote != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 19, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(controlNote, style: const TextStyle(color: AppColors.warning, fontSize: 13.5, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(width: context.isMobile ? double.infinity : 360, child: AppTextField(hint: 'Search ${side.partyLabel.toLowerCase()}', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v))),
                SizedBox(width: context.isMobile ? double.infinity : 220, child: AppDateField(label: 'As of', value: _asOf, onChanged: (v) => setState(() => _asOf = v ?? _asOf))),
              ],
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: all.isEmpty ? 'Nothing is owed' : 'Nothing matches',
                  message: all.isEmpty
                      ? (side.isReceivable ? 'Posted invoices that customers have not paid appear here, grouped by how overdue they are.' : 'Posted bills that you have not paid appear here, grouped by how overdue they are.')
                      : 'Try a different search.',
                ),
              )
            else if (context.isMobile)
              Column(children: [for (final r in rows) _agingCard(r, currency)])
            else
              _agingTable(rows, currency, all),
          ],
        );
      },
    );
  }

  Widget _agingTable(List<Map<String, dynamic>> rows, String currency, List<Map<String, dynamic>> all) {
    Widget head(String text, int flex, {bool right = false}) =>
        Expanded(flex: flex, child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    String cell(Object? v) => _n(v) == 0 ? '--' : Fmt.money(_n(v), currency: currency);
    Widget amount(Object? v, int flex, {bool strong = false, Color? color}) => Expanded(
          flex: flex,
          child: Text(cell(v), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: (strong ? AppText.bodyStrong : AppText.body).copyWith(color: color)),
        );
    double sum(String key) => all.fold<double>(0, (s, r) => s + _n(r[key]));

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              head(side.partyLabel, 4),
              for (final b in agingBuckets) head(agingBucketLabels[b]!, 2, right: true),
              head('Total due', 2, right: true),
              head('Advance', 2, right: true),
            ]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go(side.profilePath('${r['party_id']}')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Expanded(
                    flex: 4,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['party_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                      Text('${r['party_code'] ?? ''}${_n(r['credit_limit']) > 0 && side.isReceivable ? '   Limit ${Fmt.money(_n(r['credit_limit']), currency: currency)}' : ''}', style: AppText.small),
                    ]),
                  ),
                  amount(r['current_amt'], 2),
                  amount(r['d1_30'], 2),
                  amount(r['d31_60'], 2, color: _n(r['d31_60']) > 0 ? AppColors.warning : null),
                  amount(r['d61_90'], 2, color: _n(r['d61_90']) > 0 ? AppColors.danger : null),
                  amount(r['over_90'], 2, color: _n(r['over_90']) > 0 ? AppColors.danger : null),
                  amount(r['total_due'], 2, strong: true),
                  amount(r['advance'], 2, color: _n(r['advance']) > 0 ? AppColors.info : null),
                ]),
              ),
            ),
          ],
          const Divider(),
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              Expanded(flex: 4, child: Text('Total', style: AppText.bodyStrong)),
              amount(sum('current_amt'), 2, strong: true),
              amount(sum('d1_30'), 2, strong: true),
              amount(sum('d31_60'), 2, strong: true),
              amount(sum('d61_90'), 2, strong: true),
              amount(sum('over_90'), 2, strong: true),
              amount(sum('total_due'), 2, strong: true),
              amount(sum('advance'), 2, strong: true),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _agingCard(Map<String, dynamic> r, String currency) {
    final overdue = _n(r['overdue_total']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go(side.profilePath('${r['party_id']}')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('${r['party_name']}', style: AppText.bodyStrong)),
              Text(Fmt.money(_n(r['total_due']), currency: currency), style: AppText.label),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 14, children: [
              if (overdue > 0) Text('Overdue ${Fmt.money(overdue, currency: currency)}', style: AppText.small.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600)),
              if (_n(r['over_90']) > 0) Text('Over 90 days ${Fmt.money(_n(r['over_90']), currency: currency)}', style: AppText.small.copyWith(color: AppColors.danger)),
              if (_n(r['advance']) > 0) Text('Advance ${Fmt.money(_n(r['advance']), currency: currency)}', style: AppText.small.copyWith(color: AppColors.info)),
            ]),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Receipts or payments
  // ---------------------------------------------------------------------
  Widget _payments(String org, String currency) {
    final async = ref.watch(paymentsListProvider((org: org, kind: side.paymentKind, party: null)));
    final balances = ref.watch(paymentBalancesProvider((org: org, kind: side.paymentKind))).valueOrNull ?? const <String, ({double allocated, double unallocated})>{};
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(paymentsListProvider)),
      data: (all) {
        final q = _search.trim().toLowerCase();
        final rows = all.where((r) {
          if (q.isEmpty) return true;
          return '${r['number']} ${r['reference'] ?? ''} ${(r['party'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(q);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: context.isMobile ? double.infinity : 360, child: AppTextField(hint: 'Search number, reference or ${side.partyLabel.toLowerCase()}', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v))),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              AppCard(child: EmptyState(icon: Icons.payments_outlined, title: all.isEmpty ? 'No ${side.paymentsTabLabel.toLowerCase()} yet' : 'Nothing matches', message: all.isEmpty ? 'Use ${side.recordLabel} to record money ${side.isReceivable ? 'received' : 'paid'}.' : 'Try a different search.'))
            else if (context.isMobile)
              Column(children: [for (final r in rows) _paymentCard(r, balances, currency)])
            else
              _paymentTable(rows, balances, currency),
          ],
        );
      },
    );
  }

  Widget _paymentTable(List<Map<String, dynamic>> rows, Map<String, ({double allocated, double unallocated})> balances, String currency) {
    Widget head(String text, int flex, {bool right = false}) =>
        Expanded(flex: flex, child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Number', 2), head('Date', 2), head(side.partyLabel, 4), head(side.isReceivable ? 'Deposited to' : 'Paid from', 3), head('Reference', 3), head('Amount', 2, right: true), head('Unapplied', 2, right: true), const SizedBox(width: 20), head('Status', 2)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go(side.paymentPath('${r['id']}')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Expanded(flex: 2, child: Text('${r['number']}', style: AppText.bodyStrong)),
                  Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['pay_date']}')), style: AppText.body)),
                  Expanded(flex: 4, child: Text('${(r['party'] as Map?)?['name'] ?? '--'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                  Expanded(flex: 3, child: Text('${(r['account'] as Map?)?['name'] ?? '--'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                  Expanded(flex: 3, child: Text('${r['reference'] ?? '--'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                  Expanded(flex: 2, child: Text(Fmt.money(_n(r['amount']), currency: currency), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (balances['${r['id']}']?.unallocated ?? 0) > 0 ? Fmt.money(balances['${r['id']}']!.unallocated, currency: currency) : '--',
                      textAlign: TextAlign.right,
                      style: AppText.body.copyWith(color: (balances['${r['id']}']?.unallocated ?? 0) > 0 ? AppColors.info : AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: StatusBadge.status('${r['status']}'))),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> r, Map<String, ({double allocated, double unallocated})> balances, String currency) {
    final unapplied = balances['${r['id']}']?.unallocated ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go(side.paymentPath('${r['id']}')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text('${r['number']}', style: AppText.bodyStrong)), StatusBadge.status('${r['status']}')]),
            const SizedBox(height: 2),
            Text('${(r['party'] as Map?)?['name'] ?? '--'}, ${Fmt.date(DateTime.tryParse('${r['pay_date']}'))}', style: AppText.small),
            const SizedBox(height: 6),
            Text(Fmt.money(_n(r['amount']), currency: currency), style: AppText.label),
            if (unapplied > 0) Text('${Fmt.money(unapplied, currency: currency)} unapplied', style: AppText.small.copyWith(color: AppColors.info)),
          ],
        ),
      ),
    );
  }
}
