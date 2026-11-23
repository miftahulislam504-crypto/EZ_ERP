import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import '../payments/payment_access.dart';
import '../payments/payment_models.dart';
import '../payments/payment_providers.dart';
import '../payments/record_payment_dialog.dart';
import 'sales_actions.dart';
import 'trade_models.dart';
import 'trade_providers.dart';

/// One purchase or sales document with its lines, linked documents, payments
/// and the actions that are available at its current status.
class TradeDetailPage extends ConsumerStatefulWidget {
  const TradeDetailPage({super.key, required this.type, required this.docId});

  final TradeType type;
  final String docId;

  @override
  ConsumerState<TradeDetailPage> createState() => _TradeDetailPageState();
}

class _TradeDetailPageState extends ConsumerState<TradeDetailPage> {
  bool _busy = false;

  TradeType get t => widget.type;
  String get id => widget.docId;

  Future<void> _run(Future<dynamic> Function() action, String done, {String? thenGo}) async {
    setState(() => _busy = true);
    try {
      await action();
      invalidateTrade(ref);
      if (mounted) showToast(context, done);
      if (thenGo != null && mounted) context.go(thenGo);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sales documents use their own workflow functions, which take the same arguments as the purchase ones.
  String _fn(String fn) {
    if (!t.isSales) return fn;
    return switch (fn) {
      'submit_document' => 'submit_sales_document',
      'approve_document' => 'approve_sales_document',
      'reject_document' => 'reject_sales_document',
      'discard_document' => 'discard_sales_document',
      'cancel_document' => 'cancel_sales_document',
      _ => fn,
    };
  }

  Future<void> _rpc(String fn, [Map<String, dynamic> extra = const {}]) => ref.read(supabaseProvider).rpc(_fn(fn), params: {'p_id': id, ...extra});

  Future<void> _reject() async {
    final reason = await promptDialog(context, title: 'Reject ${t.label.toLowerCase()}', label: 'Reason', confirmLabel: 'Reject', message: 'The person who created it will see this reason.', danger: true);
    if (reason == null) return;
    await _run(() => _rpc('reject_document', {'p_reason': reason}), '${t.label} rejected');
  }

  Future<void> _cancel(String status) async {
    final posted = status == 'posted';
    final message = switch (t.key) {
      'goods_receipt' when posted => 'The stock this receipt added is taken out again and the accounting entry is reversed. This is not possible if the goods have been billed or already used.',
      'supplier_bill' when posted => 'The accounting entry is reversed and the payable is removed. The bill stays in your records as cancelled. This is not possible while payments are applied to it.',
      'sales_invoice' when posted => 'The accounting entry is reversed, the stock it issued goes back at the cost it left at and the receivable is removed. The invoice stays in your records as cancelled. This is not possible while payments are applied to it.',
      _ => 'The ${t.label.toLowerCase()} stays in your records as cancelled.',
    };
    final reason = await promptDialog(context, title: 'Cancel ${t.label.toLowerCase()}', label: 'Reason', confirmLabel: 'Cancel ${t.label.toLowerCase()}', message: message, danger: true);
    if (reason == null) return;
    await _run(() => _rpc('cancel_document', {'p_reason': reason}), '${t.label} cancelled');
  }

  Future<void> _close() async {
    final reason = await promptDialog(
      context,
      title: 'Close order',
      label: 'Reason',
      confirmLabel: 'Close order',
      message: t.isSalesOrder
          ? 'No more invoices can be raised on this order. Use this when the customer will not take the rest.'
          : 'No more goods can be received on this order. Use this when the supplier will not deliver the rest.',
    );
    if (reason == null) return;
    await _run(() => _rpc(t.isSalesOrder ? 'close_sales_order' : 'close_purchase_order', {'p_reason': reason}), 'Order closed');
  }

  Future<void> _decline() async {
    final reason = await promptDialog(context, title: 'Customer declined', label: 'Reason they gave', confirmLabel: 'Mark as declined', message: 'The quotation stays in your records and can be reopened and changed.');
    if (reason == null) return;
    await _run(() => _rpc('set_quotation_outcome', {'p_outcome': 'rejected', 'p_reason': reason}), 'Quotation marked as declined');
  }

  Future<void> _postInvoice(String status) async {
    final ok = await confirmDialog(
      context,
      title: status == 'approved' ? 'Post invoice?' : 'Approve and post invoice?',
      message: 'Posting records the sale and the amount receivable, issues stock at average cost and books the cost of goods sold. Afterwards it cannot be edited, only cancelled.',
      confirmLabel: 'Post invoice',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final posted = await postSalesInvoice(context, ref, id);
      if (posted) {
        invalidateTrade(ref);
        if (mounted) showToast(context, 'Invoice posted');
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(context, title: 'Delete ${t.label.toLowerCase()}?', message: 'This draft will be removed permanently.', confirmLabel: 'Delete', danger: true);
    if (!ok) return;
    await _run(() => _rpc('discard_document'), '${t.label} deleted', thenGo: t.path);
  }

  Future<void> _postReceipt() async {
    final ok = await confirmDialog(
      context,
      title: 'Post goods receipt?',
      message: 'Posting adds the received quantities to stock and books the value as goods received but not yet billed. Afterwards it cannot be edited, only cancelled.',
      confirmLabel: 'Post receipt',
    );
    if (!ok) return;
    await _run(() => _rpc('post_goods_receipt'), 'Receipt posted. Stock has been updated.');
  }

  Future<void> _postBill(String status) async {
    final ok = await confirmDialog(
      context,
      title: status == 'approved' ? 'Post bill?' : 'Approve and post bill?',
      message: 'Posting books the bill against goods received, records input tax and creates the amount payable to the supplier. Afterwards it cannot be edited, only cancelled.',
      confirmLabel: 'Post bill',
    );
    if (!ok) return;
    await _run(() => _rpc('post_supplier_bill'), 'Bill posted');
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    final uid = ref.watch(currentUserIdProvider);
    if (m == null) return const LoadingView();
    if (!t.canView(perms)) return const NoAccessView();
    final async = ref.watch(tradeDetailProvider(id));

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(tradeDetailProvider)),
      data: (d) {
        if (d == null || d['doc_type'] != t.key) {
          return EmptyState(icon: Icons.search_off_rounded, title: '${t.label} not found', message: 'It may have been deleted, or you may not have access to it.', actionLabel: 'Back to ${t.plural.toLowerCase()}', onAction: () => context.go(t.path));
        }
        final lines = List<Map<String, dynamic>>.from(d['trade_document_lines'] as List)..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));
        final status = '${d['status']}';
        final isMine = d['created_by'] != null && d['created_by'] == uid;
        final canCreate = t.can(perms, PermAction.create);
        final canEdit = t.can(perms, PermAction.edit);
        final canApprove = t.can(perms, PermAction.approve);
        final canWriteDraft = canEdit || (isMine && canCreate);
        final isOpen = status == 'draft' || status == 'rejected';
        final canPurchaseCreate = perms.can(Modules.purchase, PermAction.create);
        final canReceive = perms.can(Modules.inventory, PermAction.create) || canPurchaseCreate;
        final showMoney = t.hasPrices || t.isReceipt;
        final canSalesCreate = perms.can(Modules.sales, PermAction.create);
        final side = t.isInvoice ? LedgerSide.receivable : LedgerSide.payable;
        // Paid amount and balance of a posted invoice or bill.
        final balMap = t.hasPayments && status == 'posted' ? ref.watch(documentBalancesProvider((org: m.orgId, type: t.key))).valueOrNull : null;
        final bal = balMap == null ? null : balMap[id];
        final owed = (bal?['balance'] as num?)?.toDouble() ?? 0;

        final actions = <Widget>[
          if (isOpen && canWriteDraft) AppButton(label: 'Edit', icon: Icons.edit_outlined, kind: AppButtonKind.secondary, onPressed: _busy ? null : () => context.go(t.editPath(id))),
          if (isOpen && canWriteDraft && t.usesApproval) AppButton(label: 'Submit for approval', onPressed: _busy ? null : () => _run(() => _rpc('submit_document'), 'Submitted for approval')),
          if (status == 'pending' && canApprove) AppButton(label: 'Approve', onPressed: _busy ? null : () => _run(() => _rpc('approve_document'), '${t.label} approved')),
          if (status == 'pending' && canApprove) AppButton(label: 'Reject', kind: AppButtonKind.danger, onPressed: _busy ? null : _reject),
          if (t.isRequisition && (status == 'approved' || status == 'ordered') && canPurchaseCreate)
            AppButton(label: 'Create purchase order', icon: Icons.shopping_bag_outlined, onPressed: _busy ? null : () => context.go('${orderType.path}/new?from=$id')),
          if (t.isOrder && (status == 'approved' || status == 'partial') && canReceive)
            AppButton(label: 'Receive goods', icon: Icons.move_to_inbox_outlined, onPressed: _busy ? null : () => context.go('${receiptType.path}/new?from=$id')),
          if (t.isOrder && (status == 'approved' || status == 'partial' || status == 'received' || status == 'closed') && canPurchaseCreate)
            AppButton(label: 'Create bill', icon: Icons.description_outlined, kind: AppButtonKind.secondary, onPressed: _busy ? null : () => context.go('${billType.path}/new?supplier=${d['party_id']}')),
          if (t.isOrder && (status == 'approved' || status == 'partial') && canApprove)
            AppButton(label: 'Close order', kind: AppButtonKind.secondary, onPressed: _busy ? null : _close),
          if (t.isReceipt && status == 'draft' && canApprove) AppButton(label: 'Post receipt', onPressed: _busy ? null : _postReceipt),
          if (t.isReceipt && status == 'posted' && canPurchaseCreate)
            AppButton(label: 'Create bill', icon: Icons.description_outlined, onPressed: _busy ? null : () => context.go('${billType.path}/new?from=$id')),
          if (t.isBill && (status == 'draft' || status == 'pending' || status == 'approved') && canApprove)
            AppButton(label: status == 'approved' ? 'Post bill' : 'Approve and post', onPressed: _busy ? null : () => _postBill(status)),
          if (t.isQuotation && status == 'draft' && canWriteDraft)
            AppButton(label: 'Mark as sent', icon: Icons.send_outlined, onPressed: _busy ? null : () => _run(() => _rpc('mark_quotation_sent'), 'Quotation marked as sent')),
          if (t.isQuotation && status == 'sent' && canWriteDraft)
            AppButton(label: 'Customer accepted', icon: Icons.check_circle_outline_rounded, onPressed: _busy ? null : () => _run(() => _rpc('set_quotation_outcome', {'p_outcome': 'accepted'}), 'Quotation accepted')),
          if (t.isQuotation && status == 'sent' && canWriteDraft) AppButton(label: 'Customer declined', kind: AppButtonKind.secondary, onPressed: _busy ? null : _decline),
          if (t.isQuotation && (status == 'sent' || status == 'accepted') && canSalesCreate)
            AppButton(label: 'Create sales order', icon: Icons.shopping_cart_outlined, onPressed: _busy ? null : () => context.go('${salesOrderType.path}/new?from=$id')),
          if (t.isQuotation && (status == 'sent' || status == 'accepted') && canWriteDraft)
            AppButton(label: 'Reopen to edit', kind: AppButtonKind.ghost, onPressed: _busy ? null : () => _run(() => _rpc('reopen_quotation'), 'Quotation reopened as a draft')),
          if (t.isSalesOrder && (status == 'approved' || status == 'partial') && canSalesCreate)
            AppButton(label: 'Create invoice', icon: Icons.receipt_long_outlined, onPressed: _busy ? null : () => context.go('${invoiceType.path}/new?from=$id')),
          if (t.isSalesOrder && (status == 'approved' || status == 'partial') && canApprove)
            AppButton(label: 'Close order', kind: AppButtonKind.secondary, onPressed: _busy ? null : _close),
          if (t.isInvoice && (status == 'draft' || status == 'pending' || status == 'approved') && canApprove)
            AppButton(label: status == 'approved' ? 'Post invoice' : 'Approve and post', onPressed: _busy ? null : () => _postInvoice(status)),
          if (t.hasPayments && status == 'posted' && owed > 0 && canRecordPayment(perms, side))
            AppButton(label: t.isInvoice ? 'Record receipt' : 'Record payment', icon: Icons.payments_outlined, onPressed: _busy ? null : () => showRecordPayment(context, side: side, partyId: '${d['party_id']}', documentId: id)),
          if (_canCancel(status, canApprove, isMine))
            AppButton(label: status == 'posted' ? (t.isBill ? 'Cancel bill' : (t.isInvoice ? 'Cancel invoice' : 'Cancel receipt')) : 'Cancel', icon: Icons.block_rounded, kind: AppButtonKind.danger, onPressed: _busy ? null : () => _cancel(status)),
          if (isOpen && (canEdit || (isMine && canCreate))) AppButton(label: 'Delete', kind: AppButtonKind.ghost, onPressed: _busy ? null : _discard),
        ];

        final purchaseProgress = t.isOrder && const {'approved', 'partial', 'received', 'closed'}.contains(status) ? ref.watch(orderProgressProvider(id)).valueOrNull : null;
        final salesProgress = t.isSalesOrder && const {'approved', 'partial', 'invoiced', 'closed'}.contains(status) ? ref.watch(salesOrderProgressProvider((doc: id, exclude: null))).valueOrNull : null;
        // Sales orders show what has been invoiced in the "billed" column.
        final Map<String, ({double ordered, double received, double billed})>? progress = salesProgress == null
            ? purchaseProgress
            : {for (final e in salesProgress.entries) e.key: (ordered: e.value.ordered, received: 0.0, billed: e.value.invoiced)};

        return AppPage(
          title: '${d['number']}',
          subtitle: t.label,
          maxWidth: 1100,
          actions: actions,
          children: [
            if (status == 'rejected' && d['rejection_reason'] != null)
              _banner(Icons.cancel_outlined, t.isQuotation ? 'Declined by the customer: ${d['rejection_reason']}. You can edit it and send it again.' : 'Rejected: ${d['rejection_reason']}', AppColors.dangerSoft, AppColors.danger),
            if (status == 'cancelled' && d['cancel_reason'] != null) _banner(Icons.block_rounded, 'Cancelled: ${d['cancel_reason']}', AppColors.dangerSoft, AppColors.danger),
            if (status == 'closed' && d['cancel_reason'] != null) _banner(Icons.lock_outline_rounded, 'Closed: ${d['cancel_reason']}', AppColors.warningSoft, AppColors.warning),
            if (d['is_opening'] == true) _banner(Icons.history_rounded, 'Opening balance. This is an amount that was owed before you started using EZ ERP, entered with its original dates.', AppColors.infoSoft, AppColors.info),
            if (d['credit_overridden'] == true) _banner(Icons.warning_amber_rounded, "This invoice was posted above the customer's credit limit.", AppColors.warningSoft, AppColors.warning),
            _header(d, status, m.currency, showMoney, perms, bal),
            const SizedBox(height: 16),
            _linesCard(lines, d, m.currency, showMoney, progress),
            if (showMoney) ...[const SizedBox(height: 16), _totals(d, m.currency)],
            if (t.hasPayments && status == 'posted') ...[const SizedBox(height: 16), _paymentsCard(side, m.currency)],
            const SizedBox(height: 16),
            _related(id),
            if (d['notes'] != null) ...[
              const SizedBox(height: 16),
              SectionCard(title: t.isRequisition ? 'Reason for the request' : 'Notes', child: Text('${d['notes']}', style: AppText.body)),
            ],
            const SizedBox(height: 16),
            AttachmentsPanel(entityType: t.key, entityId: id, canUpload: canCreate && status != 'cancelled'),
          ],
        );
      },
    );
  }

