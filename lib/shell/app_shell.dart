import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/responsive.dart';
import '../features/notifications/notifications_page.dart';
import 'global_search.dart';
import 'sidebar.dart';
import 'topbar.dart';

/// Frame around every signed-in screen: sidebar and top bar on wide screens,
/// bottom navigation on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/dashboard', '/modules', '/approvals', '/notifications', '/more'];

  int _index() {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/approvals')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/more') || location.startsWith('/settings')) return 4;
    return 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = context.isWide ? _wide() : _mobile(context, ref);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showGlobalSearch(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => showGlobalSearch(context),
      },
      child: Focus(autofocus: true, child: body),
    );
  }

  Widget _wide() {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(location: location),
          Expanded(
            child: Column(
              children: [
                const TopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const MobileTopBar(),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: NavigationBarTheme(
          data: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: AppColors.primarySoft,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            height: 66,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
          child: NavigationBar(
            selectedIndex: _index(),
            onDestinationSelected: (i) => context.go(_tabs[i]),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded, color: AppColors.primary),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.apps_rounded),
                selectedIcon: Icon(Icons.apps_rounded, color: AppColors.primary),
                label: 'Modules',
              ),
              const NavigationDestination(
                icon: Icon(Icons.verified_outlined),
                selectedIcon: Icon(Icons.verified_rounded, color: AppColors.primary),
                label: 'Approvals',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
                selectedIcon: const Icon(Icons.notifications_rounded, color: AppColors.primary),
                label: 'Alerts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz_rounded),
                selectedIcon: Icon(Icons.more_horiz_rounded, color: AppColors.primary),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
