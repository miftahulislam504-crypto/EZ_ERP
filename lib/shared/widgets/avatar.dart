import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 36, this.imageUrl});

  final String? name;
  final double size;
  final String? imageUrl;

  static const _palette = [
    (AppColors.primarySoft, AppColors.primary),
    (AppColors.brassSoft, Color(0xFF8A6417)),
    (AppColors.infoSoft, AppColors.info),
    (AppColors.successSoft, AppColors.success),
    (AppColors.neutralSoft, AppColors.neutral),
  ];

  @override
  Widget build(BuildContext context) {
    final pair = _palette[(name ?? '').codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pair.$1,
        shape: BoxShape.circle,
        image: imageUrl == null ? null : DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover),
      ),
      child: imageUrl != null
          ? null
          : Text(
              Fmt.initials(name),
              style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: pair.$2),
            ),
    );
  }
}
