import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_card.dart';
import 'feedback.dart';

/// A single headline figure. A null value renders as "--".
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = BadgeTone.primary,
    this.hint,
    this.onTap,
  });

  final String label;
  final String? value;
  final IconData icon;
  final BadgeTone tone;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 20, color: c.fg),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppText.label.copyWith(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value ?? '--', style: AppText.kpi),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: AppText.small),
          ],
        ],
      ),
    );
  }
}
