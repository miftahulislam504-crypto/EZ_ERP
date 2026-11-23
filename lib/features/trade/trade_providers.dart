import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../shared/crud/crud_config.dart';
import '../finance/finance_providers.dart';
import '../payments/payment_providers.dart';

String? _org(Ref ref) => ref.watch(activeMembershipProvider.select((m) => m?.orgId));

Rows _rows(Object? raw) => List<Map<String, dynamic>>.from(raw as List);

// ---------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------
typedef TradeListKey = ({String org, String type});

/// All documents of one type, newest first. Filtering by status happens on screen.
final tradeListProvider = FutureProvider.autoDispose.family<Rows, TradeListKey>((ref, k) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('trade_documents')
      .select(
        'id, number, doc_date, due_date, expected_date, status, reference, total, party_id, is_opening, '
        'party:parties(name), warehouse:warehouses(name), creator:profiles!created_by(full_name)',
      )
      .eq('org_id', k.org)
      .eq('doc_type', k.type)
      .order('doc_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(500);
  return _rows(rows);
});

/// One document with its lines and the people and records it points to.
final tradeDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('trade_documents').select(
        '*, party:parties(id, name, code, phone, email), warehouse:warehouses(name), branch:branches(name), '
        'department:departments(name), creator:profiles!created_by(full_name), approver:profiles!approved_by(full_name), '
        'poster:profiles!posted_by(full_name), voucher:vouchers!voucher_id(id, voucher_no), '
        'source:trade_documents!source_id(id, number, doc_type), '
        'trade_document_lines(id, line_no, product_id, description, quantity, unit_price, discount_amount, tax_rate_id, tax_rate, '
        'tax_amount, net_amount, line_total, account_id, source_line_id, product:products(name, sku, track_inventory, item_type), '
        'account:accounts!account_id(code, name), tax:tax_rates!tax_rate_id(name))',
      ).eq('id', id).maybeSingle();
});

/// Documents linked to this one: where it came from and what was created from it.
final relatedDocumentsProvider = FutureProvider.autoDispose.family<Rows, String>((ref, id) async {
  final rows = await ref.watch(supabaseProvider).rpc('related_documents', params: {'p_doc': id});
  return _rows(rows);
});

/// Ordered, received and billed quantity per line of a purchase order.
final orderProgressProvider = FutureProvider.autoDispose.family<Map<String, ({double ordered, double received, double billed})>, String>((ref, id) async {
  final rows = await ref.watch(supabaseProvider).rpc('purchase_order_progress', params: {'p_doc': id});
  return {
    for (final r in (rows as List))
      (r as Map)['line_id'] as String: (
        ordered: (r['ordered_qty'] as num).toDouble(),
        received: (r['received_qty'] as num).toDouble(),
        billed: (r['billed_qty'] as num).toDouble(),
      ),
  };
});

typedef SalesProgressKey = ({String doc, String? exclude});

/// Ordered, invoiced and committed quantity per line of a sales order. Committed
/// counts every live invoice, drafts included, so it is what is left to invoice.
final salesOrderProgressProvider = FutureProvider.autoDispose.family<Map<String, ({double ordered, double invoiced, double committed})>, SalesProgressKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('sales_order_progress', params: {'p_doc': k.doc, 'p_exclude': k.exclude});
  return {
    for (final r in (rows as List))
      (r as Map)['line_id'] as String: (
        ordered: (r['ordered_qty'] as num).toDouble(),
        invoiced: (r['invoiced_qty'] as num).toDouble(),
        committed: (r['committed_qty'] as num).toDouble(),
      ),
  };
});

typedef PartyKey = ({String org, String party, String? excludeBill});

/// Posted receipt lines of one supplier that have not been fully billed.
final unbilledReceiptLinesProvider = FutureProvider.autoDispose.family<Rows, PartyKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc(
    'unbilled_receipt_lines',
    params: {'p_org': k.org, 'p_party': k.party, 'p_exclude_bill': k.excludeBill},
  );
  return _rows(rows);
});

