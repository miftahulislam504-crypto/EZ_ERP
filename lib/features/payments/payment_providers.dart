import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../shared/crud/crud_config.dart';
import '../finance/finance_providers.dart';

Rows _rows(Object? raw) => List<Map<String, dynamic>>.from(raw as List);

// ---------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------
typedef PaymentListKey = ({String org, String kind, String? party});

/// Receipts or supplier payments, newest first. Amounts still unapplied come from [paymentBalancesProvider].
final paymentsListProvider = FutureProvider.autoDispose.family<Rows, PaymentListKey>((ref, k) async {
  final base = ref
      .watch(supabaseProvider)
      .from('payments')
      .select('id, number, kind, pay_date, amount, status, reference, party_id, party:parties(name), account:financial_accounts(name), method:lookups(name)')
      .eq('org_id', k.org)
      .eq('kind', k.kind);
  final filtered = k.party == null ? base : base.eq('party_id', k.party!);
  final rows = await filtered.order('pay_date', ascending: false).order('created_at', ascending: false).limit(500);
  return _rows(rows);
});

typedef PaymentKindKey = ({String org, String kind});

/// Allocated and unapplied amount of every payment of one kind.
final paymentBalancesProvider = FutureProvider.autoDispose.family<Map<String, ({double allocated, double unallocated})>, PaymentKindKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).from('payment_balances').select('payment_id, allocated, unallocated').eq('org_id', k.org).eq('kind', k.kind).limit(1000);
  return {
    for (final r in rows) r['payment_id'] as String: (allocated: (r['allocated'] as num).toDouble(), unallocated: (r['unallocated'] as num).toDouble()),
  };
});

/// One payment with the documents it was applied to.
final paymentDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('payments').select(
        '*, party:parties(id, name, code, is_customer, is_supplier), account:financial_accounts(id, name, kind), method:lookups(name), '
        'creator:profiles!created_by(full_name), voucher:vouchers!voucher_id(id, voucher_no), '
        'payment_allocations(id, amount, alloc_date, reversed_at, voucher_id, document:trade_documents(id, number, doc_type, doc_date, due_date))',
      ).eq('id', id).maybeSingle();
});

// ---------------------------------------------------------------------
// Document balances
// ---------------------------------------------------------------------
typedef DocBalanceKey = ({String org, String type});

/// Paid amount, balance and payment status of every posted invoice or bill, by document id.
final documentBalancesProvider = FutureProvider.autoDispose.family<Map<String, Map<String, dynamic>>, DocBalanceKey>((ref, k) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('document_balances')
      .select('document_id, paid, balance, payment_status, days_overdue')
      .eq('org_id', k.org)
      .eq('doc_type', k.type)
      .order('doc_date', ascending: false)
      .limit(1000);
  return {for (final r in rows) r['document_id'] as String: Map<String, dynamic>.from(r)};
});

/// Payments applied to one invoice or bill.
final documentPaymentsProvider = FutureProvider.autoDispose.family<Rows, String>((ref, docId) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('payment_allocations')
      .select('id, amount, alloc_date, payment:payments(id, number, kind, pay_date, reference, status)')
      .eq('document_id', docId)
      .isFilter('reversed_at', null)
      .order('alloc_date');
  return _rows(rows);
});

// ---------------------------------------------------------------------
// Aging, statements and dues
// ---------------------------------------------------------------------
typedef AgingKey = ({String org, String side, String asOf});

/// Dues by customer or supplier in aging buckets.
final agingProvider = FutureProvider.autoDispose.family<Rows, AgingKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('party_aging', params: {'p_org': k.org, 'p_kind': k.side, 'p_as_of': k.asOf});
  return _rows(rows);
});

typedef OpenItemsKey = ({String org, String side, String? party, String? asOf});

/// Open invoices or bills with days past due. Used for drill-down and when choosing what a payment pays.
final openItemsProvider = FutureProvider.autoDispose.family<Rows, OpenItemsKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc(
    'aging_documents',
    params: {'p_org': k.org, 'p_kind': k.side, 'p_as_of': k.asOf, 'p_party': k.party},
  );
  return _rows(rows);
});

typedef StatementKey = ({String org, String party, String role, String? from, String? to});

final statementProvider = FutureProvider.autoDispose.family<Rows, StatementKey>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc(
    'party_statement',
    params: {'p_org': k.org, 'p_party': k.party, 'p_role': k.role, 'p_from': k.from, 'p_to': k.to},
  );
  return _rows(rows);
});

typedef PartyKeyOf = ({String org, String party});

/// Headline dues, advances and credit of one customer or supplier.
final partySummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, PartyKeyOf>((ref, k) async {
  final rows = await ref.watch(supabaseProvider).rpc('party_summary', params: {'p_org': k.org, 'p_party': k.party});
  final list = _rows(rows);
  return list.isEmpty ? null : list.first;
});

/// Ledger control accounts against the documents and advances behind them.
final controlCheckProvider = FutureProvider.autoDispose.family<Rows, String>((ref, org) async {
  try {
    final rows = await ref.watch(supabaseProvider).rpc('aging_control_check', params: {'p_org': org, 'p_as_of': null});
    return _rows(rows);
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
});

typedef PartyDocsKey = ({String org, String party, List<String> types});

/// Documents of one customer or supplier across the given types.
final partyDocumentsProvider = FutureProvider.autoDispose.family<Rows, PartyDocsKey>((ref, k) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('trade_documents')
      .select('id, number, doc_type, doc_date, due_date, expected_date, status, total, reference, is_opening')
      .eq('org_id', k.org)
      .eq('party_id', k.party)
      .inFilter('doc_type', k.types)
      .order('doc_date', ascending: false)
      .order('created_at', ascending: false)
      .limit(300);
  return _rows(rows);
});

/// One customer or supplier row, for the profile header.
final partyRowProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async {
  return await ref.watch(supabaseProvider).from('parties').select('*, customer_group:lookups!customer_group_id(name), supplier_category:lookups!supplier_category_id(name)').eq('id', id).maybeSingle();
});

// ---------------------------------------------------------------------
// Pick lists
// ---------------------------------------------------------------------
/// Active cash, bank and wallet accounts, for the account a payment moves through.
final cashBankOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final rows = await ref.watch(financialAccountsProvider.future);
  return [
    for (final r in rows)
      if (r['is_active'] == true) Option(r['id'] as String, r['bank_name'] == null ? '${r['name']}' : '${r['name']}  (${r['bank_name']})'),
  ];
});

/// Refreshes everything a payment, allocation or opening balance can change.
void invalidatePayments(WidgetRef ref) {
  ref.invalidate(paymentsListProvider);
  ref.invalidate(paymentBalancesProvider);
  ref.invalidate(paymentDetailProvider);
  ref.invalidate(documentBalancesProvider);
  ref.invalidate(documentPaymentsProvider);
  ref.invalidate(agingProvider);
  ref.invalidate(openItemsProvider);
  ref.invalidate(statementProvider);
  ref.invalidate(partySummaryProvider);
  ref.invalidate(controlCheckProvider);
  ref.invalidate(partyDocumentsProvider);
}
