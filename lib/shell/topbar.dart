import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/permissions/permissions.dart';
import '../core/state/session.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/notifications_page.dart';
import '../shared/widgets/avatar.dart';
import 'global_search.dart';

class _PillButton extends StatelessWidget {
  const _PillButton({required this.leading, required this.label, this.maxWidth = 200});

  final Widget leading;
  final String label;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppText.label)),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class CompanySwitcher extends ConsumerWidget {
  const CompanySwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeMembershipProvider);
    if (active == null) return const SizedBox.shrink();
    final all = ref.watch(membershipsProvider).valueOrNull ?? const [];
    return PopupMenuButton<String>(
      tooltip: 'Switch company',
      offset: const Offset(0, 48),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      onSelected: (id) => ref.read(activeOrgIdProvider.notifier).select(id),
      itemBuilder: (_) => [
        for (final m in all)
          PopupMenuItem(
            value: m.orgId,
            child: Row(
              children: [
                InitialsAvatar(name: m.orgName, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(m.orgName, overflow: TextOverflow.ellipsis)),
                if (m.orgId == active.orgId) const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
      child: _PillButton(leading: InitialsAvatar(name: active.orgName, size: 24, imageUrl: active.logoUrl), label: active.orgName),
    );
  }
}

class BranchSwitcher extends ConsumerWidget {
  const BranchSwitcher({super.key});

  static const _all = '__all__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider).valueOrNull ?? const [];
    final selected = ref.watch(activeBranchIdProvider);
    final current = branches.where((b) => b.id == selected).toList();
    final label = current.isEmpty ? 'All branches' : current.first.name;
    return PopupMenuButton<String>(
      tooltip: 'Filter by branch',
      offset: const Offset(0, 48),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      onSelected: (id) => ref.read(activeBranchIdProvider.notifier).select(id == _all ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _all, child: Text('All branches')),
        for (final b in branches) PopupMenuItem(value: b.id, child: Text(b.name)),
      ],
      child: _PillButton(
        leading: const Icon(Icons.store_mall_directory_outlined, size: 18, color: AppColors.textSecondary),
        label: label,
        maxWidth: 190,
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: () => showGlobalSearch(context),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5F4),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text('Search pages and actions', style: AppText.small.copyWith(fontSize: 13.5))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
              child: const Text('Ctrl K', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class BellButton extends ConsumerWidget {
  const BellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.go('/notifications'),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary),
      ),
    );
  }
}

class ProfileMenu extends ConsumerWidget {
  const ProfileMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final perms = ref.watch(permsProvider);
    final role = ref.watch(activeMembershipProvider)?.roleName ?? '';
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      onSelected: (v) async {
        if (v == 'account') context.go('/settings/profile');
        if (v == 'settings') context.go('/settings');
        if (v == 'signout') await ref.read(supabaseProvider).auth.signOut();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile?.fullName ?? 'Account', style: AppText.bodyStrong),
              Text(profile?.email ?? '', style: AppText.small),
              if (role.isNotEmpty) Text(role, style: AppText.small),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'account', child: Text('My account')),
        if (perms.canView(Modules.settings)) const PopupMenuItem(value: 'settings', child: Text('Settings')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InitialsAvatar(name: profile?.fullName ?? profile?.email, size: 36),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: const Row(
        children: [
          CompanySwitcher(),
          SizedBox(width: 10),
          BranchSwitcher(),
          SizedBox(width: 20),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 460), child: _SearchPill()),
            ),
          ),
          SizedBox(width: 12),
          BellButton(),
          SizedBox(width: 4),
          ProfileMenu(),
        ],
      ),
    );
  }
}

class MobileTopBar extends StatelessWidget {
  const MobileTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          const Flexible(child: CompanySwitcher()),
          const SizedBox(width: 8),
          const BranchSwitcherIcon(),
          const Spacer(),
          IconButton(
            tooltip: 'Search',
            onPressed: () => showGlobalSearch(context),
            icon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          ),
          const ProfileMenu(),
        ],
      ),
    );
  }
}

/// Compact branch filter for phones.
class BranchSwitcherIcon extends ConsumerWidget {
  const BranchSwitcherIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider).valueOrNull ?? const [];
    final selected = ref.watch(activeBranchIdProvider);
    if (branches.length < 2) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Filter by branch',
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      icon: Icon(Icons.store_mall_directory_outlined, color: selected == null ? AppColors.textSecondary : AppColors.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      onSelected: (id) => ref.read(activeBranchIdProvider.notifier).select(id == BranchSwitcher._all ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(value: BranchSwitcher._all, child: Text('All branches')),
        for (final b in branches) PopupMenuItem(value: b.id, child: Text(b.name)),
      ],
    );
  }
}
