import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/crud_page.dart';

/// Active members, used to pick department heads and other owners.
final memberOptionsProvider = FutureProvider<List<Option>>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return const <Option>[];
  final rows = await ref
      .watch(supabaseProvider)
      .from('organization_members')
      .select('user_id, profiles(full_name, email)')
      .eq('org_id', m.orgId)
      .eq('status', 'active');
  final list = rows.map((r) {
    final p = r['profiles'] as Map?;
    final name = ((p?['full_name'] ?? p?['email']) ?? 'Member') as String;
    return Option(r['user_id'] as String, name);
  }).toList();
  list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return list;
});

final _branchConfig = CrudConfig(
  title: 'Branches',
  singular: 'Branch',
  subtitle: 'Head office, branches and outlets',
  table: 'branches',
  module: Modules.settings,
  hasActiveFlag: true,
  icon: Icons.store_mall_directory_outlined,
  searchKeys: const ['name', 'code', 'district'],
  fields: [
    const FieldDef('code', 'Code', required: true, inList: true, flex: 1, hint: 'For example DHK-01'),
    const FieldDef('name', 'Name', required: true, inList: true, flex: 3),
    const FieldDef(
      'branch_type',
      'Type',
      type: FieldType.dropdown,
      required: true,
      inList: true,
      defaultValue: 'branch',
      options: [
        Option('head_office', 'Head office'),
        Option('branch', 'Branch'),
        Option('outlet', 'Outlet'),
        Option('office', 'Office'),
      ],
    ),
    const FieldDef('phone', 'Phone', type: FieldType.phone, inList: true),
    const FieldDef('email', 'Email', type: FieldType.email),
    const FieldDef('district', 'District'),
    const FieldDef('address_line', 'Address', type: FieldType.multiline),
  ],
);

final _departmentConfig = CrudConfig(
  title: 'Departments',
  singular: 'Department',
  subtitle: 'How your company is organized',
  table: 'departments',
  module: Modules.settings,
  hasActiveFlag: true,
  icon: Icons.groups_2_outlined,
  fields: [
    const FieldDef('name', 'Name', required: true, inList: true, flex: 3),
    FieldDef('head_user_id', 'Department head', type: FieldType.dropdown, inList: true, flex: 3, optionsSource: memberOptionsProvider),
    const FieldDef('description', 'Description', type: FieldType.multiline, inList: true, flex: 4),
  ],
);

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _branchConfig);
}

class DepartmentsPage extends StatelessWidget {
  const DepartmentsPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _departmentConfig);
}
