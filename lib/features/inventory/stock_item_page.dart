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
import '../finance/finance_providers.dart';
import '../trade/trade_models.dart';
import '../trade/trade_providers.dart';
import 'stock_overview_page.dart';

final _productProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('products').select('id, sku, name, item_type, track_inventory, min_stock, reorder_level, unit:lookups!unit_id(name), category:lookups!category_id(name)').eq('id', id).maybeSingle();
});

/// The stock card of one item: where it is held, what it last cost and every
/// movement that changed its quantity.
class StockItemPage extends ConsumerStatefulWidget {
  const StockItemPage({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<StockItemPage> createState() => _StockItemPageState();
}

class _StockItemPageState extends ConsumerState<StockItemPage> {
  String? _warehouse;
  String? _from;
  String? _to;

  String? _sourcePath(Map<String, dynamic> r) {
    final id = r['source_id'];
    if (id == null) return null;
    return switch (r['source_type']) {
      'goods_receipt' => '/purchase/receipts/$id',
      'sales_invoice' => '/sales/invoices/$id',
      'stock_adjustment' => '/inventory/adjustments/$id',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.inventory)) return const NoAccessView();
    final product = ref.watch(_productProvider(widget.productId));
    final warehouses = ref.watch(warehouseOptions).valueOrNull ?? const [];
    final onHand = ref.watch(stockOnHandProvider((org: m.orgId, warehouse: null))).valueOrNull ?? <Map<String, dynamic>>[];
    final last = ref.watch(lastPurchasePricesProvider).valueOrNull?[widget.productId];
    final ledger = ref.watch(stockLedgerProvider((org: m.orgId, product: widget.productId, warehouse: _warehouse, from: _from, to: _to)));
    final showCost = perms.canView(Modules.financialData);

    return product.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_productProvider)),
      data: (p) {
        if (p == null) {
          return EmptyState(icon: Icons.search_off_rounded, title: 'Item not found', actionLabel: 'Back to stock', onAction: () => context.go('/inventory/stock'));
        }
        final mine = onHand.where((r) => r['product_id'] == widget.productId).toList();
        final total = mine.fold<double>(0, (s, r) => s + (r['quantity'] as num).toDouble());
        String warehouseName(Object? id) => warehouses.where((w) => w.value == id).map((w) => w.label).firstOrNull ?? '--';
        final level = stockLevel({'quantity': total, 'min_stock': p['min_stock'], 'reorder_level': p['reorder_level']});

        return AppPage(
          title: '${p['name']}',
          subtitle: '${p['sku']}${(p['category'] as Map?)?['name'] != null ? '   ${(p['category'] as Map)['name']}' : ''}',
          maxWidth: 1100,
          actions: [
            AppButton(label: 'Back to stock', icon: Icons.arrow_back_rounded, kind: AppButtonKind.secondary, onPressed: () => context.go('/inventory/stock')),
            if (perms.can(Modules.inventory, PermAction.create)) AppButton(label: 'Adjust stock', icon: Icons.tune_outlined, onPressed: () => context.go('/inventory/adjustments/new')),
          ],
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('${qtyText(total)} ${(p['unit'] as Map?)?['name'] ?? ''}'.trim(), style: AppText.kpi),
                    const SizedBox(width: 12),
                    stockLevelBadge(level),
                  ]),
                  const SizedBox(height: 4),
                  Text('On hand across all warehouses', style: AppText.small),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 32,
                    runSpacing: 14,
                    children: [
                      for (final r in mine)
                        SizedBox(
                          width: 190,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(warehouseName(r['warehouse_id']), style: AppText.small), Text(qtyText(r['quantity'] as num), style: AppText.bodyStrong)]),
                        ),
                      if (mine.isEmpty) Text('No stock is held in any warehouse.', style: AppText.body),
                    ],
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 18),
                    Text('Last purchase', style: AppText.small),
                    Text(
                      '${Fmt.money((last['unit_cost'] as num).toDouble(), currency: m.currency)} on ${Fmt.date(DateTime.tryParse('${last['purchase_date']}'))}${last['supplier_name'] != null ? ' from ${last['supplier_name']}' : ''}',
                      style: AppText.bodyStrong,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: context.isMobile ? double.infinity : 240,
                  child: AppDropdown<String?>(
                    label: 'Warehouse',
                    value: _warehouse,
                    items: [const DropdownMenuItem<String?>(value: null, child: Text('All warehouses')), for (final w in warehouses) DropdownMenuItem<String?>(value: w.value, child: Text(w.label))],
                    onChanged: (v) => setState(() => _warehouse = v),
                  ),
                ),
                SizedBox(width: context.isMobile ? double.infinity : 200, child: AppDateField(label: 'From', value: _from, onChanged: (v) => setState(() => _from = v))),
                SizedBox(width: context.isMobile ? double.infinity : 200, child: AppDateField(label: 'To', value: _to, onChanged: (v) => setState(() => _to = v))),
                if (_from != null || _to != null)
                  Padding(padding: const EdgeInsets.only(top: 24), child: AppButton(label: 'Clear dates', kind: AppButtonKind.ghost, compact: true, onPressed: () => setState(() {
                        _from = null;
                        _to = null;
                      }))),
              ],
            ),
            const SizedBox(height: 16),
            ledger.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(stockLedgerProvider)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const AppCard(child: EmptyState(icon: Icons.swap_vert_rounded, title: 'No stock movements', message: 'Receipts, adjustments and sales will appear here as they happen.'));
                }
                return context.isMobile ? Column(children: [for (final r in rows) _card(r, m.currency, showCost)]) : _table(rows, m.currency, showCost);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _qty(Map<String, dynamic> r) {
    final q = (r['quantity'] as num).toDouble();
    return Text('${q > 0 ? '+' : ''}${qtyText(q)}', style: AppText.bodyStrong.copyWith(color: q > 0 ? AppColors.success : AppColors.danger));
  }

  Widget _table(Rows rows, String currency, bool showCost) {
    Widget head(String t, int flex, {bool right = false}) => Expanded(flex: flex, child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: AppText.small.copyWith(fontWeight: FontWeight.w600)));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F9F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [head('Date', 2), head('Movement', 3), head('Warehouse', 3), head('Reference', 3), head('Change', 2, right: true), head('Balance', 2, right: true), if (showCost) head('Unit cost', 2, right: true), if (showCost) head('Value', 3, right: true)]),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: _sourcePath(r) == null ? null : () => context.go(_sourcePath(r)!),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(Fmt.date(DateTime.tryParse('${r['movement_date']}')), style: AppText.body)),
                    Expanded(flex: 3, child: Text(movementLabels['${r['movement_type']}'] ?? '${r['movement_type']}', style: AppText.body)),
                    Expanded(flex: 3, child: Text('${r['warehouse']}', style: AppText.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text('${r['reference'] ?? '--'}', style: AppText.body.copyWith(color: _sourcePath(r) == null ? null : AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: _qty(r))),
                    Expanded(flex: 2, child: Text(qtyText(r['running_qty'] as num), textAlign: TextAlign.right, style: AppText.body)),
                    if (showCost) Expanded(flex: 2, child: Text(r['unit_cost'] == null ? '--' : Fmt.money((r['unit_cost'] as num).toDouble(), currency: currency), textAlign: TextAlign.right, style: AppText.body)),
                    if (showCost) Expanded(flex: 3, child: Text(r['value'] == null ? '--' : Fmt.money((r['value'] as num).toDouble(), currency: currency), textAlign: TextAlign.right, style: AppText.body)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r, String currency, bool showCost) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: _sourcePath(r) == null ? null : () => context.go(_sourcePath(r)!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text(movementLabels['${r['movement_type']}'] ?? '${r['movement_type']}', style: AppText.bodyStrong)), _qty(r)]),
            Text('${Fmt.date(DateTime.tryParse('${r['movement_date']}'))}, ${r['warehouse']}${r['reference'] != null ? ', ${r['reference']}' : ''}', style: AppText.small),
            const SizedBox(height: 4),
            Text('Balance ${qtyText(r['running_qty'] as num)}${showCost && r['value'] != null ? '   ${Fmt.money((r['value'] as num).toDouble(), currency: currency)}' : ''}', style: AppText.body),
          ],
        ),
      ),
    );
  }
}
