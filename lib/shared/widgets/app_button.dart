import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppButtonKind { primary, secondary, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = AppButtonKind.primary,
    this.loading = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonKind kind;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = switch (kind) {
      AppButtonKind.primary || AppButtonKind.danger => Colors.white,
      AppButtonKind.secondary => AppColors.textPrimary,
      AppButtonKind.ghost => AppColors.primary,
    };

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 18),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control));
    final pad = EdgeInsets.symmetric(horizontal: compact ? 14 : 20);
    final size = Size(0, compact ? 38 : 46);
    final action = enabled ? onPressed : null;

    final Widget button = switch (kind) {
      AppButtonKind.primary => FilledButton(
          onPressed: action,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: size, padding: pad, shape: shape, elevation: 0),
          child: child,
        ),
      AppButtonKind.danger => FilledButton(
          onPressed: action,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger, foregroundColor: Colors.white, minimumSize: size, padding: pad, shape: shape, elevation: 0),
          child: child,
        ),
      AppButtonKind.secondary => OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: Colors.white,
              minimumSize: size,
              padding: pad,
              shape: shape,
              side: const BorderSide(color: AppColors.borderStrong)),
          child: child,
        ),
      AppButtonKind.ghost => TextButton(
          onPressed: action,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary, minimumSize: size, padding: pad, shape: shape),
          child: child,
        ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
