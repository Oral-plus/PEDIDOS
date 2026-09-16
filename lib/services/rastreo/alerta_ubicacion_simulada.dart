import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/navegacion.dart';
import '../../widgets/app_dialog.dart';
import 'claves_rastreo.dart';
import 'rastreo_ubicacion.dart';

class AlertaUbicacionSimulada {
  AlertaUbicacionSimulada._();

  static bool _instalada = false;
  static bool _mostrando = false;

  static void instalar() {
    if (_instalada || !RastreoUbicacion.disponible) return;
    FlutterForegroundTask.addTaskDataCallback(_alRecibir);
    _instalada = true;
  }

  static void _alRecibir(Object data) {
    if (data is Map && data['tipo'] == 'ubicacion_simulada') mostrarSiPendiente();
  }

  static Future<void> mostrarSiPendiente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final detectada = prefs.getInt(ClavesRastreo.simuladaDetectadaMs);
      final vista = prefs.getInt(ClavesRastreo.simuladaVistaMs);
      if (detectada == null || (vista != null && vista >= detectada)) return;
      await mostrar(detectadaMs: detectada);
    } catch (_) {}
  }

  static Future<void> mostrar({int? detectadaMs}) async {
    final ctx = navigatorKey.currentContext;
    if (_mostrando || ctx == null) return;
    _mostrando = true;
    try {
      await showAppDialog<void>(
        ctx,
        barrierDismissible: false,
        child: Builder(
          builder: (dialogo) => AppDialogShell(
            icon: Icons.gps_off_rounded,
            title: 'Ubicación simulada detectada',
            content: const Text(
              'Otra aplicación está modificando la ubicación de este dispositivo. El registro quedó marcado y será revisado.\n\nDesactiva cualquier aplicación de GPS falso y la opción "ubicación simulada" de las opciones de desarrollador.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w500),
            ),
            actions: [
              appDialogAction(dialogo, text: 'Entendido', onPressed: () => Navigator.of(dialogo).pop()),
            ],
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(ClavesRastreo.simuladaVistaMs, detectadaMs ?? DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
    } finally {
      _mostrando = false;
    }
  }
}
