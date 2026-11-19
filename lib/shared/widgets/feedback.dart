import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import 'app_button.dart';

enum BadgeTone { success, warning, danger, info, neutral, primary }

({Color fg, Color bg}) toneColors(BadgeTone tone) => switch (tone) {
      BadgeTone.success => (fg: AppColors.success, bg: AppColors.successSoft),
      BadgeTone.warning => (fg: AppColors.warning, bg: AppColors.warningSoft),
      BadgeTone.danger => (fg: AppColors.danger, bg: AppColors.dangerSoft),
      BadgeTone.info => (fg: AppColors.info, bg: AppColors.infoSoft),
      BadgeTone.neutral => (fg: AppColors.neutral, bg: AppColors.neutralSoft),
      BadgeTone.primary => (fg: AppColors.primary, bg: AppColors.primarySoft),
    };

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = BadgeTone.neutral});

  /// Maps a workflow status (draft, pending, approved, paid, overdue ...) to a tone.
  factory StatusBadge.status(String status, {Key? key}) {
    final s = status.toLowerCase();
    final tone = switch (s) {
      'approved' || 'paid' || 'active' || 'accepted' || 'completed' || 'received' || 'done' || 'won' => BadgeTone.success,
      'pending' || 'submitted' || 'in_review' => BadgeTone.warning,
      'rejected' || 'overdue' || 'revoked' || 'cancelled' || 'failed' || 'lost' || 'bounced' => BadgeTone.danger,
      'partial' || 'in_progress' || 'sent' => BadgeTone.info,
      'posted' || 'confirmed' => BadgeTone.primary,
      _ => BadgeTone.neutral,
    };
    return StatusBadge(Fmt.humanize(status), key: key, tone: tone);
  }

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.fg)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
                child: Icon(icon, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 18),
              Text(title, style: AppText.h3, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, style: AppText.body, textAlign: TextAlign.center),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                AppButton(label: actionLabel!, onPressed: onAction, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Could not load this data',
      message: message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'You do not have access to this area',
      message: 'Ask an administrator to grant your role the required permission.',
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.sidebarBottom,
      ),
    );
}
