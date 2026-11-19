import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/feature_routes.dart';
import '../core/router/nav.dart';
import '../core/state/session.dart';
import '../core/theme/app_theme.dart';

Future<void> showGlobalSearch(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x590F1F1D),
    builder: (_) => const _SearchDialog(),
  );
}

/// Jump to any screen the user may open. Record search (customers, invoices,
/// products ...) plugs into this dialog as each module ships.
class _SearchDialog extends ConsumerStatefulWidget {
  const _SearchDialog();

  @override
  ConsumerState<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<_SearchDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final q = _q.trim().toLowerCase();
    final results = NavConfig.searchable(perms).where((l) => q.isEmpty || l.label.toLowerCase().contains(q)).take(12).toList();

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search pages and actions',
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(),
            Flexible(
              child: results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Nothing matches "$_q"', style: AppText.body),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(8),
                      shrinkWrap: true,
                      children: [
                        for (final l in results)
                          ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                            leading: Icon(l.icon, size: 20, color: AppColors.textSecondary),
                            title: Text(l.label, style: AppText.bodyStrong),
                            trailing: featureRoutes.containsKey(l.route)
                                ? null
                                : Text(l.phase > 1 ? 'Phase ${l.phase}' : 'Soon', style: AppText.small),
                            onTap: () {
                              Navigator.of(context).pop();
                              context.go(l.route);
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
