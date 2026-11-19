import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../permissions/permissions.dart';
import 'models.dart';

/// Overridden in main() once SharedPreferences is ready.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// The signed-in user's id. Comparing ids (not User objects) means hourly token
/// refreshes do not rebuild everything that depends on the user.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final row = await ref.watch(supabaseProvider).from('profiles').select().eq('id', uid).maybeSingle();
  return row == null ? null : Profile.fromJson(row);
});

/// Companies the signed-in user belongs to. Pending invitations for the
/// user's email are claimed first so invited users land in the right company.
final membershipsProvider = FutureProvider<List<Membership>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const <Membership>[];
  final client = ref.watch(supabaseProvider);
  try {
    await client.rpc('claim_invitations');
  } catch (_) {
    // Claiming is best effort; membership loading below is what matters.
  }
  final rows = await client
      .from('organization_members')
      .select('id, org_id, role_id, branch_ids, organizations(name, logo_url, currency_code, fiscal_year_start_month), roles(name, is_owner)')
      .eq('user_id', uid)
      .eq('status', 'active');
  return rows.map((r) => Membership.fromJson(r)).toList();
});

class ActiveOrgNotifier extends Notifier<String?> {
  static const _key = 'active_org_id';

  @override
  String? build() => ref.read(sharedPrefsProvider).getString(_key);

  Future<void> select(String orgId) async {
    state = orgId;
    await ref.read(sharedPrefsProvider).setString(_key, orgId);
  }
}

final activeOrgIdProvider = NotifierProvider<ActiveOrgNotifier, String?>(ActiveOrgNotifier.new);

/// The company the user is currently working in.
final activeMembershipProvider = Provider<Membership?>((ref) {
  final list = ref.watch(membershipsProvider).valueOrNull ?? const <Membership>[];
  if (list.isEmpty) return null;
  final id = ref.watch(activeOrgIdProvider);
  return list.firstWhere((m) => m.orgId == id, orElse: () => list.first);
});

final permissionsProvider = FutureProvider<PermissionSet>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return PermissionSet.empty;
  if (m.isOwner) return PermissionSet.owner;
  final rows = await ref.watch(supabaseProvider).from('role_permissions').select().eq('role_id', m.roleId);
  return PermissionSet.fromRows(rows);
});

/// Synchronous access to permissions. Owners resolve immediately.
final permsProvider = Provider<PermissionSet>((ref) {
  final m = ref.watch(activeMembershipProvider);
  if (m != null && m.isOwner) return PermissionSet.owner;
  return ref.watch(permissionsProvider).valueOrNull ?? PermissionSet.empty;
});

/// Branches the user may work in (respecting per-member branch scope).
final branchesProvider = FutureProvider<List<BranchRef>>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return const <BranchRef>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('branches')
      .select('id, code, name, is_head_office')
      .eq('org_id', m.orgId)
      .eq('is_active', true)
      .order('is_head_office', ascending: false)
      .order('name');
  return rows
      .map((r) => BranchRef.fromJson(r))
      .where((b) => m.branchIds.isEmpty || m.branchIds.contains(b.id))
      .toList();
});

/// Branch filter used by dashboards and reports. Null means all branches.
class ActiveBranchNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(activeMembershipProvider.select((m) => m?.orgId));
    return null;
  }

  void select(String? branchId) => state = branchId;
}

final activeBranchIdProvider = NotifierProvider<ActiveBranchNotifier, String?>(ActiveBranchNotifier.new);
