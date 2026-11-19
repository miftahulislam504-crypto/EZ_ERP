import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/modules/modules_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/onboarding/splash_page.dart';
import '../../shell/app_shell.dart';
import '../state/session.dart';
import 'feature_routes.dart';
import 'nav.dart';

const _authRoutes = {'/login', '/register', '/forgot-password'};

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.listen(membershipsProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    final session = ref.read(supabaseProvider).auth.currentSession;

    if (session == null) return _authRoutes.contains(loc) ? null : '/login';

    final memberships = ref.read(membershipsProvider);
    if (memberships.isLoading || memberships.hasError) return loc == '/splash' ? null : '/splash';

    final list = memberships.valueOrNull ?? const [];
    if (list.isEmpty) return loc == '/onboarding' ? null : '/onboarding';
    if (_authRoutes.contains(loc) || loc == '/splash' || loc == '/onboarding') return '/dashboard';
    return null;
  }

  final router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(path: '/splash', pageBuilder: (c, s) => _fade(s, const SplashPage())),
      GoRoute(path: '/login', pageBuilder: (c, s) => _fade(s, const LoginPage())),
      GoRoute(path: '/register', pageBuilder: (c, s) => _fade(s, const RegisterPage())),
      GoRoute(path: '/forgot-password', pageBuilder: (c, s) => _fade(s, const ForgotPasswordPage())),
      GoRoute(path: '/onboarding', pageBuilder: (c, s) => _fade(s, const OnboardingPage())),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          for (final entry in featureRoutes.entries)
            GoRoute(path: entry.key, pageBuilder: (c, s) => _fade(s, entry.value(s))),
          for (final leaf in NavConfig.leaves.where((l) => !featureRoutes.containsKey(l.route)))
            GoRoute(path: leaf.route, pageBuilder: (c, s) => _fade(s, ComingSoonPage(leaf: leaf))),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
