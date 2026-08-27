import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/session_provider.dart';
import '../providers/visita_activa_provider.dart';
import '../screens/login_screen.dart';
import '../utils/navegacion.dart';
import 'api_client.dart';
import 'api_easy_service.dart';
import 'catalogo_service.dart';

/// Cierre de sesión en un solo sitio: servidor, datos guardados, estado en
/// memoria y vuelta al login. Lo usan el botón Salir, la respuesta 401 del
/// backend y el vencimiento de las 12 horas.
class Sesion {
  Sesion._();

  static bool _cerrando = false;

  /// Conecta el aviso de 401 del cliente HTTP con el cierre de sesión.
  static void instalar() {
    ApiClient.onSesionInvalida = (mensaje) => expirar(mensaje);
  }

  /// Cierre voluntario (botón Salir): también se cierra en el servidor.
  static Future<void> cerrar() => _cerrar(avisarServidor: true, aviso: null);

  /// La sesión venció o el servidor la rechazó.
  static Future<void> expirar([String? mensaje]) {
    if (ApiEasyService().token == null) return Future.value();
    return _cerrar(
      avisarServidor: false,
      aviso: mensaje ?? 'Tu sesión expiró. Inicia sesión de nuevo.',
    );
  }

  /// Al volver a primer plano: si ya pasaron las 12 horas se pide el login.
  static Future<void> verificarVigencia() async {
    final api = ApiEasyService();
    if (api.token != null && api.sesionVencida) await expirar();
  }

  static Future<void> _cerrar({required bool avisarServidor, String? aviso}) async {
    if (_cerrando) return;
    _cerrando = true;
    try {
      final api = ApiEasyService();
      if (avisarServidor) {
        await api.logout();
      } else {
        await api.clearSession();
      }
      CatalogoService().invalidar();
      _limpiarEstado();
      navigatorKey.currentState?.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => LoginScreen(aviso: aviso),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          transitionDuration: const Duration(milliseconds: 250),
        ),
        (route) => false,
      );
    } finally {
      _cerrando = false;
    }
  }

  /// Cliente seleccionado, carrito y visita en curso vuelven a cero.
  static void _limpiarEstado() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ctx.read<SessionProvider>().clear();
      ctx.read<CartProvider>().clearCart();
      ctx.read<VisitaActivaProvider>().finalizar();
    } catch (_) {}
  }
}
