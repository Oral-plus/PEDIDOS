import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Genera y persiste un "ID de servicio" único por instalación de la app.
///
/// El ID se crea la primera vez que se abre la app, se guarda en el dispositivo
/// (sobrevive reinicios y cierres) y se muestra en la pantalla de login para que
/// el vendedor lo envíe a Soporte TI. Se regenera solo si se desinstala la app.
class DeviceService {
  DeviceService._();
  static final DeviceService _instance = DeviceService._();
  factory DeviceService() => _instance;

  static const _key = 'id_servicio';
  String? _idServicio;

  /// ID en memoria (null si aún no se ha cargado/generado).
  String? get idServicioCache => _idServicio;

  /// Devuelve el ID de servicio, generándolo y guardándolo la primera vez.
  Future<String> obtenerIdServicio() async {
    if (_idServicio != null) return _idServicio!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = _generar();
      await prefs.setString(_key, id);
    }
    _idServicio = id;
    return id;
  }

  /// Formato legible: SVC-XXXX-XXXX (sin caracteres ambiguos como O/0, I/1).
  String _generar() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    String bloque(int n) =>
        List.generate(n, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'SVC-${bloque(4)}-${bloque(4)}';
  }
}
