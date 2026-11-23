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
import '../payments/payment_models.dart';
import '../payments/payment_providers.dart';
import 'trade_models.dart';
import 'trade_providers.dart';

/// List of one kind of document: purchase requisitions, orders, receipts and bills, or sales quotations, orders and invoices.
class TradeListPage extends ConsumerStatefulWidget {
  const TradeListPage({super.key, required this.type});

  final TradeType type;

  @override
  ConsumerState<TradeListPage> createState() => _TradeListPageState();
}

class _TradeListPageState extends ConsumerState<TradeListPage> {
  int _filter = 0;
  String _search = '';

  TradeType get t => widget.type;

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!t.canView(perms)) return const NoAccessView();
    final canCreate = t.can(perms, PermAction.create);
    final async = ref.watch(tradeListProvider((org: m.orgId, type: t.key)));
    final money = t.hasPrices || t.isReceipt;
    // Paid amount and balance of posted invoices and bills.
    final balances = t.hasPayments
        ? (ref.watch(documentBalancesProvider((org: m.orgId, type: t.key))).valueOrNull ?? const <String, Map<String, dynamic>>{})
        : const <String, Map<String, dynamic>>{};

    return AppPage(
      title: t.plural,
      subtitle: t.subtitle,
      actions: [
        if (canCreate) AppButton(label: 'New ${t.label.toLowerCase()}', icon: Icons.add_rounded, onPressed: () => context.go(t.newPath)),
      ],
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(tradeListProvider)),
          data: (all) {
            final statuses = t.filters[_filter].statuses;
            final payState = t.filters[_filter].paymentState;
            final q = _search.trim().toLowerCase();
            final rows = all.where((r) {
              if (statuses.isNotEmpty && !statuses.contains(r['status'])) return false;
              if (payState != null) {
                final b = balances['${r['id']}'];
                if (b == null || ((b['balance'] as num?) ?? 0) <= 0) return false;
                if (payState == 'overdue' && ((b['days_overdue'] as num?) ?? 0) <= 0) return false;
              }
              if (q.isEmpty) return true;
              final hay = '${r['number']} ${r['reference'] ?? ''} ${(r['party'] as Map?)?['name'] ?? ''} ${(r['creator'] as Map?)?['full_name'] ?? ''}'.toLowerCase();
              return hay.contains(q);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summary(all, balances, m.currency),
                const SizedBox(height: 16),
                PillTabs(labels: [for (final f in t.filters) f.label], index: _filter, onChanged: (i) => setState(() => _filter = i)),
                const SizedBox(height: 14),
                SizedBox(
                  width: context.isMobile ? double.infinity : 360,
                  child: AppTextField(hint: 'Search number, reference or ${t.partyLabel.toLowerCase()}', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v)),
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: t.icon,
                      title: all.isEmpty ? 'No ${t.plural.toLowerCase()} yet' : 'Nothing matches',
                      message: all.isEmpty ? _emptyHint() : 'Try a different filter or search.',
                      actionLabel: all.isEmpty && canCreate ? 'New ${t.label.toLowerCase()}' : null,
                      onAction: all.isEmpty && canCreate ? () => context.go(t.newPath) : null,
                    ),
                  )
                else
                  context.isMobile ? Column(children: [for (final r in rows) _card(r, balances, m.currency, money)]) : _table(rows, balances, m.currency, money),
              ],
            );
          },
        ),
      ],
    );
  }

  String _emptyHint() => switch (t.key) {
        'purchase_requisition' => 'Raise a requisition when your team needs something. Approved requisitions turn into purchase orders.',
        'purchase_order' => 'Create an order for a supplier, or convert an approved requisition.',
        'goods_receipt' => 'Record goods as they arrive. Receipts update your stock and the books.',
        'sales_quotation' => 'Send a priced quotation to a customer. When they accept it, convert it into a sales order.',
        'sales_order' => 'Confirm what a customer has ordered, then invoice it in full or in parts.',
        'sales_invoice' => 'Invoice a customer. Posting records the sale, issues stock and creates the receivable.',
        _ => 'Enter a supplier invoice to record what you owe. Stock items are billed from goods receipts.',
      };

  /// Headline figures for the whole list, ignoring the filter.
  Widget _summary(List<Map<String, dynamic>> all, Map<String, Map<String, dynamic>> balances, String currency) {
    int count(bool Function(Map<String, dynamic>) test) => all.where(test).length;
    double sum(bool Function(Map<String, dynamic>) test) => all.where(test).fold<double>(0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
    final today = DateTime.now();
    // A posted bill or invoice is overdue when something is still to pay and the due date has passed.
    bool overdue(Map<String, dynamic> r) {
      if (r['status'] != 'posted') return false;
      final b = balances['${r['id']}'];
      if (b != null) return ((b['balance'] as num?) ?? 0) > 0 && ((b['days_overdue'] as num?) ?? 0) > 0;
      final d = DateTime.tryParse('${r['due_date']}');
      return d != null && d.isBefore(DateTime(today.year, today.month, today.day));
    }

    double owed() => all.where((r) => r['status'] == 'posted').fold<double>(0, (s, r) => s + ((balances['${r['id']}']?['balance'] as num?)?.toDouble() ?? 0));
    double overdueSum() => all.where(overdue).fold<double>(0, (s, r) => s + ((balances['${r['id']}']?['balance'] as num?)?.toDouble() ?? 0));

    final cards = <Widget>[
      if (t.usesApproval) StatCard(label: 'Awaiting approval', value: '${count((r) => r['status'] == 'pending')}', icon: Icons.hourglass_top_rounded, tone: BadgeTone.warning),
      if (t.isRequisition) StatCard(label: 'Ready to order', value: '${count((r) => r['status'] == 'approved')}', icon: Icons.task_alt_rounded, tone: BadgeTone.success),
      if (t.isOrder) StatCard(label: 'Open orders', value: '${count((r) => r['status'] == 'approved' || r['status'] == 'partial')}', icon: Icons.local_shipping_outlined, tone: BadgeTone.info),
      if (t.isOrder) StatCard(label: 'Open order value', value: Fmt.compact(sum((r) => r['status'] == 'approved' || r['status'] == 'partial')), icon: Icons.payments_outlined),
      if (t.isReceipt) StatCard(label: 'Draft receipts', value: '${count((r) => r['status'] == 'draft')}', icon: Icons.edit_note_rounded, tone: BadgeTone.warning),
      if (t.isReceipt) StatCard(label: 'Posted receipts', value: '${count((r) => r['status'] == 'posted')}', icon: Icons.inventory_rounded, tone: BadgeTone.success),
      if (t.isBill) StatCard(label: 'Posted bills', value: Fmt.compact(sum((r) => r['status'] == 'posted')), icon: Icons.receipt_long_outlined),
      if (t.isBill) StatCard(label: 'Still to pay', value: Fmt.compact(owed()), icon: Icons.account_balance_wallet_outlined, tone: BadgeTone.warning),
      if (t.isBill) StatCard(label: 'Overdue bills', value: '${count(overdue)}', icon: Icons.event_busy_outlined, tone: BadgeTone.danger, hint: 'Unpaid and past the due date'),
      if (t.isQuotation) StatCard(label: 'Sent, awaiting answer', value: '${count((r) => r['status'] == 'sent')}', icon: Icons.send_outlined, tone: BadgeTone.info),
      if (t.isQuotation) StatCard(label: 'Accepted, not yet ordered', value: Fmt.compact(sum((r) => r['status'] == 'accepted')), icon: Icons.task_alt_rounded, tone: BadgeTone.success),
      if (t.isSalesOrder) StatCard(label: 'Open orders', value: '${count((r) => r['status'] == 'approved' || r['status'] == 'partial')}', icon: Icons.local_shipping_outlined, tone: BadgeTone.info),
      if (t.isSalesOrder) StatCard(label: 'Still to invoice', value: Fmt.compact(sum((r) => r['status'] == 'approved' || r['status'] == 'partial')), icon: Icons.payments_outlined),
      if (t.isInvoice) StatCard(label: 'Invoiced', value: Fmt.compact(sum((r) => r['status'] == 'posted' && r['is_opening'] != true)), icon: Icons.receipt_long_outlined),
      if (t.isInvoice) StatCard(label: 'Still to collect', value: Fmt.compact(owed()), icon: Icons.account_balance_wallet_outlined, tone: BadgeTone.warning),
      if (t.isInvoice) StatCard(label: 'Overdue invoices', value: '${count(overdue)}', icon: Icons.event_busy_outlined, tone: BadgeTone.danger, hint: Fmt.compact(overdueSum())),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final s in cards) SizedBox(width: w, child: s)]);
      },
    );
  }

  String _partyOrCreator(Map<String, dynamic> r) {
    if (t.isRequisition) return '${(r['creator'] as Map?)?['full_name'] ?? '--'}';
    return '${(r['party'] as Map?)?['name'] ?? '--'}';
  }

  String _secondDate(Map<String, dynamic> r) {
    final raw = t.hasPayments ? r['due_date'] : r['expected_date'];
    return raw == null ? '--' : Fmt.date(DateTime.tryParse('$raw'));
  }

  /// Workflow status, or for posted bills and invoices whether they are paid, partly paid or overdue.
  Widget _status(Map<String, dynamic> r, Map<String, Map<String, dynamic>> balances) {
    final status = '${r['status']}';
    if (t.isQuotation && status == 'rejected') return const StatusBadge('Declined', tone: BadgeTone.danger);
    if (t.isQuotation && status == 'sent') {
      final d = DateTime.tryParse('${r['expected_date']}');
      final today = DateTime.now();
      if (d != null && d.isBefore(DateTime(today.year, today.month, today.day))) return const StatusBadge('Expired', tone: BadgeTone.warning);
    }
    if (t.hasPayments && status == 'posted') {
      final b = balances['${r['id']}'];
      if (b != null) {
        return StatusBadge.status(paymentStateOf(
          total: (r['total'] as num?)?.toDouble() ?? 0,
          paid: (b['paid'] as num?)?.toDouble() ?? 0,
          daysOverdue: (b['days_overdue'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    return StatusBadge.status(status);
  }

  double _balance(Map<String, dynamic> r, Map<String, Map<String, dynamic>> balances) => (balances['${r['id']}']?['balance'] as num?)?.toDouble() ?? 0;

  Widget _table(List<Map<String, dynamic>> rows, Map<String, Map<String, dynamic>> balances, String currency, bool money) {
    Widget head(String text, int flex, {bool right = false}) =>
        Expanded(flex: flex, child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    final thirdTitle = t.isRequisition ? 'Requested by' : t.partyLabel;
    final fourthTitle = t.secondDateLabel ?? 'Warehouse';
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Number', 2), head('Date', 2), head(thirdTitle, 4), head(fourthTitle, 2), head('Reference', 3), if (money) head('Total', 2, right: true), if (t.hasPayments) head('Balance', 2, right: true), const SizedBox(width: 20), head('Status', 2)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go(t.detailPath('${r['id']}')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['number']}', style: AppText.bodyStrong),
                        if (r['is_opening'] == true) Text('Opening balance', style: AppText.small),
                      ]),
                    ),
                    Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['doc_date']}')), style: AppText.body)),
                    Expanded(flex: 4, child: Text(_partyOrCreator(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                    Expanded(flex: 2, child: Text(t.isReceipt ? '${(r['warehouse'] as Map?)?['name'] ?? '--'}' : _secondDate(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                    Expanded(flex: 3, child: Text('${r['reference'] ?? '--'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                    if (money) Expanded(flex: 2, child: Text(Fmt.money((r['total'] as num?)?.toDouble() ?? 0, currency: currency), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                    if (t.hasPayments)
                      Expanded(
                        flex: 2,
                        child: Text(
                          r['status'] == 'posted' ? (_balance(r, balances) > 0 ? Fmt.money(_balance(r, balances), currency: currency) : '--') : '',
                          textAlign: TextAlign.right,
                          style: AppText.body.copyWith(color: _balance(r, balances) > 0 ? AppColors.warning : AppColors.textMuted),
                        ),
                      ),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _status(r, balances))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r, Map<String, Map<String, dynamic>> balances, String currency, bool money) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go(t.detailPath('${r['id']}')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text('${r['number']}${r['is_opening'] == true ? '  (opening balance)' : ''}', style: AppText.bodyStrong)), _status(r, balances)]),
            const SizedBox(height: 2),
            Text('${_partyOrCreator(r)}, ${Fmt.date(DateTime.tryParse('${r['doc_date']}'))}', style: AppText.small),
            if (r['reference'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['reference']}', style: AppText.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (money) Padding(padding: const EdgeInsets.only(top: 6), child: Text(Fmt.money((r['total'] as num?)?.toDouble() ?? 0, currency: currency), style: AppText.label)),
            if (t.hasPayments && r['status'] == 'posted' && _balance(r, balances) > 0)
              Text('${Fmt.money(_balance(r, balances), currency: currency)} to ${t.isInvoice ? 'collect' : 'pay'}', style: AppText.small.copyWith(color: AppColors.warning)),
          ],
        ),
      ),
    );
  }
}
