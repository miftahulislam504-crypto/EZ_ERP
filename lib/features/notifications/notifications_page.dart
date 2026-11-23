import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../trade/trade_models.dart';

/// Live notifications for the signed-in user in the active company.
final notificationsStreamProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (uid == null || orgId == null) return Stream.value(const <Map<String, dynamic>>[]);
  return ref
      .watch(supabaseProvider)
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.where((r) => r['org_id'] == orgId).toList());
});

final unreadCountProvider = Provider<int>((ref) {
  final rows = ref.watch(notificationsStreamProvider).valueOrNull ?? const <Map<String, dynamic>>[];
  return rows.where((r) => r['is_read'] != true).length;
});

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  IconData _icon(String? kind) => switch (kind) {
        'approval' => Icons.verified_outlined,
        'warning' => Icons.warning_amber_rounded,
        'due' => Icons.schedule_rounded,
        'stock' => Icons.inventory_2_outlined,
        _ => Icons.info_outline_rounded,
      };

  Future<void> _markRead(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(supabaseProvider).from('notifications').update({'is_read': true}).eq('id', id);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  /// Where a notification leads. More record types are added as modules ship.
  String? _route(Map<String, dynamic> row) {
    final id = row['entity_id'];
    if (id == null) return null;
    return switch (row['entity_type']) {
      'voucher' => '/finance/vouchers/$id',
      'expense' || 'income' => '/finance/transactions?open=$id',
      'stock_adjustment' => '/inventory/adjustments/$id',
      final String type => tradeDocumentPath(type, '$id'),
      _ => null,
    };
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Map<String, dynamic> row) async {
    if (row['is_read'] != true) await _markRead(context, ref, row['id'] as String);
    final route = _route(row);
    if (route != null && context.mounted) context.go(route);
  }

  Future<void> _markAll(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    try {
      await ref.read(supabaseProvider).from('notifications').update({'is_read': true}).eq('user_id', uid).eq('is_read', false);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsStreamProvider);
    final unread = ref.watch(unreadCountProvider);
    return AppPage(
      title: 'Notifications',
      subtitle: unread == 0 ? 'You are all caught up' : '$unread unread',
      maxWidth: 860,
      actions: [
        if (unread > 0)
          AppButton(label: 'Mark all as read', kind: AppButtonKind.secondary, compact: true, onPressed: () => _markAll(context, ref)),
      ],
      children: [
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(notificationsStreamProvider)),
          data: (rows) {
            if (rows.isEmpty) {
              return const AppCard(
                child: EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet',
                  message: 'Approval requests, due payments, low stock and deadlines will show up here.',
                ),
              );
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(),
                    _Tile(
                      row: rows[i],
                      icon: _icon(rows[i]['kind'] as String?),
                      onTap: () => _open(context, ref, rows[i]),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.row, required this.icon, required this.onTap});

  final Map<String, dynamic> row;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = row['is_read'] != true;
    final body = row['body'] as String?;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread ? const Color(0xFFF4FAF8) : null,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${row['title']}', style: AppText.bodyStrong),
                  if (body != null && body.isNotEmpty) ...[const SizedBox(height: 2), Text(body, style: AppText.body)],
                  const SizedBox(height: 4),
                  Text(Fmt.timeAgo(Fmt.parse(row['created_at'] as String?)), style: AppText.small),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(top: 6, left: 8),
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: AppColors.brass, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
