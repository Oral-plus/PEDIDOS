import 'package:geolocator/geolocator.dart';
import 'punto_ubicacion.dart';

class UbicacionDispositivo {
  UbicacionDispositivo._();

  static bool permisoConcedido(LocationPermission p) =>
      p == LocationPermission.always || p == LocationPermission.whileInUse;

  static Future<Position?> posicion({
    Duration limite = const Duration(seconds: 40),
    bool pedirPermiso = false,
    bool aceptarUltimaConocida = true,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied && pedirPermiso) {
        permiso = await Geolocator.requestPermission();
      }
      if (!permisoConcedido(permiso)) return null;
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: limite),
        );
      } catch (_) {
        return aceptarUltimaConocida ? await Geolocator.getLastKnownPosition() : null;
      }
    } catch (_) {
      return null;
    }
  }

  static PuntoUbicacion? desdePosicion(
    Position p, {
    required String origen,
    required String usuario,
    String? clienteCodigo,
    int? visitaId,
  }) {
    if (!PuntoUbicacion.coordenadaValida(p.latitude, p.longitude)) return null;
    final ms = p.timestamp.millisecondsSinceEpoch;
    double? util(double v) => v.isFinite && v >= 0 ? v : null;
    return PuntoUbicacion(
      idLocal: PuntoUbicacion.nuevoIdLocal(ms),
      latitud: p.latitude,
      longitud: p.longitude,
      precision: util(p.accuracy),
      altitud: p.altitude.isFinite ? p.altitude : null,
      velocidad: util(p.speed),
      rumbo: util(p.heading),
      simulada: p.isMocked,
      origen: origen,
      capturadoEnMs: ms,
      clienteCodigo: clienteCodigo,
      visitaId: visitaId,
      usuario: usuario,
    );
  }

  static Future<PuntoUbicacion?> capturar({
    required String origen,
    required String usuario,
    String? clienteCodigo,
    int? visitaId,
    Duration limite = const Duration(seconds: 40),
    bool pedirPermiso = false,
  }) async {
    final p = await posicion(limite: limite, pedirPermiso: pedirPermiso);
    if (p == null) return null;
    return desdePosicion(p, origen: origen, usuario: usuario, clienteCodigo: clienteCodigo, visitaId: visitaId);
  }
}
