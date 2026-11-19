import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/state/session.dart';
import 'crud_config.dart';

/// Dropdown option sources shared by master-data forms. They are auto-disposed,
/// so a dropdown always reflects values edited elsewhere a moment ago.

Future<List<Option>> _lookups(SupabaseClient client, String? orgId, String kind) async {
  if (orgId == null) return const <Option>[];
  final rows = await client
      .from('lookups')
      .select('id, name')
      .eq('org_id', orgId)
      .eq('kind', kind)
      .eq('is_active', true)
      .order('sort_order')
      .order('name');
  return rows.map((r) => Option(r['id'] as String, r['name'] as String)).toList();
}

AutoDisposeFutureProvider<List<Option>> _lookupSource(String kind) {
  return FutureProvider.autoDispose<List<Option>>((ref) {
    return _lookups(ref.watch(supabaseProvider), ref.watch(activeMembershipProvider.select((m) => m?.orgId)), kind);
  });
}

final unitOptions = _lookupSource('unit');
final productCategoryOptions = _lookupSource('product_category');
final brandOptions = _lookupSource('brand');
final customerGroupOptions = _lookupSource('customer_group');
final supplierCategoryOptions = _lookupSource('supplier_category');

final branchOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('branches')
      .select('id, name')
      .eq('org_id', orgId)
      .eq('is_active', true)
      .order('name');
  return rows.map((r) => Option(r['id'] as String, r['name'] as String)).toList();
});

final taxRateOptions = FutureProvider.autoDispose<List<Option>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('tax_rates')
      .select('id, name, rate')
      .eq('org_id', orgId)
      .eq('is_active', true)
      .order('name');
  return rows.map((r) => Option(r['id'] as String, '${r['name']} (${r['rate']}%)')).toList();
});

/// Business divisions used for address fields.
const bangladeshDivisions = <Option>[
  Option('Barishal', 'Barishal'),
  Option('Chattogram', 'Chattogram'),
  Option('Dhaka', 'Dhaka'),
  Option('Khulna', 'Khulna'),
  Option('Mymensingh', 'Mymensingh'),
  Option('Rajshahi', 'Rajshahi'),
  Option('Rangpur', 'Rangpur'),
  Option('Sylhet', 'Sylhet'),
];
