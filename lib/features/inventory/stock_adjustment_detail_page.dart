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
import '../trade/trade_models.dart';
import '../trade/trade_providers.dart';

/// One stock adjustment with its lines and the actions available at its status.
class StockAdjustmentDetailPage extends ConsumerStatefulWidget {
  const StockAdjustmentDetailPage({super.key, required this.adjustmentId});

  final String adjustmentId;

  @override
  ConsumerState<StockAdjustmentDetailPage> createState() => _StockAdjustmentDetailPageState();
}

class _StockAdjustmentDetailPageState extends ConsumerState<StockAdjustmentDetailPage> {
  bool _busy = false;

  String get id => widget.adjustmentId;

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

  Future<void> _rpc(String fn, [Map<String, dynamic> extra = const {}]) => ref.read(supabaseProvider).rpc(fn, params: {'p_id': id, ...extra});

  Future<void> _reject() async {
    final reason = await promptDialog(context, title: 'Reject adjustment', label: 'Reason', confirmLabel: 'Reject', message: 'The person who created it will see this reason.', danger: true);
    if (reason == null) return;
    await _run(() => _rpc('reject_stock_adjustment', {'p_reason': reason}), 'Adjustment rejected');
  }

  Future<void> _post(String status) async {
    final ok = await confirmDialog(
      context,
      title: status == 'approved' ? 'Post adjustment?' : 'Approve and post adjustment?',
      message: 'Posting changes the stock quantities now and books the value difference. Afterwards it cannot be edited, only cancelled.',
      confirmLabel: 'Post adjustment',
    );
    if (!ok) return;
    await _run(() => _rpc('post_stock_adjustment'), 'Adjustment posted. Stock has been updated.');
  }