  bool _canCancel(String status, bool canApprove, bool isMine) {
    switch (t.key) {
      case 'purchase_requisition':
        return const {'draft', 'pending', 'approved', 'rejected'}.contains(status) && (canApprove || isMine);
      case 'purchase_order':
        return const {'draft', 'pending', 'approved', 'rejected'}.contains(status) && (canApprove || (isMine && (status == 'draft' || status == 'rejected')));
      case 'goods_receipt':
        return (status == 'draft' && (canApprove || isMine)) || (status == 'posted' && canApprove);
      case 'supplier_bill':
      case 'sales_invoice':
        return (const {'draft', 'pending', 'approved', 'rejected'}.contains(status) && (canApprove || (isMine && (status == 'draft' || status == 'rejected')))) || (status == 'posted' && canApprove);
      case 'sales_quotation':
        return const {'draft', 'sent', 'accepted', 'rejected'}.contains(status) && (t.can(ref.read(permsProvider), PermAction.edit) || isMine);
      case 'sales_order':
        return const {'draft', 'pending', 'approved', 'rejected'}.contains(status) && (canApprove || (isMine && (status == 'draft' || status == 'rejected')));
    }
    return false;
  }

  Widget _banner(IconData icon, String text, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(children: [Icon(icon, size: 19, color: fg), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)))]),
    );
  }

  Widget _info(String label, String value) => SizedBox(
        width: 210,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.small), const SizedBox(height: 2), Text(value, style: AppText.bodyStrong)]),
      );

  Widget _header(Map<String, dynamic> d, String status, String currency, bool showMoney, PermissionSet perms, Map<String, dynamic>? bal) {
    String who(String key) => ((d[key] as Map?)?['full_name'] as String?) ?? '--';
    String date(Object? raw) => raw == null ? '--' : Fmt.date(DateTime.tryParse('$raw'));
    final party = d['party'] as Map?;
    final source = d['source'] as Map?;
    final voucher = d['voucher'] as Map?;
    String money(Object? v) => Fmt.money((v as num?)?.toDouble() ?? 0, currency: currency);

    // Quotations show Expired and Declined; posted bills and invoices show whether they are paid, partly paid or overdue.
    Widget badge() {
      if (t.isQuotation && status == 'rejected') return const StatusBadge('Declined', tone: BadgeTone.danger);
      if (t.isQuotation && status == 'sent') {
        final until = DateTime.tryParse('${d['expected_date']}');
        final today = DateTime.now();
        if (until != null && until.isBefore(DateTime(today.year, today.month, today.day))) return const StatusBadge('Expired', tone: BadgeTone.warning);
      }
      if (bal != null) {
        return StatusBadge.status(paymentStateOf(total: (d['total'] as num?)?.toDouble() ?? 0, paid: (bal['paid'] as num?)?.toDouble() ?? 0, daysOverdue: (bal['days_overdue'] as num?)?.toInt() ?? 0));
      }
      return StatusBadge.status(status);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [badge(), const Spacer(), if (showMoney) Text(Fmt.money((d['total'] as num?)?.toDouble() ?? 0, currency: currency), style: AppText.kpi)]),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              if (!t.isRequisition || party != null) _info(t.isRequisition ? 'Preferred supplier' : t.partyLabel, '${party?['name'] ?? '--'}'),
              _info(t.dateLabel, date(d['doc_date'])),
              if (t.hasPayments) _info('Due date', date(d['due_date'])) else if (t.secondDateLabel != null) _info(t.secondDateLabel!, date(d['expected_date'])),
              if (bal != null) _info('Paid', money(bal['paid'])),
              if (bal != null) _info('Balance due', money(bal['balance'])),
              if (d['warehouse'] != null) _info(t.isOrder ? 'Deliver to' : (t.isInvoice ? 'Issued from' : (t.isSalesOrder ? 'Deliver from' : 'Warehouse')), '${(d['warehouse'] as Map)['name']}'),
              if (d['branch'] != null) _info('Branch', '${(d['branch'] as Map)['name']}'),
              if (d['department'] != null) _info('Department', '${(d['department'] as Map)['name']}'),
              if (d['reference'] != null) _info(t.referenceLabel, '${d['reference']}'),
              _info(t.isRequisition ? 'Requested by' : 'Created by', who('creator')),
              if (d['approved_at'] != null) _info('Approved by', '${who('approver')}, ${Fmt.dateTime(Fmt.parse(d['approved_at'] as String?))}'),
              if (d['posted_at'] != null) _info('Posted by', '${who('poster')}, ${Fmt.dateTime(Fmt.parse(d['posted_at'] as String?))}'),
            ],
          ),
          if (source != null || (party != null && !t.isRequisition) || (voucher != null && perms.canView(Modules.finance))) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (source != null)
                  AppButton(
                    label: 'Created from ${source['number']}',
                    icon: Icons.subdirectory_arrow_right_rounded,
                    kind: AppButtonKind.ghost,
                    compact: true,
                    onPressed: () {
                      final path = tradeDocumentPath('${source['doc_type']}', '${source['id']}');
                      if (path != null) context.go(path);
                    },
                  ),
                if (party != null && !t.isRequisition && perms.canView(t.isSales ? Modules.sales : Modules.purchase))
                  AppButton(label: 'Open ${t.partyLabel.toLowerCase()} profile', icon: Icons.person_outline_rounded, kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go(partyProfilePath(t.partyRole, '${party['id']}'))),
                if (voucher != null && perms.canView(Modules.finance))
                  AppButton(label: 'Accounting entry ${voucher['voucher_no']}', icon: Icons.receipt_long_outlined, kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go('/finance/vouchers/${voucher['id']}')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _itemName(Map<String, dynamic> l) {
    final p = l['product'] as Map?;
    final name = p?['name'] as String?;
    final desc = l['description'] as String?;
    if (name != null && desc != null) return '$name, $desc';
    return name ?? desc ?? '--';
  }

  String _itemSub(Map<String, dynamic> l) {
    final p = l['product'] as Map?;
    final acc = l['account'] as Map?;
    return [if (p?['sku'] != null) '${p!['sku']}', if (acc != null) 'Account ${acc['code']} ${acc['name']}'].join('   ');
  }

  Widget _linesCard(List<Map<String, dynamic>> lines, Map<String, dynamic> d, String currency, bool showMoney, Map<String, ({double ordered, double received, double billed})>? progress) {
    final showTax = t.hasTaxAndDiscount && lines.any((l) => ((l['tax_amount'] as num?) ?? 0) > 0 || ((l['discount_amount'] as num?) ?? 0) > 0);
    String money(Object? v) => Fmt.money((v as num?)?.toDouble() ?? 0, currency: currency);

    if (context.isMobile) {
      return SectionCard(
        title: 'Items',
        child: Column(
          children: [
            for (final l in lines) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_itemName(l), style: AppText.bodyStrong),
                    if (_itemSub(l).isNotEmpty) Text(_itemSub(l), style: AppText.small),
                    const SizedBox(height: 4),
                    Text(
                      '${qtyText(l['quantity'] as num)} x ${money(l['unit_price'])}${showMoney ? '  =  ${money(l['line_total'])}' : ''}',
                      style: AppText.body,
                    ),
                    if (progress != null && progress[l['id']] != null)
                      Text(t.isSalesOrder ? 'Invoiced ${qtyText(progress[l['id']]!.billed)}' : 'Received ${qtyText(progress[l['id']]!.received)}, billed ${qtyText(progress[l['id']]!.billed)}', style: AppText.small),
                  ],
                ),
              ),
              if (l != lines.last) const Divider(height: 22),
            ],
          ],
        ),
      );
    }

    Widget cell(String text, int flex, {bool right = false, bool head = false, bool strong = false}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: head ? AppText.small.copyWith(fontWeight: FontWeight.w600) : (strong ? AppText.bodyStrong : AppText.body)),
          ),
        );

    final prog = progress != null;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [
              cell('Item', 6, head: true),
              cell('Quantity', 2, right: true, head: true),
              if (prog && !t.isSalesOrder) cell('Received', 2, right: true, head: true),
              if (prog) cell(t.isSalesOrder ? 'Invoiced' : 'Billed', 2, right: true, head: true),
              if (t.hasPrices || t.isReceipt) cell(t.isReceipt ? 'Unit cost' : 'Unit price', 3, right: true, head: true),
              if (showTax) cell('Discount', 2, right: true, head: true),
              if (showTax) cell('Tax', 2, right: true, head: true),
              if (showMoney) cell('Total', 3, right: true, head: true),
            ]),
          ),
          for (final l in lines) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_itemName(l), style: AppText.bodyStrong),
                        if (_itemSub(l).isNotEmpty) Text(_itemSub(l), style: AppText.small),
                      ]),
                    ),
                  ),
                  cell(qtyText(l['quantity'] as num), 2, right: true),
                  if (prog && !t.isSalesOrder) cell(qtyText(progress?[l['id']]?.received), 2, right: true),
                  if (prog) cell(qtyText(progress?[l['id']]?.billed), 2, right: true),
                  if (t.hasPrices || t.isReceipt) cell(money(l['unit_price']), 3, right: true),
                  if (showTax) cell(((l['discount_amount'] as num?) ?? 0) == 0 ? '' : money(l['discount_amount']), 2, right: true),
                  if (showTax) cell(((l['tax_amount'] as num?) ?? 0) == 0 ? '' : '${money(l['tax_amount'])}${l['tax'] != null ? '\n${(l['tax'] as Map)['name']}' : ''}', 2, right: true),
                  if (showMoney) cell(money(l['line_total']), 3, right: true, strong: true),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totals(Map<String, dynamic> d, String currency) {
    String money(Object? v) => Fmt.money((v as num?)?.toDouble() ?? 0, currency: currency);
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(label, style: strong ? AppText.h3 : AppText.body)), Text(value, style: strong ? AppText.h3 : AppText.bodyStrong)]),
        );
    final discount = (d['discount_total'] as num?) ?? 0;
    final tax = (d['tax_total'] as num?) ?? 0;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: AppCard(
          child: Column(children: [
            row('Subtotal', money(d['subtotal'])),
            if (discount > 0) row('Discount', '- ${money(discount)}'),
            if (tax > 0) row('Tax', money(tax)),
            const Divider(height: 18),
            row(t.isRequisition ? 'Estimated total' : 'Total', money(d['total']), strong: true),
          ]),
        ),
      ),
    );
  }

  /// Payments applied to this invoice or bill, each linking to its receipt or payment.
  Widget _paymentsCard(LedgerSide side, String currency) {
    final async = ref.watch(documentPaymentsProvider(id));
    return SectionCard(
      title: 'Payments',
      subtitle: t.isInvoice ? 'Receipts applied to this invoice' : 'Payments applied to this bill',
      child: async.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (e, _) => Text(friendlyError(e), style: AppText.body),
        data: (rows) {
          if (rows.isEmpty) return Text(t.isInvoice ? 'Nothing has been received against this invoice yet.' : 'Nothing has been paid against this bill yet.', style: AppText.body);
          return Column(
            children: [
              for (final r in rows) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => context.go(side.paymentPath('${(r['payment'] as Map)['id']}')),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(children: [
                      const Icon(Icons.payments_outlined, size: 20, color: AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${(r['payment'] as Map)['number']}', style: AppText.bodyStrong),
                          Text('${Fmt.date(DateTime.tryParse('${r['alloc_date']}'))}${(r['payment'] as Map)['reference'] == null ? '' : ', ${(r['payment'] as Map)['reference']}'}', style: AppText.small),
                        ]),
                      ),
                      Text(Fmt.money((r['amount'] as num).toDouble(), currency: currency), style: AppText.bodyStrong),
                    ]),
                  ),
                ),
                if (r != rows.last) const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _related(String docId) {
    final async = ref.watch(relatedDocumentsProvider(docId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: 'Related documents',
          subtitle: 'Where this came from and what was created from it',
          child: Column(
            children: [
              for (final r in rows) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () {
                    final path = tradeDocumentPath('${r['doc_type']}', '${r['id']}');
                    if (path != null) context.go(path);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(tradeTypes['${r['doc_type']}']?.icon ?? Icons.description_outlined, size: 20, color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['number']}', style: AppText.bodyStrong),
                            Text('${tradeTypes['${r['doc_type']}']?.label ?? ''}, ${r['relation'] == 'source' ? 'created from' : 'created later'}, ${Fmt.date(DateTime.tryParse('${r['doc_date']}'))}', style: AppText.small),
                          ]),
                        ),
                        StatusBadge.status('${r['status']}'),
                      ],
                    ),
                  ),
                ),
                if (r != rows.last) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}
