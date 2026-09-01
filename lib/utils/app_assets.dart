import 'package:flutter/material.dart';

class AppAssets {
  AppAssets._();

  static const String logo = 'assets/logo.png';

  static const String appIcon = 'assets/ENCABEZADOS/Icon-512.png';

  static Widget logoImage({
    double? width,
    double? height,
    double opacity = 0.97,
    Widget? errorWidget,
  }) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Image.asset(
        logo,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            errorWidget ?? Icon(Icons.medical_services_rounded, size: height ?? 28, color: const Color(0xFF1e3a8a)),
      ),
    );
  }
}
