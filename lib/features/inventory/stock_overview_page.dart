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

/// Stock level of an item: out, low (at or below its reorder point) or fine.
String stockLevel(Map<String, dynamic> r) {
  final qty = (r['quantity'] as num).toDouble();
  if (qty <= 0) return 'out';
  final min = (r['min_stock'] as num?)?.toDouble() ?? 0;
  final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
  final threshold = min > reorder ? min : reorder;
  return threshold > 0 && qty <= threshold ? 'low' : 'ok';
}

Widget stockLevelBadge(String level) => switch (level) {
      'out' => const StatusBadge('Out of stock', tone: BadgeTone.danger),
      'low' => const StatusBadge('Low stock', tone: BadgeTone.warning),
      _ => const StatusBadge('In stock', tone: BadgeTone.success),
    };

/// Current stock of every tracked item, with value and low stock warnings.
class StockOverviewPage extends ConsumerStatefulWidget {
  const StockOverviewPage({super.key});

  @override
  ConsumerState<StockOverviewPage> createState() => _StockOverviewPageState();
}

class _StockOverviewPageState extends ConsumerState<StockOverviewPage> {
  String? _warehouse;
  int _filter = 0;
  String _search = '';

  static const _filters = ['All items', 'Low stock', 'Out of stock'];

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.inventory)) return const NoAccessView();
    final canAdjust = perms.can(Modules.inventory, PermAction.create);
    final warehouses = ref.watch(warehouseOptions).valueOrNull ?? const [];
    final async = ref.watch(stockSummaryProvider((org: m.orgId, warehouse: _warehouse)));

    return AppPage(
      title: 'Stock overview',
      subtitle: 'Quantity on hand, value and reorder warnings for every tracked item',
      actions: [
        AppButton(label: 'Adjustments', icon: Icons.tune_outlined, kind: AppButtonKind.secondary, onPressed: () => context.go('/inventory/adjustments')),
        if (canAdjust) AppButton(label: 'New adjustment', icon: Icons.add_rounded, onPressed: () => context.go('/inventory/adjustments/new')),
      ],
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(stockSummaryProvider)),
          data: (all) {
            final q = _search.trim().toLowerCase();
            final rows = all.where((r) {
              final level = stockLevel(r);
              if (_filter == 1 && level != 'low') return false;
              if (_filter == 2 && level != 'out') return false;
              return q.isEmpty || '${r['name']} ${r['sku']} ${r['category'] ?? ''}'.toLowerCase().contains(q);
            }).toList();
            final hasValue = all.isNotEmpty && all.every((r) => r['value'] != null);
            final totalValue = all.fold<double>(0, (s, r) => s + ((r['value'] as num?)?.toDouble() ?? 0));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
                    final w = (c.maxWidth - (cols - 1) * 14) / cols;
                    final cards = [
                      StatCard(label: 'Tracked items', value: '${all.length}', icon: Icons.category_outlined),
                      StatCard(label: 'Stock value', value: hasValue ? Fmt.money(totalValue, currency: m.currency) : '--', icon: Icons.account_balance_wallet_outlined, hint: hasValue ? 'At weighted average cost' : 'Hidden without financial data access'),
                      StatCard(label: 'Low stock', value: '${all.where((r) => stockLevel(r) == 'low').length}', icon: Icons.trending_down_rounded, tone: BadgeTone.warning, onTap: () => setState(() => _filter = 1)),
                      StatCard(label: 'Out of stock', value: '${all.where((r) => stockLevel(r) == 'out').length}', icon: Icons.production_quantity_limits_rounded, tone: BadgeTone.danger, onTap: () => setState(() => _filter = 2)),
                    ];
                    return Wrap(spacing: 14, runSpacing: 14, children: [for (final s in cards) SizedBox(width: w, child: s)]);
                  },
                ),
                const SizedBox(height: 16),
                PillTabs(labels: _filters, index: _filter, onChanged: (i) => setState(() => _filter = i)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(width: context.isMobile ? double.infinity : 340, child: AppTextField(hint: 'Search item, SKU or category', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => _search = v))),
                    SizedBox(
                      width: context.isMobile ? double.infinity : 240,
                      child: AppDropdown<String?>(
                        value: _warehouse,
                        items: [const DropdownMenuItem<String?>(value: null, child: Text('All warehouses')), for (final w in warehouses) DropdownMenuItem<String?>(value: w.value, child: Text(w.label))],
                        onChanged: (v) => setState(() => _warehouse = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: all.isEmpty ? 'No tracked items yet' : 'Nothing matches',
                      message: all.isEmpty ? 'Add products that track stock, then receive goods or post opening stock.' : 'Try a different filter or search.',
                      actionLabel: all.isEmpty ? 'Go to products' : null,
                      onAction: all.isEmpty ? () => context.go('/inventory/products') : null,
                    ),
                  )
                else
                  context.isMobile ? Column(children: [for (final r in rows) _card(r, m.currency)]) : _table(rows, m.currency),
              ],
            );
          },
        ),
      ],
    );
  }

  String _money(Object? v, String currency) => v == null ? '--' : Fmt.money((v as num).toDouble(), currency: currency);

  Widget _table(List<Map<String, dynamic>> rows, String currency) {
    Widget head(String t, int flex, {bool right = false}) => Expanded(flex: flex, child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Item', 5), head('On hand', 2, right: true), head('Reorder at', 2, right: true), head('Average cost', 3, right: true), head('Value', 3, right: true), const SizedBox(width: 20), head('Status', 2)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: () => context.go('/inventory/stock/${r['product_id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['name']}', style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${r['sku']}${r['category'] != null ? '   ${r['category']}' : ''}', style: AppText.small),
                      ]),
                    ),
                    Expanded(flex: 2, child: Text('${qtyText(r['quantity'] as num)} ${r['unit'] ?? ''}'.trim(), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                    Expanded(flex: 2, child: Text(_reorderText(r), textAlign: TextAlign.right, style: AppText.body)),
                    Expanded(flex: 3, child: Text(_money(r['avg_cost'], currency), textAlign: TextAlign.right, style: AppText.body)),
                    Expanded(flex: 3, child: Text(_money(r['value'], currency), textAlign: TextAlign.right, style: AppText.bodyStrong)),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: stockLevelBadge(stockLevel(r)))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _reorderText(Map<String, dynamic> r) {
    final min = (r['min_stock'] as num?)?.toDouble() ?? 0;
    final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
    final v = min > reorder ? min : reorder;
    return v == 0 ? '--' : qtyText(v);
  }

  Widget _card(Map<String, dynamic> r, String currency) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go('/inventory/stock/${r['product_id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text('${r['name']}', style: AppText.bodyStrong)), stockLevelBadge(stockLevel(r))]),
            Text('${r['sku']}', style: AppText.small),
            const SizedBox(height: 6),
            Text('${qtyText(r['quantity'] as num)} ${r['unit'] ?? ''} on hand${r['value'] != null ? '   ${_money(r['value'], currency)}' : ''}'.trim(), style: AppText.label),
          ],
        ),
      ),
    );
  }
}
