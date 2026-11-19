import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Base surface used across the product. Clips content to its rounded border
/// and shows an ink ripple when it is tappable.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final radius = BorderRadius.circular(AppRadius.card);
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: AppColors.border),
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: content),
              ),
      ),
    );
  }
}

/// A card with a title row, used to group related content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.h3),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.small),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
