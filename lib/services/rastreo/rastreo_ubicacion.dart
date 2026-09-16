import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/app_dialog.dart';
import '../api_easy_service.dart';
import 'claves_rastreo.dart';
import 'cola_ubicaciones.dart';
import 'envio_ubicaciones.dart';
import 'tarea_rastreo.dart';
import 'ubicacion_dispositivo.dart';

class EstadoRastreo {
  final bool disponible;
  final bool servicioActivo;
  final bool gpsEncendido;
  final LocationPermission permiso;
  final bool notificaciones;
  final bool sinRestriccionBateria;
  final int pendientes;
  final DateTime? ultimaCaptura;
  final DateTime? ultimoEnvio;

  const EstadoRastreo({
    required this.disponible,
    required this.servicioActivo,
    required this.gpsEncendido,
    required this.permiso,
    required this.notificaciones,
    required this.sinRestriccionBateria,
    required this.pendientes,
    this.ultimaCaptura,
    this.ultimoEnvio,
  });

  bool get todoElTiempo => permiso == LocationPermission.always;
  bool get completo => servicioActivo && gpsEncendido && todoElTiempo;
}

class RastreoUbicacion {
  RastreoUbicacion._();

  static const Duration intervalo = Duration(minutes: 15);
  static const int _idServicio = 510;
  static bool _configurado = false;
  static bool _asegurando = false;

  static bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void configurar() {
    if (_configurado || !disponible) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rastreo_recorrido',
        channelName: 'Recorrido de visitas',
        channelDescription: 'Registro de la ubicación cada 15 minutos',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalo.inMilliseconds),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _configurado = true;
  }

  static bool get _debeRastrear {
    final api = ApiEasyService();
    return api.hasSession && !api.esSoporte && api.loginUsuario.trim().isNotEmpty;
  }

  static Future<EstadoRastreo> estado() async {
    if (!disponible) {
      return const EstadoRastreo(
        disponible: false,
        servicioActivo: false,
        gpsEncendido: false,
        permiso: LocationPermission.unableToDetermine,
        notificaciones: false,
        sinRestriccionBateria: false,
        pendientes: 0,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final usuario = prefs.getString(ClavesRastreo.usuario) ?? '';
    final pendientes = usuario.isEmpty
        ? 0
        : (await ColaUbicaciones(const AlmacenPreferencias()).pendientesDe(usuario, limite: 100000)).length;
    DateTime? fecha(String clave) {
      final ms = prefs.getInt(clave);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return EstadoRastreo(
      disponible: true,
      servicioActivo: await FlutterForegroundTask.isRunningService,
      gpsEncendido: await Geolocator.isLocationServiceEnabled(),
      permiso: await Geolocator.checkPermission(),
      notificaciones: await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted,
      sinRestriccionBateria: await FlutterForegroundTask.isIgnoringBatteryOptimizations,
      pendientes: pendientes,
      ultimaCaptura: fecha(ClavesRastreo.ultimaCapturaMs),
      ultimoEnvio: fecha(ClavesRastreo.ultimoEnvioMs),
    );
  }

  static Future<bool> iniciar() async {
    if (!disponible || !_debeRastrear) return false;
    try {
      configurar();
      if (!UbicacionDispositivo.permisoConcedido(await Geolocator.checkPermission())) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ClavesRastreo.usuario, ApiEasyService().loginUsuario.trim());
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask({'accion': 'enviar'});
        return true;
      }
      final r = await FlutterForegroundTask.startService(
        serviceId: _idServicio,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'Recorrido activo',
        notificationText: 'Registrando tu ubicación cada 15 minutos',
        callback: iniciarTareaRastreo,
      );
      return r is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  static void capturarAhora(String origen) {
    if (!disponible) return;
    FlutterForegroundTask.sendDataToTask({'accion': 'capturar', 'origen': origen});
  }

  static Future<void> alVolverALaApp() async {
    if (!disponible || !_debeRastrear) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) await iniciar();
    } catch (_) {}
  }

  static Future<void> alCerrarSesion() async {
    if (!disponible) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final sesion = SesionRastreo.desdePreferencias(prefs);
      if (sesion != null && sesion.puedeEnviar) {
        final cola = ColaUbicaciones(const AlmacenPreferencias());
        final lote = await cola.pendientesDe(sesion.usuario, limite: 500);
        if (lote.isNotEmpty &&
            await EnvioUbicaciones.enviar(sesion, lote).timeout(
                  const Duration(seconds: 8),
                  onTimeout: () => ResultadoEnvio.fallo,
                ) ==
                ResultadoEnvio.enviado) {
          await cola.confirmar(lote.map((p) => p.idLocal));
        }
      }
      await prefs.remove(ClavesRastreo.usuario);
      await limpiarVisitaEnCurso();
    } catch (_) {}
  }

  static Future<void> guardarVisitaEnCurso({required int visitaId, required String cliente, required DateTime inicio}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ClavesRastreo.visitaId, visitaId);
    await prefs.setString(ClavesRastreo.visitaCliente, cliente);
    await prefs.setInt(ClavesRastreo.visitaInicioMs, inicio.millisecondsSinceEpoch);
  }

  static Future<void> limpiarVisitaEnCurso() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ClavesRastreo.visitaId);
    await prefs.remove(ClavesRastreo.visitaCliente);
    await prefs.remove(ClavesRastreo.visitaInicioMs);
  }

  static Future<void> asegurar(BuildContext context, {bool forzar = false}) async {
    if (!disponible || !_debeRastrear || _asegurando) return;
    _asegurando = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!context.mounted) return;
        final abrir = await showAppConfirm(
          context,
          title: 'Activa la ubicación',
          message: 'El GPS está apagado. ORAL-PLUS registra tu recorrido cada 15 minutos y valida si estás en el cliente durante la visita.',
          confirmText: 'Activar GPS',
          cancelText: 'Ahora no',
          icon: Icons.location_off_rounded,
        );
        if (abrir) await Geolocator.openLocationSettings();
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.deniedForever) {
        if (!context.mounted) return;
        final abrir = await showAppConfirm(
          context,
          title: 'Permiso de ubicación bloqueado',
          message: 'Sin el permiso de ubicación no se puede registrar tu recorrido ni validar las visitas. Actívalo en los ajustes de la aplicación.',
          confirmText: 'Abrir ajustes',
          cancelText: 'Ahora no',
          icon: Icons.location_disabled_rounded,
        );
        if (abrir) await Geolocator.openAppSettings();
        return;
      }
      if (!UbicacionDispositivo.permisoConcedido(permiso)) return;

      final prefs = await SharedPreferences.getInstance();
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final ultimaVez = prefs.getInt(ClavesRastreo.pidioSegundoPlanoMs) ?? 0;
      if (permiso == LocationPermission.whileInUse && (forzar || ahora - ultimaVez > const Duration(hours: 12).inMilliseconds)) {
        await prefs.setInt(ClavesRastreo.pidioSegundoPlanoMs, ahora);
        if (!context.mounted) return;
        final continuar = await showAppConfirm(
          context,
          title: 'Permitir todo el tiempo',
          message: 'Para registrar tu recorrido también con la aplicación cerrada, en la siguiente pantalla elige "Permitir todo el tiempo".',
          confirmText: 'Continuar',
          cancelText: 'Ahora no',
          icon: Icons.my_location_rounded,
        );
        if (continuar) await Permission.locationAlways.request();
      }

      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      await iniciar();
    } catch (_) {
    } finally {
      _asegurando = false;
    }
  }
}
