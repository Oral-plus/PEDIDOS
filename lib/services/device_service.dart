import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  DeviceService._();
  static final DeviceService _instance = DeviceService._();
  factory DeviceService() => _instance;

  static const _key = 'id_servicio';
  String? _idServicio;

  String? get idServicioCache => _idServicio;

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

  String _generar() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    String bloque(int n) =>
        List.generate(n, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'SVC-${bloque(4)}-${bloque(4)}';
  }
}
