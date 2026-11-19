import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class EzErpApp extends ConsumerWidget {
  const EzErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'EZ ERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
      ),
    );
  }
}

/// Shown when the app is started without Supabase credentials.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backend is not configured', style: AppText.h2),
                  const SizedBox(height: 10),
                  Text(
                    'Start the app with your Supabase project values:\n\n'
                    'flutter run -d chrome \\\n'
                    '  --dart-define=SUPABASE_URL=https://your-project.supabase.co \\\n'
                    '  --dart-define=SUPABASE_ANON_KEY=your-anon-key',
                    style: AppText.body,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
