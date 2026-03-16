import 'package:flutter/material.dart';

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  double responsive(double value) {
    double baseWidth = 390.0;
    return (screenWidth / baseWidth) * value;
  }

  double responsiveHeight(double value) {
    double baseHeight = 844.0;
    return (screenHeight / baseHeight) * value;
  }

  double clampFont(double min, double max, double scale) {
    double size = responsive(scale);
    return size.clamp(min, max);
  }

  bool get isTablet => screenWidth >= 600;
  bool get isDesktop => screenWidth >= 900;
  bool get isLandscape => screenWidth > screenHeight;

  EdgeInsets get responsivePadding {
    if (isDesktop) return const EdgeInsets.all(32);
    if (isTablet) return const EdgeInsets.all(24);
    return const EdgeInsets.all(16);
  }

  double get responsiveRadius {
    if (isDesktop) return 32;
    if (isTablet) return 28;
    return 24;
  }
}
