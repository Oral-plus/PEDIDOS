import 'package:flutter/material.dart';

/// Rutas de assets de la app.
/// Para cambiar el logo en toda la app: sustituye el archivo assets/logo.png
/// (login, splash, dashboard, perfil, facturas, Wompi, etc. usan AppAssets.logo).
class AppAssets {
  AppAssets._();

  /// Logo que se muestra en login, registro, splash, dashboard y resto de la app.
  /// Cambia solo este path o reemplaza el archivo para actualizar en todas las pantallas.
  static const String logo = 'assets/logo.png';

  /// Icono de la aplicación para APK, PWA y launcher (512x512).
  static const String appIcon = 'assets/ENCABEZADOS/Icon-512.png';

  /// Logo con fondo transparente y más estirado (misma proporción). Usar en AppBar y pantallas.
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