  Future<void> _cancel(String status) async {
    final reason = await promptDialog(
      context,
      title: 'Cancel adjustment',
      label: 'Reason',
      confirmLabel: 'Cancel adjustment',
      message: status == 'posted' ? 'The stock movements and the accounting entry are reversed. This is not possible if the stock has since been used.' : 'The adjustment stays in your records as cancelled.',
      danger: true,
    );
    if (reason == null) return;
    await _run(() => _rpc('cancel_stock_adjustment', {'p_reason': reason}), 'Adjustment cancelled');
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(context, title: 'Delete adjustment?', message: 'This draft will be removed permanently.', confirmLabel: 'Delete', danger: true);
    if (!ok) return;
    await _run(() => _rpc('discard_stock_adjustment'), 'Adjustment deleted', thenGo: '/inventory/adjustments');
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    final uid = ref.watch(currentUserIdProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.inventory)) return const NoAccessView();
    final async = ref.watch(adjustmentDetailProvider(id));

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(adjustmentDetailProvider)),
      data: (a) {
        if (a == null) {
          return EmptyState(icon: Icons.search_off_rounded, title: 'Adjustment not found', message: 'It may have been deleted, or you may not have access to it.', actionLabel: 'Back to adjustments', onAction: () => context.go('/inventory/adjustments'));
        }
        final status = '${a['status']}';
        final lines = List<Map<String, dynamic>>.from(a['stock_adjustment_lines'] as List)..sort((x, y) => (x['line_no'] as int).compareTo(y['line_no'] as int));
        final isMine = a['created_by'] != null && a['created_by'] == uid;
        final canCreate = perms.can(Modules.inventory, PermAction.create);
        final canEdit = perms.can(Modules.inventory, PermAction.edit);
        final canApprove = perms.can(Modules.inventory, PermAction.approve);
        final canWriteDraft = canEdit || (isMine && canCreate);
        final isOpen = status == 'draft' || status == 'rejected';
        final movements = status == 'posted' ? (ref.watch(movementsForSourceProvider(id)).valueOrNull ?? <Map<String, dynamic>>[]) : <Map<String, dynamic>>[];
        String who(String key) => ((a[key] as Map?)?['full_name'] as String?) ?? '--';
        final voucher = a['voucher'] as Map?;

        return AppPage(
          title: '${a['number']}',
          subtitle: 'Stock adjustment',
          maxWidth: 1000,
          actions: [
            if (isOpen && canWriteDraft) AppButton(label: 'Edit', icon: Icons.edit_outlined, kind: AppButtonKind.secondary, onPressed: _busy ? null : () => context.go('/inventory/adjustments/$id/edit')),
            if (isOpen && canWriteDraft) AppButton(label: 'Submit for approval', onPressed: _busy ? null : () => _run(() => _rpc('submit_stock_adjustment'), 'Submitted for approval')),
            if (status == 'pending' && canApprove) AppButton(label: 'Approve', onPressed: _busy ? null : () => _run(() => _rpc('approve_stock_adjustment'), 'Adjustment approved')),
            if (status == 'pending' && canApprove) AppButton(label: 'Reject', kind: AppButtonKind.danger, onPressed: _busy ? null : _reject),
            if ((isOpen || status == 'pending' || status == 'approved') && canApprove) AppButton(label: status == 'approved' ? 'Post' : 'Approve and post', onPressed: _busy ? null : () => _post(status)),
            if (status != 'cancelled' && status != 'posted' && (canApprove || (isMine && isOpen))) AppButton(label: 'Cancel', icon: Icons.block_rounded, kind: AppButtonKind.danger, onPressed: _busy ? null : () => _cancel(status)),
            if (status == 'posted' && canApprove) AppButton(label: 'Cancel adjustment', icon: Icons.undo_rounded, kind: AppButtonKind.danger, onPressed: _busy ? null : () => _cancel(status)),
            if (isOpen && (canEdit || (isMine && canCreate))) AppButton(label: 'Delete', kind: AppButtonKind.ghost, onPressed: _busy ? null : _discard),
          ],
          children: [
            if (status == 'rejected' && a['rejection_reason'] != null) _banner(Icons.cancel_outlined, 'Rejected: ${a['rejection_reason']}', AppColors.dangerSoft, AppColors.danger),
            if (status == 'cancelled' && a['cancel_reason'] != null) _banner(Icons.block_rounded, 'Cancelled: ${a['cancel_reason']}', AppColors.dangerSoft, AppColors.danger),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge.status(status),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 24,
                    runSpacing: 14,
                    children: [
                      _info('Date', Fmt.date(DateTime.tryParse('${a['adj_date']}'))),
                      _info('Warehouse', '${(a['warehouse'] as Map?)?['name'] ?? '--'}'),
                      _info('Reason', adjustmentReasons['${a['reason']}'] ?? '${a['reason']}'),
                      _info('Created by', who('creator')),
                      if (a['approved_at'] != null) _info('Approved by', '${who('approver')}, ${Fmt.dateTime(Fmt.parse(a['approved_at'] as String?))}'),
                      if (a['posted_at'] != null) _info('Posted by', '${who('poster')}, ${Fmt.dateTime(Fmt.parse(a['posted_at'] as String?))}'),
                    ],
                  ),
                  if (a['notes'] != null) ...[const SizedBox(height: 16), Text('Notes', style: AppText.small), const SizedBox(height: 2), Text('${a['notes']}', style: AppText.body)],
                  if (voucher != null && perms.canView(Modules.finance)) ...[
                    const SizedBox(height: 14),
                    AppButton(label: 'Accounting entry ${voucher['voucher_no']}', icon: Icons.receipt_long_outlined, kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go('/finance/vouchers/${voucher['id']}')),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _linesCard(lines, movements, m.currency),
            const SizedBox(height: 16),
            AttachmentsPanel(entityType: 'stock_adjustment', entityId: id, canUpload: canCreate && status != 'cancelled'),
          ],
        );
      },
    );
  }

  Widget _banner(IconData icon, String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(children: [Icon(icon, size: 19, color: fg), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)))]),
      );

  Widget _info(String label, String value) => SizedBox(
        width: 210,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.small), const SizedBox(height: 2), Text(value, style: AppText.bodyStrong)]),
      );

  Widget _linesCard(List<Map<String, dynamic>> lines, List<Map<String, dynamic>> movements, String currency) {
    Map<String, dynamic>? movementFor(Object? lineId) {
      for (final mv in movements) {
        if (mv['source_line_id'] == lineId) return mv;
      }
      return null;
    }

    String change(Map<String, dynamic> l) {
      final q = (l['quantity_change'] as num).toDouble();
      return '${q > 0 ? '+' : ''}${qtyText(q)}';
    }

    Color changeColor(Map<String, dynamic> l) => (l['quantity_change'] as num) > 0 ? AppColors.success : AppColors.danger;

    if (context.isMobile) {
      return SectionCard(
        title: 'Items',
        child: Column(
          children: [
            for (final l in lines) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(l['product'] as Map?)?['name'] ?? '--'}', style: AppText.bodyStrong),
                  Text('${(l['product'] as Map?)?['sku'] ?? ''}', style: AppText.small),
                  const SizedBox(height: 4),
                  Text('${change(l)} ${((l['product'] as Map?)?['unit'] as Map?)?['name'] ?? ''}'.trim(), style: AppText.bodyStrong.copyWith(color: changeColor(l))),
                  if (l['note'] != null) Text('${l['note']}', style: AppText.small),
                ]),
              ),
              if (l != lines.last) const Divider(height: 22),
            ],
          ],
        ),
      );
    }

    Widget cell(String text, int flex, {bool right = false, bool head = false, Color? color}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(text, textAlign: right ? TextAlign.right : TextAlign.left, style: head ? AppText.small.copyWith(fontWeight: FontWeight.w600) : AppText.bodyStrong.copyWith(color: color)),
          ),
        );
    final showCost = movements.isNotEmpty;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [cell('Item', 6, head: true), cell('Change', 2, right: true, head: true), if (showCost) cell('Unit cost', 3, right: true, head: true), if (showCost) cell('Value', 3, right: true, head: true), cell('Note', 4, head: true)]),
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${(l['product'] as Map?)?['name'] ?? '--'}', style: AppText.bodyStrong), Text('${(l['product'] as Map?)?['sku'] ?? ''}', style: AppText.small)]),
                  ),
                  cell(change(l), 2, right: true, color: changeColor(l)),
                  if (showCost) cell(movementFor(l['id']) == null ? '--' : Fmt.money((movementFor(l['id'])!['unit_cost'] as num).toDouble(), currency: currency), 3, right: true),
                  if (showCost) cell(movementFor(l['id']) == null ? '--' : Fmt.money((movementFor(l['id'])!['value'] as num).toDouble(), currency: currency), 3, right: true),
                  Expanded(flex: 4, child: Text('${l['note'] ?? ''}', style: AppText.body)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
