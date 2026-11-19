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
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import 'finance_providers.dart';
import 'voucher_pdf.dart';
import 'vouchers_page.dart';

final voucherDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('vouchers').select(
        '*, branches(name), creator:profiles!created_by(full_name), approver:profiles!approved_by(full_name), '
        'poster:profiles!posted_by(full_name), reversed:vouchers!reversed_by(voucher_no), reversal:vouchers!reversal_of(voucher_no), '
        'voucher_lines(id, line_no, description, debit, credit, accounts(code, name), parties(name))',
      ).eq('id', id).maybeSingle();
});

class VoucherDetailPage extends ConsumerStatefulWidget {
  const VoucherDetailPage({super.key, required this.voucherId});
  final String voucherId;

  @override
  ConsumerState<VoucherDetailPage> createState() => _VoucherDetailPageState();
}

class _VoucherDetailPageState extends ConsumerState<VoucherDetailPage> {
  bool _busy = false;

  String get id => widget.voucherId;

  Future<void> _run(Future<dynamic> Function() action, String done, {String? thenGo}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(voucherDetailProvider);
      ref.invalidate(vouchersListProvider);
      ref.invalidate(balancesProvider);
      if (mounted) showToast(context, done);
      if (thenGo != null && mounted) context.go(thenGo);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rpc(String fn, [Map<String, dynamic> extra = const {}]) =>
      ref.read(supabaseProvider).rpc(fn, params: {'p_id': id, ...extra});

  Future<void> _reject() async {
    final reason = await promptDialog(context, title: 'Reject voucher', label: 'Reason', confirmLabel: 'Reject', message: 'The person who created it will see this reason.', danger: true);
    if (reason == null) return;
    await _run(() => _rpc('reject_voucher', {'p_reason': reason}), 'Voucher rejected');
  }

  Future<void> _reverse() async {
    final reason = await promptDialog(
      context,
      title: 'Reverse voucher',
      label: 'Reason',
      confirmLabel: 'Reverse',
      message: 'A new voucher with equal and opposite entries is posted today. The original stays in your books for the audit trail.',
      danger: true,
    );
    if (reason == null) return;
    await _run(() => _rpc('reverse_voucher', {'p_reason': reason}), 'Voucher reversed');
  }

  Future<void> _post() async {
    final ok = await confirmDialog(context, title: 'Post voucher?', message: 'Posting writes this voucher into your books. Afterwards it cannot be edited, only reversed.', confirmLabel: 'Post voucher');
    if (!ok) return;
    await _run(() => _rpc('post_voucher'), 'Voucher posted');
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(context, title: 'Delete voucher?', message: 'This draft will be removed permanently.', confirmLabel: 'Delete', danger: true);
    if (!ok) return;
    await _run(() => _rpc('discard_voucher'), 'Voucher deleted', thenGo: '/finance/vouchers');
  }

  Future<void> _print(Map<String, dynamic> v, List<Map<String, dynamic>> lines) async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() => _busy = true);
    try {
      await printVoucher(voucher: v, lines: lines, orgName: m.orgName, currency: m.currency);
    } catch (e) {
      if (mounted) showToast(context, 'Could not prepare the PDF. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.finance)) return const NoAccessView();
    final async = ref.watch(voucherDetailProvider(id));

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(voucherDetailProvider)),
      data: (v) {
        if (v == null) {
          return const EmptyState(icon: Icons.search_off_rounded, title: 'Voucher not found', message: 'It may have been deleted.');
        }
        final lines = List<Map<String, dynamic>>.from(v['voucher_lines'] as List)..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));
        final status = '${v['status']}';
        final canApprove = perms.can(Modules.finance, PermAction.approve);
        final canWrite = perms.can(Modules.finance, PermAction.create) || perms.can(Modules.finance, PermAction.edit);
        final isOpen = status == 'draft' || status == 'rejected';
        final reversed = v['reversed_by'] != null;
        final isReversal = v['reversal_of'] != null;

