import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../shared/crud/crud_config.dart';

typedef Rows = List<Map<String, dynamic>>;

const accountTypeLabels = {
  'asset': 'Assets',
  'liability': 'Liabilities',
  'equity': 'Equity',
  'income': 'Income',
  'expense': 'Expenses',
};

const accountTypeOrder = ['asset', 'liability', 'equity', 'income', 'expense'];

/// Closing balance in the account's natural direction (assets and expenses grow with debits).
double signedBalance(String type, double debit, double credit) =>
    (type == 'asset' || type == 'expense') ? debit - credit : credit - debit;

/// Every account in the chart, ordered by code.
final accountsProvider = FutureProvider.autoDispose<Rows>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('accounts')
      .select('id, code, name, account_type, parent_id, is_group, is_system, system_key, description, is_active')
      .eq('org_id', orgId)
      .order('code');
  return List<Map<String, dynamic>>.from(rows);
});

Option _accountOption(Map<String, dynamic> r) => Option(r['id'] as String, '${r['code']}  ${r['name']}');

List<Option> _leafOptions(Rows rows, [String? type]) => [
      for (final r in rows)
        if (r['is_active'] == true && r['is_group'] != true && (type == null || r['account_type'] == type)) _accountOption(r),
    ];

/// Accounts that can receive postings (not group accounts).
final postingAccountOptions = FutureProvider.autoDispose<List<Option>>((ref) async => _leafOptions(await ref.watch(accountsProvider.future)));
final expenseHeadOptions = FutureProvider.autoDispose<List<Option>>((ref) async => _leafOptions(await ref.watch(accountsProvider.future), 'expense'));
final incomeHeadOptions = FutureProvider.autoDispose<List<Option>>((ref) async => _leafOptions(await ref.watch(accountsProvider.future), 'income'));

/// Cash, bank and mobile wallet accounts with their ledger account.
final financialAccountsProvider = FutureProvider.autoDispose<Rows>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return <Map<String, dynamic>>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('financial_accounts')
      .select('id, kind, name, account_id, bank_name, branch_name, account_number, is_active')
      .eq('org_id', orgId)
      .order('kind')
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});

final financialAccountOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final rows = await ref.watch(financialAccountsProvider.future);
  return [for (final r in rows) if (r['is_active'] == true) Option(r['id'] as String, '${r['name']}')];
});

final partyOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('parties')
      .select('id, name, code')
      .eq('org_id', orgId)
      .eq('is_active', true)
      .order('name');
  return [for (final r in rows) Option(r['id'] as String, '${r['name']}  (${r['code']})')];
});

/// Posted debit and credit totals per account (only for users who may view finance).
final balancesProvider = FutureProvider.autoDispose<Map<String, ({double debit, double credit})>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return const {};
  final rows = await ref.watch(supabaseProvider).rpc('account_balances', params: {'p_org': orgId});
  return {
    for (final r in (rows as List))
      (r as Map)['account_id'] as String: (debit: (r['total_debit'] as num).toDouble(), credit: (r['total_credit'] as num).toDouble()),
  };
});
