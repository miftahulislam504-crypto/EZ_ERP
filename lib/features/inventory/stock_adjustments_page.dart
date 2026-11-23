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
import '../trade/trade_models.dart';
import '../trade/trade_providers.dart';

/// Opening stock, count corrections, damaged, expired and lost stock, and internal issues.
class StockAdjustmentsPage extends ConsumerStatefulWidget {
  const StockAdjustmentsPage({super.key});

  @override
  ConsumerState<StockAdjustmentsPage> createState() => _StockAdjustmentsPageState();
}

class _StockAdjustmentsPageState extends ConsumerState<StockAdjustmentsPage> {
  int _filter = 0;
  String _search = '';

  static const _filters = <(String, List<String>)>[
    ('All', []),
    ('Draft', ['draft', 'rejected']),
    ('Awaiting approval', ['pending']),
    ('Approved', ['approved']),
    ('Posted', ['posted']),
    ('Cancelled', ['cancelled']),
  ];

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.inventory)) return const NoAccessView();
    final canCreate = perms.can(Modules.inventory, PermAction.create);
    final async = ref.watch(adjustmentsListProvider(m.orgId));

    return AppPage(
      title: 'Stock adjustments',
      subtitle: 'Opening stock, count corrections, damaged, expired and lost stock, and internal issues',
      actions: [
        if (canCreate) AppButton(label: 'New adjustment', icon: Icons.add_rounded, onPressed: () => context.go('/inventory/adjustments/new')),
      ],
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(adjustmentsListProvider)),
          data: (all) {
            final statuses = _filters[_filter].$2;
            final q = _search.trim().toLowerCase();
            final rows = all.where((r) {
              if (statuses.isNotEmpty && !statuses.contains(r['status'])) return false;
              return q.isEmpty || '${r['number']} ${r['notes'] ?? ''} ${adjustmentReasons[r['reason']] ?? ''}'.toLowerCase().contains(q);
            }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 700 ? 3 : 1;
                    final w = (c.maxWidth - (cols - 1) * 14) / cols;
                    final cards = [
                      StatCard(label: 'Awaiting approval', value: '${all.where((r) => r['status'] == 'pending').length}', icon: Icons.hourglass_top_rounded, tone: BadgeTone.warning),
                      StatCard(label: 'Approved, not posted', value: '${all.where((r) => r['status'] == 'approved').length}', icon: Icons.task_alt_rounded, tone: BadgeTone.info),
                      StatCard(label: 'Posted', value: '${all.where((r) => r['status'] == 'posted').length}', icon: Icons.inventory_rounded, tone: BadgeTone.success),
                    ];
                    return Wrap(spacing: 14, runSpacing: 14, children: [for (final s in cards) SizedBox(width: w, child: s)]);
                  },
                ),
                const SizedBox(height: 16),
                PillTabs(labels: [for (final f in _filters) f.$1], index: _filter, onChanged: (i) => setState(() => _filter = i)),
                const SizedBox(height: 14),
                SizedBox(width: context.isMobile ? double.infinity : 340, child: AppTextField(hint: 'Search number, reason or notes', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v))),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.tune_outlined,
                      title: all.isEmpty ? 'No stock adjustments yet' : 'Nothing matches',
                      message: all.isEmpty ? 'Post opening stock, correct a count, or write off damaged, expired or lost stock.' : 'Try a different filter or search.',
                      actionLabel: all.isEmpty && canCreate ? 'New adjustment' : null,
                      onAction: all.isEmpty && canCreate ? () => context.go('/inventory/adjustments/new') : null,
                    ),
                  )
                else
                  context.isMobile ? Column(children: [for (final r in rows) _card(r)]) : _table(rows),
              ],
            );
          },
        ),
      ],
    );
  }

  int _count(Map<String, dynamic> r) => (r['stock_adjustment_lines'] as List?)?.length ?? 0;

  Widget _table(List<Map<String, dynamic>> rows) {
    Widget head(String t, int flex) => Expanded(flex: flex, child: Text(t, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Number', 2), head('Date', 2), head('Reason', 3), head('Warehouse', 3), head('Items', 1), head('Created by', 3), head('Status', 2)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go('/inventory/adjustments/${r['id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('${r['number']}', style: AppText.bodyStrong)),
                    Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['adj_date']}')), style: AppText.body)),
                    Expanded(flex: 3, child: Text(adjustmentReasons['${r['reason']}'] ?? '${r['reason']}', style: AppText.body)),
                    Expanded(flex: 3, child: Text('${(r['warehouse'] as Map?)?['name'] ?? '--'}', style: AppText.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 1, child: Text('${_count(r)}', style: AppText.body)),
                    Expanded(flex: 3, child: Text('${(r['creator'] as Map?)?['full_name'] ?? '--'}', style: AppText.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: StatusBadge.status('${r['status']}'))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go('/inventory/adjustments/${r['id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text('${r['number']}', style: AppText.bodyStrong)), StatusBadge.status('${r['status']}')]),
            Text('${adjustmentReasons['${r['reason']}'] ?? ''}, ${Fmt.date(DateTime.tryParse('${r['adj_date']}'))}', style: AppText.small),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('${(r['warehouse'] as Map?)?['name'] ?? '--'}, ${_count(r)} item${_count(r) == 1 ? '' : 's'}', style: AppText.body)),
          ],
        ),
      ),
    );
  }
}