        return AppPage(
          title: '${v['voucher_no']}',
          subtitle: voucherTypeLabels['${v['voucher_type']}'],
          maxWidth: 1000,
          actions: [
            AppButton(label: 'Print or save PDF', icon: Icons.print_outlined, kind: AppButtonKind.secondary, loading: _busy, onPressed: () => _print(v, lines)),
            if (isOpen && canWrite) AppButton(label: 'Edit', icon: Icons.edit_outlined, kind: AppButtonKind.secondary, onPressed: _busy ? null : () => context.go('/finance/vouchers/$id/edit')),
            if (isOpen && canWrite) AppButton(label: 'Submit for approval', onPressed: _busy ? null : () => _run(() => _rpc('submit_voucher'), 'Submitted for approval')),
            if (status == 'pending' && canApprove) AppButton(label: 'Approve', onPressed: _busy ? null : () => _run(() => _rpc('approve_voucher'), 'Voucher approved')),
            if (status == 'pending' && canApprove) AppButton(label: 'Reject', kind: AppButtonKind.danger, onPressed: _busy ? null : _reject),
            if ((isOpen || status == 'pending' || status == 'approved') && canApprove)
              AppButton(label: status == 'approved' ? 'Post' : 'Approve and post', onPressed: _busy ? null : _post),
            if (status == 'posted' && canApprove && !reversed && !isReversal)
              AppButton(label: 'Reverse', icon: Icons.undo_rounded, kind: AppButtonKind.danger, onPressed: _busy ? null : _reverse),
            if (isOpen && canWrite) AppButton(label: 'Delete', kind: AppButtonKind.ghost, onPressed: _busy ? null : _discard),
          ],
          children: [
            if (status == 'rejected' && v['rejection_reason'] != null)
              _banner(Icons.cancel_outlined, 'Rejected: ${v['rejection_reason']}', AppColors.dangerSoft, AppColors.danger),
            if (reversed) _banner(Icons.undo_rounded, 'This voucher was reversed by ${(v['reversed'] as Map?)?['voucher_no'] ?? 'another voucher'}.', AppColors.warningSoft, AppColors.warning),
            if (isReversal) _banner(Icons.undo_rounded, 'This voucher reverses ${(v['reversal'] as Map?)?['voucher_no'] ?? 'another voucher'}.', AppColors.infoSoft, AppColors.info),
            _header(v, status, m.currency),
            const SizedBox(height: 16),
            _linesCard(lines, v, m.currency),
            const SizedBox(height: 16),
            AttachmentsPanel(entityType: 'voucher', entityId: id, canUpload: perms.can(Modules.finance, PermAction.create)),
          ],
        );
      },
    );
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

  Widget _header(Map<String, dynamic> v, String status, String currency) {
    String who(String key) => ((v[key] as Map?)?['full_name'] as String?) ?? '--';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [StatusBadge.status(status), const Spacer(), Text(Fmt.money((v['total_amount'] as num?)?.toDouble() ?? 0, currency: currency), style: AppText.kpi)]),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _info('Date', Fmt.date(DateTime.tryParse('${v['voucher_date']}'))),
              _info('Reference', '${v['reference'] ?? '--'}'),
              _info('Branch', '${(v['branches'] as Map?)?['name'] ?? '--'}'),
              _info('Created by', who('creator')),
              if (v['approved_at'] != null) _info('Approved by', '${who('approver')}, ${Fmt.dateTime(Fmt.parse(v['approved_at'] as String?))}'),
              if (v['posted_at'] != null) _info('Posted by', '${who('poster')}, ${Fmt.dateTime(Fmt.parse(v['posted_at'] as String?))}'),
            ],
          ),
          if (v['narration'] != null) ...[
            const SizedBox(height: 16),
            Text('Narration', style: AppText.small),
            const SizedBox(height: 2),
            Text('${v['narration']}', style: AppText.body),
          ],
          if (v['source_id'] != null && (v['source_type'] == 'expense' || v['source_type'] == 'income')) ...[
            const SizedBox(height: 14),
            AppButton(
              label: 'View the ${v['source_type']} entry',
              kind: AppButtonKind.ghost,
              compact: true,
              onPressed: () => context.go('/finance/transactions?open=${v['source_id']}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linesCard(List<Map<String, dynamic>> lines, Map<String, dynamic> v, String currency) {
    String money(Object? raw) {
      final n = raw as num?;
      return n == null || n == 0 ? '' : Fmt.money(n.toDouble(), currency: currency);
    }
    Widget cell(String t, int flex, {bool right = false, bool head = false, bool strong = false}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: head ? AppText.small.copyWith(fontWeight: FontWeight.w600) : (strong ? AppText.bodyStrong : AppText.body)),
          ),
        );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(color: const Color(0xFFF7F9F8), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), child: Row(children: [cell('Account', 5, head: true), cell('Details', 4, head: true), cell('Debit', 3, right: true, head: true), cell('Credit', 3, right: true, head: true)])),
          for (final l in lines) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell('${(l['accounts'] as Map?)?['code'] ?? ''}  ${(l['accounts'] as Map?)?['name'] ?? ''}', 5, strong: true),
                  cell([if (l['description'] != null) l['description'], if ((l['parties'] as Map?)?['name'] != null) '(${(l['parties'] as Map)['name']})'].join(' '), 4),
                  cell(money(l['debit']), 3, right: true),
                  cell(money(l['credit']), 3, right: true),
                ],
              ),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [cell('', 5), cell('Total', 4, strong: true), cell(money(v['total_amount']), 3, right: true, strong: true), cell(money(v['total_amount']), 3, right: true, strong: true)]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Align(alignment: Alignment.centerLeft, child: Text(amountInWords((v['total_amount'] as num?) ?? 0, currency), style: AppText.small)),
          ),
        ],
      ),
    );
  }
}
