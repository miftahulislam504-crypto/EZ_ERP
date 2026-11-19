import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../shell/sidebar.dart';

/// Split layout for sign in, registration and password recovery.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child, this.footer});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final showPanel = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          if (showPanel) const Expanded(flex: 5, child: _BrandPanel()),
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!showPanel) ...[
                        const Row(children: [BrandMark(size: 34), SizedBox(width: 10), _WordMark()]),
                        const SizedBox(height: 36),
                      ],
                      Text(title, style: AppText.h1),
                      const SizedBox(height: 6),
                      Text(subtitle, style: AppText.body),
                      const SizedBox(height: 28),
                      child,
                      if (footer != null) ...[const SizedBox(height: 24), footer!],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordMark extends StatelessWidget {
  const _WordMark();

  @override
  Widget build(BuildContext context) {
    return Text('EZ ERP', style: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4));
  }
}

class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.4))),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _points = [
    'Purchase to payment, tracked end to end',
    'Live stock across every warehouse and branch',
    'Receivables and payables you can trust',
    'Approvals that follow your own rules',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.sidebarTop, AppColors.sidebarBottom]),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _LedgerPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 56, 56, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandMark(size: 40),
                    const SizedBox(width: 12),
                    Text('EZ ERP', style: GoogleFonts.manrope(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4)),
                  ],
                ),
                const Spacer(),
                Text(
                  'Run purchasing, sales, stock and accounts from one ledger.',
                  style: GoogleFonts.manrope(fontSize: 40, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -1.2, color: Colors.white),
                ),
                const SizedBox(height: 32),
                for (final p in _points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.brass, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 14),
                        Flexible(child: Text(p, style: GoogleFonts.inter(fontSize: 15, color: AppColors.sidebarText))),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint ruled lines with a brass margin, like a ledger page.
class _LedgerPainter extends CustomPainter {
  const _LedgerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    for (double y = 40; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final margin = Paint()
      ..color = const Color(0x66C4943A)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(44, 0), Offset(44, size.height), margin);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
