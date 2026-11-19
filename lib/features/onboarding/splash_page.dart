import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/feedback.dart';
import '../../shell/sidebar.dart';

/// Shown while the user's companies load, or when loading fails.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider);
    return Scaffold(
      body: Center(
        child: memberships.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ErrorView(
                    message: '${friendlyError(memberships.error!)} If this is a new project, confirm the database migration has been applied.',
                    onRetry: () => ref.invalidate(membershipsProvider),
                  ),
                  AppButton(
                    label: 'Sign out',
                    kind: AppButtonKind.ghost,
                    onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                  ),
                ],
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [BrandMark(size: 52), SizedBox(height: 24), LoadingView()],
              ),
      ),
    );
  }
}
