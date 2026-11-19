import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

/// Standard page frame: centered content column, scrolling, and a header.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 1320,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final pad = context.isMobile ? 16.0 : 28.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
          children: [
            PageHeader(title: title, subtitle: subtitle, actions: actions),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.isMobile ? AppText.h2 : AppText.h1),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppText.body),
        ],
      ],
    );
    if (actions.isEmpty) return titleBlock;
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titleBlock, const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        Wrap(spacing: 10, runSpacing: 10, children: actions),
      ],
    );
  }
}
