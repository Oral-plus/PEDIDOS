import 'dart:ui';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'claves_rastreo.dart';
import 'cola_ubicaciones.dart';
import 'envio_ubicaciones.dart';
import 'ubicacion_dispositivo.dart';

@pragma('vm:entry-point')
void iniciarTareaRastreo() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(TareaRastreo());
}

class TareaRastreo extends TaskHandler {
  bool _ocupado = false;
  final ColaUbicaciones _cola = ColaUbicaciones(const AlmacenPreferencias());

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) =>
      _ciclo(origen: starter == TaskStarter.system ? 'periodico' : 'inicio_sesion');

  @override
  void onRepeatEvent(DateTime timestamp) {
    _ciclo(origen: 'periodico');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data['accion'] == 'capturar') _ciclo(origen: (data['origen'] ?? 'manual').toString());
    if (data['accion'] == 'enviar') _ciclo();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  Future<void> _ciclo({String? origen}) async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final sesion = SesionRastreo.desdePreferencias(prefs);
      if (sesion == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      if (origen != null) await _capturar(prefs, sesion, origen);
      if (sesion.puedeEnviar) {
        await _cola.descartarAjenos(sesion.usuario);
        await _enviarPendientes(prefs, sesion);
        await _pulsoVisita(prefs, sesion);
      }
    } catch (_) {
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _capturar(SharedPreferences prefs, SesionRastreo sesion, String origen) async {
    final visitaId = prefs.getInt(ClavesRastreo.visitaId);
    final punto = await UbicacionDispositivo.capturar(
      origen: origen,
      usuario: sesion.usuario,
      clienteCodigo: visitaId != null ? prefs.getString(ClavesRastreo.visitaCliente) : null,
      visitaId: visitaId,
    );
    if (punto == null) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Recorrido sin ubicación',
        notificationText: 'Activa el GPS y el permiso de ubicación de ORAL-PLUS',
      );
      return;
    }
    if (prefs.getInt(ClavesRastreo.ultimaCapturaMs) == punto.capturadoEnMs) return;
    await _cola.agregar(punto);
    await prefs.setInt(ClavesRastreo.ultimaCapturaMs, punto.capturadoEnMs);
    if (punto.simulada) {
      await prefs.setInt(ClavesRastreo.simuladaDetectadaMs, punto.capturadoEnMs);
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Ubicación simulada detectada',
        notificationText: 'Otra aplicación está modificando tu ubicación. Quedó registrado.',
      );
      FlutterForegroundTask.sendDataToMain({'tipo': 'ubicacion_simulada', 'ms': punto.capturadoEnMs});
    } else {
      final hora = DateTime.fromMillisecondsSinceEpoch(punto.capturadoEnMs);
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Recorrido activo',
        notificationText: 'Última ubicación ${_hora(hora)} · se registra cada 15 minutos',
      );
    }
  }

  Future<void> _enviarPendientes(SharedPreferences prefs, SesionRastreo sesion) async {
    for (var vuelta = 0; vuelta < 10; vuelta++) {
      final lote = await _cola.pendientesDe(sesion.usuario, limite: 200);
      if (lote.isEmpty) return;
      final r = await EnvioUbicaciones.enviar(sesion, lote);
      if (r != ResultadoEnvio.enviado) return;
      await _cola.confirmar(lote.map((p) => p.idLocal));
      await prefs.setInt(ClavesRastreo.ultimoEnvioMs, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> _pulsoVisita(SharedPreferences prefs, SesionRastreo sesion) async {
    final visitaId = prefs.getInt(ClavesRastreo.visitaId);
    final cliente = prefs.getString(ClavesRastreo.visitaCliente);
    final inicioMs = prefs.getInt(ClavesRastreo.visitaInicioMs);
    if (visitaId == null || cliente == null || inicioMs == null) return;
    final duracion = ((DateTime.now().millisecondsSinceEpoch - inicioMs) / 1000).floor();
    final estado = await EnvioUbicaciones.pulsoVisita(sesion, cliente, visitaId, duracion < 0 ? 0 : duracion);
    if (estado != 404) return;
    await prefs.reload();
    if (prefs.getInt(ClavesRastreo.visitaId) != visitaId) return;
    await prefs.remove(ClavesRastreo.visitaId);
    await prefs.remove(ClavesRastreo.visitaCliente);
    await prefs.remove(ClavesRastreo.visitaInicioMs);
  }

  static String _hora(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }
}
