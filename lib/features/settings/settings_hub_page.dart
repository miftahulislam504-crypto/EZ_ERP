import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';

class _Entry {
  const _Entry(this.title, this.desc, this.icon, this.route, this.module);
  final String title;
  final String desc;
  final IconData icon;
  final String route;
  final String module;
}

const _entries = [
  _Entry('Organization', 'Company details, address, currency, financial year and time zone.', Icons.business_center_outlined,
      '/settings/organization', Modules.settings),
  _Entry('Branches', 'Head office, branches and outlets.', Icons.store_mall_directory_outlined, '/settings/branches', Modules.settings),
  _Entry('Departments', 'Departments and who leads them.', Icons.groups_2_outlined, '/settings/departments', Modules.settings),
  _Entry('Business settings', 'Units, categories, brands, payment methods, tax rates and document numbering.', Icons.tune_outlined,
      '/settings/business', Modules.settings),
  _Entry('Users and roles', 'Invite people, assign roles and control permissions.', Icons.manage_accounts_outlined, '/settings/users',
      Modules.users),
  _Entry('Audit log', 'See who created, changed or removed what, and when.', Icons.history_rounded, '/settings/audit', Modules.audit),
  _Entry('My account', 'Your profile, password and signed-in devices.', Icons.person_outline_rounded, '/settings/profile',
      Modules.dashboard),
];

class SettingsHubPage extends ConsumerWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permsProvider);
    final visible = _entries.where((e) => perms.canView(e.module)).toList();
    return AppPage(
      title: 'Settings',
      subtitle: 'Configure your workspace',
      children: [
        LayoutBuilder(
          builder: (context, cons) {
            final cols = cons.maxWidth >= 900 ? 3 : (cons.maxWidth >= 560 ? 2 : 1);
            const gap = 14.0;
            final w = (cons.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final e in visible)
                  SizedBox(
                    width: w,
                    child: AppCard(
                      onTap: () => context.go(e.route),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                            child: Icon(e.icon, size: 22, color: AppColors.primary),
                          ),
                          const SizedBox(height: 14),
                          Text(e.title, style: AppText.h3),
                          const SizedBox(height: 4),
                          Text(e.desc, style: AppText.body),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
