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
import 'finance_providers.dart';
import 'voucher_pdf.dart';

typedef _VKey = ({String org, String type, String status});

final vouchersListProvider = FutureProvider.autoDispose.family<Rows, _VKey>((ref, k) async {
  var q = ref
      .watch(supabaseProvider)
      .from('vouchers')
      .select('id, voucher_no, voucher_type, voucher_date, status, narration, reference, total_amount, reversed_by, reversal_of')
      .eq('org_id', k.org);
  if (k.type.isNotEmpty) q = q.eq('voucher_type', k.type);
  if (k.status.isNotEmpty) q = q.eq('status', k.status);
  final rows = await q.order('voucher_date', ascending: false).order('created_at', ascending: false).limit(300);
  return List<Map<String, dynamic>>.from(rows);
});

class VouchersPage extends ConsumerStatefulWidget {
  const VouchersPage({super.key});

  @override
  ConsumerState<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends ConsumerState<VouchersPage> {
  String _type = '';
  String _status = '';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.finance)) return const NoAccessView();
    final canCreate = perms.can(Modules.finance, PermAction.create);
    final showMoney = perms.canView(Modules.financialData);
    final async = ref.watch(vouchersListProvider((org: m.orgId, type: _type, status: _status)));

    return AppPage(
      title: 'Vouchers',
      subtitle: 'Journal, payment, receipt and contra vouchers',
      actions: [
        if (canCreate)
          PopupMenuButton<String>(
            tooltip: 'Create a voucher',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            onSelected: (t) => context.go('/finance/vouchers/new?type=$t'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'payment', child: Text('Payment voucher')),
              PopupMenuItem(value: 'receipt', child: Text('Receipt voucher')),
              PopupMenuItem(value: 'contra', child: Text('Contra voucher (transfer)')),
              PopupMenuItem(value: 'journal', child: Text('Journal voucher')),
            ],
            child: IgnorePointer(child: AppButton(label: 'New voucher', icon: Icons.add_rounded, onPressed: () {})),
          ),
      ],
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: context.isMobile ? double.infinity : 320,
              child: AppTextField(hint: 'Search number, narration or reference', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v)),
            ),
            SizedBox(
              width: context.isMobile ? double.infinity : 200,
              child: AppDropdown<String>(
                value: _type,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All types')),
                  for (final e in voucherTypeLabels.entries.take(4)) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _type = v ?? ''),
              ),
            ),
            SizedBox(
              width: context.isMobile ? double.infinity : 200,
              child: AppDropdown<String>(
                value: _status,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All statuses')),
                  for (final s in const ['draft', 'pending', 'approved', 'rejected', 'posted']) DropdownMenuItem(value: s, child: Text(Fmt.humanize(s))),
                ],
                onChanged: (v) => setState(() => _status = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(vouchersListProvider)),
          data: (all) {
            final q = _search.trim().toLowerCase();
            final rows = all.where((r) => q.isEmpty || '${r['voucher_no']} ${r['narration'] ?? ''} ${r['reference'] ?? ''}'.toLowerCase().contains(q)).toList();
            if (rows.isEmpty) {
              return AppCard(
                child: EmptyState(
                  icon: Icons.edit_note_outlined,
                  title: all.isEmpty ? 'No vouchers yet' : 'No matching vouchers',
                  message: all.isEmpty ? 'Record a payment, receipt, transfer or journal entry to start your books.' : 'Try a different search or filter.',
                  actionLabel: all.isEmpty && canCreate ? 'New payment voucher' : null,
                  onAction: all.isEmpty && canCreate ? () => context.go('/finance/vouchers/new?type=payment') : null,
                ),
              );
            }
            return context.isMobile
                ? Column(children: [for (final r in rows) _mobileCard(r, m.currency, showMoney)])
                : _table(rows, m.currency, showMoney);
          },
        ),
      ],
    );
  }

  Widget _statusBadge(Map<String, dynamic> r) {
    if (r['reversed_by'] != null) return const StatusBadge('Reversed', tone: BadgeTone.neutral);
    return StatusBadge.status('${r['status']}');
  }

  Widget _table(Rows rows, String currency, bool showMoney) {
    Widget head(String t, int flex, {bool right = false}) =>
        Expanded(flex: flex, child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Voucher', 2), head('Date', 2), head('Type', 2), head('Narration', 5), if (showMoney) head('Amount', 2, right: true), const SizedBox(width: 20), head('Status', 2)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go('/finance/vouchers/${r['id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('${r['voucher_no']}', style: AppText.bodyStrong)),
                    Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['voucher_date']}')), style: AppText.body)),
                    Expanded(flex: 2, child: Text(voucherTypeLabels['${r['voucher_type']}'] ?? '', style: AppText.body)),
                    Expanded(flex: 5, child: Text('${r['narration'] ?? r['reference'] ?? '--'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                    if (showMoney)
                      Expanded(flex: 2, child: Text(Fmt.money((r['total_amount'] as num?)?.toDouble() ?? 0, currency: currency), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _statusBadge(r))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileCard(Map<String, dynamic> r, String currency, bool showMoney) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go('/finance/vouchers/${r['id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${r['voucher_no']}', style: AppText.bodyStrong)),
                _statusBadge(r),
              ],
            ),
            const SizedBox(height: 2),
            Text('${voucherTypeLabels['${r['voucher_type']}'] ?? ''}, ${Fmt.date(DateTime.tryParse('${r['voucher_date']}'))}', style: AppText.small),
            if (r['narration'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['narration']}', style: AppText.body, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (showMoney) Padding(padding: const EdgeInsets.only(top: 6), child: Text(Fmt.money((r['total_amount'] as num?)?.toDouble() ?? 0, currency: currency), style: AppText.label)),
          ],
        ),
      ),
    );
  }
}