/// Service and non-stock order lines of one supplier that have not been fully billed.
final unbilledOrderLinesProvider = FutureProvider.autoDispose.family<Rows, PartyKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc(
    'unbilled_order_lines',
    params: {'p_org': k.org, 'p_party': k.party, 'p_exclude_bill': k.excludeBill},
  );
  return _rows(rows);
});

// ---------------------------------------------------------------------
// Pick lists
// ---------------------------------------------------------------------
final supplierOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final org = _org(ref);
  if (org == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('parties')
      .select('id, name, code')
      .eq('org_id', org)
      .eq('is_supplier', true)
      .eq('is_active', true)
      .order('name');
  return [for (final r in rows) Option(r['id'] as String, '${r['name']}  (${r['code']})')];
});

final customerOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final org = _org(ref);
  if (org == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('parties')
      .select('id, name, code')
      .eq('org_id', org)
      .eq('is_customer', true)
      .eq('is_active', true)
      .order('name');
  return [for (final r in rows) Option(r['id'] as String, '${r['name']}  (${r['code']})')];
});

final warehouseOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final org = _org(ref);
  if (org == null) return const <Option>[];
  final rows = await ref.watch(supabaseProvider).from('warehouses').select('id, name, is_default').eq('org_id', org).eq('is_active', true).order('name');
  return [for (final r in rows) Option(r['id'] as String, '${r['name']}')];
});

/// The default warehouse, used to prefill forms.
final defaultWarehouseProvider = FutureProvider.autoDispose<String?>((ref) async {
  final org = _org(ref);
  if (org == null) return null;
  final rows = await ref.watch(supabaseProvider).from('warehouses').select('id').eq('org_id', org).eq('is_active', true).eq('is_default', true).limit(1);
  return rows.isEmpty ? null : rows.first['id'] as String;
});

final departmentOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final org = _org(ref);
  if (org == null) return const <Option>[];
  final rows = await ref.watch(supabaseProvider).from('departments').select('id, name').eq('org_id', org).eq('is_active', true).order('name');
  return [for (final r in rows) Option(r['id'] as String, '${r['name']}')];
});

/// Items that can be put on a purchase document, with what the form needs to
/// decide whether a line is a stock line.
final productCatalogProvider = FutureProvider.autoDispose<Rows>((ref) async {
  final org = _org(ref);
  if (org == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('products')
      .select('id, sku, name, item_type, track_inventory, tax_rate_id, purchase_price, sales_price, unit:lookups!unit_id(name)')
      .eq('org_id', org)
      .eq('is_active', true)
      .order('name');
  return _rows(rows);
});

/// Whether a catalog item is kept in stock (receipts and adjustments apply).
bool isStockItem(Map<String, dynamic>? p) => p != null && p['track_inventory'] == true && p['item_type'] != 'service';

/// Tax rates usable on purchases.
final purchaseTaxRatesProvider = FutureProvider.autoDispose<Rows>((ref) async {
  final org = _org(ref);
  if (org == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('tax_rates')
      .select('id, name, rate, applies_to')
      .eq('org_id', org)
      .eq('is_active', true)
      .inFilter('applies_to', ['purchase', 'both'])
      .order('name');
  return _rows(rows);
});

/// Tax rates usable on sales.
final salesTaxRatesProvider = FutureProvider.autoDispose<Rows>((ref) async {
  final org = _org(ref);
  if (org == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('tax_rates')
      .select('id, name, rate, applies_to')
      .eq('org_id', org)
      .eq('is_active', true)
      .inFilter('applies_to', ['sales', 'both'])
      .order('name');
  return _rows(rows);
});

/// Expense and asset accounts a bill line can be booked to.
final billAccountOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  return [
    for (final r in accounts)
      if (r['is_active'] == true && r['is_group'] != true && (r['account_type'] == 'expense' || r['account_type'] == 'asset'))
        Option(r['id'] as String, '${r['code']}  ${r['name']}'),
  ];
});

/// Most recent receipt cost per item. Empty for people without access.
final lastPurchasePricesProvider = FutureProvider.autoDispose<Map<String, Map<String, dynamic>>>((ref) async {
  final org = _org(ref);
  if (org == null) return const {};
  try {
    final rows = await ref.watch(supabaseProvider).rpc('last_purchase_prices', params: {'p_org': org});
    return {for (final r in (rows as List)) (r as Map)['product_id'] as String: Map<String, dynamic>.from(r)};
  } catch (_) {
    return const {};
  }
});

// ---------------------------------------------------------------------
// Stock
// ---------------------------------------------------------------------
typedef StockKey = ({String org, String? warehouse});

final stockSummaryProvider = FutureProvider.autoDispose.family<Rows, StockKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('stock_summary', params: {'p_org': k.org, 'p_warehouse': k.warehouse});
  return _rows(rows);
});

