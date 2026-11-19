import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/router/feature_routes.dart';
import '../../core/router/nav.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';

/// Phone home for every module the user's role can open.
class ModulesPage extends ConsumerWidget {
  const ModulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = NavConfig.visible(ref.watch(permsProvider)).where((g) => !g.flat).toList();
    return AppPage(
      title: 'Modules',
      subtitle: 'Everything your role can open',
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 6),
            child: Row(
              children: [
                Icon(g.icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(g.label, style: AppText.h3),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, cons) {
              final cols = cons.maxWidth >= 640 ? 3 : 2;
              const gap = 10.0;
              final w = (cons.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final l in g.leaves)
                    SizedBox(
                      width: w,
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        shadow: false,
                        onTap: () => context.go(l.route),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(l.icon, size: 22, color: AppColors.textSecondary),
                            const SizedBox(height: 10),
                            Text(l.label, style: AppText.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (!featureRoutes.containsKey(l.route))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(l.phase > 1 ? 'Phase ${l.phase}' : 'Coming soon', style: AppText.small),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permsProvider);
    final entries = <(String, IconData, String)>[
      ('My account', Icons.person_outline_rounded, '/settings/profile'),
      if (perms.canView(Modules.settings)) ('Settings', Icons.settings_outlined, '/settings'),
      if (perms.canView(Modules.reports)) ('Reports', Icons.assessment_outlined, '/reports'),
      if (perms.canView(Modules.documents)) ('Documents', Icons.folder_open_outlined, '/documents'),
      if (perms.canView(Modules.audit)) ('Audit log', Icons.history_rounded, '/settings/audit'),
    ];
    return AppPage(
      title: 'More',
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(),
                ListTile(
                  leading: Icon(entries[i].$2, color: AppColors.textSecondary),
                  title: Text(entries[i].$1, style: AppText.bodyStrong),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () => context.go(entries[i].$3),
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                title: Text('Sign out', style: AppText.bodyStrong.copyWith(color: AppColors.danger)),
                onTap: () => ref.read(supabaseProvider).auth.signOut(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens for modules that are in the roadmap but not built yet.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.leaf});

  final NavLeaf leaf;

  @override
  Widget build(BuildContext context) {
    final upcoming = leaf.phase > 1;
    return AppPage(
      title: leaf.label,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
                child: Icon(leaf.icon, size: 30, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              StatusBadge(upcoming ? 'Planned for Phase ${leaf.phase}' : 'Being built in Phase 1', tone: upcoming ? BadgeTone.neutral : BadgeTone.warning),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(leaf.desc, textAlign: TextAlign.center, style: AppText.body),
              ),
              const SizedBox(height: 22),
              AppButton(label: 'Back to dashboard', kind: AppButtonKind.secondary, compact: true, onPressed: () => context.go('/dashboard')),
            ],
          ),
        ),
      ],
    );
  }
}
