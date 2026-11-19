import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/router/feature_routes.dart';
import '../core/router/nav.dart';
import '../core/state/session.dart';
import '../core/theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: AppColors.brass, width: 1.4),
      ),
      child: Text(
        'EZ',
        style: GoogleFonts.manrope(fontSize: size * 0.4, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
      ),
    );
  }
}

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key, required this.location});
  final String location;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final Map<String, bool> _manual = {};

  bool _active(NavLeaf l) => widget.location == l.route || widget.location.startsWith('${l.route}/');

  String? _tag(NavLeaf l) {
    if (featureRoutes.containsKey(l.route)) return null;
    return l.phase > 1 ? 'P${l.phase}' : 'Soon';
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final groups = NavConfig.visible(perms);
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.sidebarTop, AppColors.sidebarBottom],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Row(
              children: [
                const BrandMark(),
                const SizedBox(width: 12),
                Text(
                  'EZ ERP',
                  style: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              children: [for (final g in groups) ..._group(g)],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _group(NavGroup g) {
    if (g.flat) {
      final l = g.leaves.first;
      return [_NavTile(icon: l.icon, label: l.label, selected: _active(l), onTap: () => context.go(l.route))];
    }
    final active = g.leaves.any(_active);
    final open = _manual[g.label] ?? active;
    return [
      _GroupHeader(
        icon: g.icon,
        label: g.label,
        open: open,
        active: active,
        onTap: () => setState(() => _manual[g.label] = !open),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? Column(
                children: [
                  for (final l in g.leaves)
                    _NavTile(
                      icon: l.icon,
                      label: l.label,
                      selected: _active(l),
                      indent: true,
                      tag: _tag(l),
                      onTap: () => context.go(l.route),
                    ),
                  const SizedBox(height: 6),
                ],
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    ];
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.icon, required this.label, required this.open, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool open;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : AppColors.sidebarText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: const Color(0x0FFFFFFF),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color))),
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.indent = false,
    this.tag,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool indent;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.sidebarText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0x0FFFFFFF),
          onTap: onTap,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.fromLTRB(indent ? 43 : 12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0x1FFFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    if (!indent) ...[
                      Icon(icon, size: 19, color: color),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: color),
                      ),
                    ),
                    if (tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(6)),
                        child: Text(tag!, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.sidebarText)),
                      ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 9,
                  bottom: 9,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(color: AppColors.brass, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