/// Quantity on hand per item and warehouse.
final stockOnHandProvider = FutureProvider.autoDispose.family<Rows, StockKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('stock_on_hand', params: {'p_org': k.org, 'p_warehouse': k.warehouse});
  return _rows(rows);
});

typedef LedgerKey = ({String org, String product, String? warehouse, String? from, String? to});

final stockLedgerProvider = FutureProvider.autoDispose.family<Rows, LedgerKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc(
    'stock_ledger',
    params: {'p_org': k.org, 'p_product': k.product, 'p_warehouse': k.warehouse, 'p_from': k.from, 'p_to': k.to},
  );
  return _rows(rows);
});

// ---------------------------------------------------------------------
// Stock adjustments
// ---------------------------------------------------------------------
final adjustmentsListProvider = FutureProvider.autoDispose.family<Rows, String>((ref, org) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('stock_adjustments')
      .select('id, number, adj_date, reason, status, notes, warehouse:warehouses(name), creator:profiles!created_by(full_name), stock_adjustment_lines(id)')
      .eq('org_id', org)
      .order('adj_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(300);
  return _rows(rows);
});

final adjustmentDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('stock_adjustments').select(
        '*, warehouse:warehouses(name), creator:profiles!created_by(full_name), approver:profiles!approved_by(full_name), '
        'poster:profiles!posted_by(full_name), voucher:vouchers!voucher_id(id, voucher_no), '
        'stock_adjustment_lines(id, line_no, product_id, quantity_change, unit_cost, note, product:products(name, sku, unit:lookups!unit_id(name)))',
      ).eq('id', id).maybeSingle();
});

/// Stock movements written by one document, so a posted adjustment can show what it cost.
final movementsForSourceProvider = FutureProvider.autoDispose.family<Rows, String>((ref, sourceId) async {
  try {
    final rows = await ref.watch(supabaseProvider).from('stock_movements').select('source_line_id, quantity, unit_cost, value').eq('source_id', sourceId);
    return _rows(rows);
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
});

/// Refreshes every list that a purchase, sales, payment or stock action can change.
void invalidateTrade(WidgetRef ref) {
  ref.invalidate(tradeListProvider);
  ref.invalidate(tradeDetailProvider);
  ref.invalidate(relatedDocumentsProvider);
  ref.invalidate(orderProgressProvider);
  ref.invalidate(salesOrderProgressProvider);
  ref.invalidate(unbilledReceiptLinesProvider);
  ref.invalidate(unbilledOrderLinesProvider);
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(stockOnHandProvider);
  ref.invalidate(stockLedgerProvider);
  ref.invalidate(adjustmentsListProvider);
  ref.invalidate(adjustmentDetailProvider);
  ref.invalidate(movementsForSourceProvider);
  ref.invalidate(lastPurchasePricesProvider);
  ref.invalidate(balancesProvider);
  invalidatePayments(ref);
}
