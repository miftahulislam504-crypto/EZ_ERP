import 'package:flutter/widgets.dart';

class Breakpoints {
  Breakpoints._();

  /// Below this width forms open as bottom sheets and grids collapse.
  static const mobile = 720.0;

  /// From this width the persistent sidebar layout is used.
  static const wide = 960.0;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isMobile => screenWidth < Breakpoints.mobile;
  bool get isWide => screenWidth >= Breakpoints.wide;
}
