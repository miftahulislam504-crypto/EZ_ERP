import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFE6ECEA), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == index
                        ? const [BoxShadow(color: Color(0x140F1F1D), blurRadius: 6, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: i == index ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
