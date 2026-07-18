import 'package:flutter/material.dart';

/// Shared responsive infrastructure for OneFit.
///
/// The app was originally phone-only. These helpers let screens cap their
/// content width on tablets/desktop (so cards stop stretching edge-to-edge)
/// and reflow grids into more columns as width allows — without changing any
/// screen behaviour. They are purely presentational wrappers.
class Breakpoints {
  Breakpoints._();

  /// Below this width is treated as a phone.
  static const double phone = 600;

  /// At/above [phone] and below this is a tablet.
  static const double tablet = 1024;

  /// Max width the main content column is allowed to grow to. Phones are
  /// narrower than this so they stay full-width; wider screens center the
  /// content and leave breathing room on the sides.
  static const double maxContentWidth = 640;
}

/// Wraps a screen's scroll child so its content never stretches wider than
/// [maxWidth]; on wide screens the content is centered. On phones (narrower
/// than [maxWidth]) this is a no-op visually — the child fills the width.
///
/// This is a passive layout wrapper: it holds no state and intercepts no
/// gestures or callbacks.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // topCenter (not Center) so short content stays top-aligned on tall
    // screens instead of floating to the vertical middle; the ConstrainedBox
    // caps width and the alignment centers it horizontally.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

extension ResponsiveContext on BuildContext {
  /// True when the current screen width is tablet-sized or larger.
  bool get isTablet => MediaQuery.sizeOf(this).width >= Breakpoints.phone;

  /// True when the current screen width is large (desktop-class).
  bool get isLargeScreen => MediaQuery.sizeOf(this).width >= Breakpoints.tablet;

  /// Column count for a responsive grid, derived from the available width:
  /// [phone] below 600px, [tablet] from 600px, [large] from 1024px.
  int responsiveColumns({int phone = 2, int tablet = 3, int large = 4}) {
    final width = MediaQuery.sizeOf(this).width;
    if (width >= Breakpoints.tablet) return large;
    if (width >= Breakpoints.phone) return tablet;
    return phone;
  }
}
