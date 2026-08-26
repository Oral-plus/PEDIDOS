/// Caché en memoria con vencimiento por clave.
///
/// Evita repetir peticiones que devuelven lo mismo (clientes, cartera,
/// tareas, precios). Si dos pantallas piden la misma clave a la vez, comparten
/// una sola petición en curso.
class CacheService {
  CacheService._();
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;

  final Map<String, _Entrada> _datos = {};
  final Map<String, Future<dynamic>> _enVuelo = {};

  /// Devuelve el valor guardado si no venció; si no, ejecuta [cargar] y guarda
  /// el resultado durante [ttl]. Un resultado null nunca se guarda; con
  /// [guardarSi] se puede exigir además una condición (p. ej. success == true).
  Future<T> obtener<T>(
    String clave,
    Duration ttl,
    Future<T> Function() cargar, {
    bool forzar = false,
    bool Function(T valor)? guardarSi,
  }) async {
    if (!forzar) {
      final e = _datos[clave];
      if (e != null && !e.vencida) return e.valor as T;
      final pendiente = _enVuelo[clave];
      if (pendiente != null) return await pendiente as T;
    }

    final futuro = cargar();
    _enVuelo[clave] = futuro;
    try {
      final valor = await futuro;
      if (valor != null && (guardarSi == null || guardarSi(valor))) {
        _datos[clave] = _Entrada(valor, DateTime.now().add(ttl));
      }
      return valor;
    } finally {
      if (identical(_enVuelo[clave], futuro)) _enVuelo.remove(clave);
    }
  }

  /// Valor guardado (o null si no existe o venció).
  T? leer<T>(String clave) {
    final e = _datos[clave];
    if (e == null) return null;
    if (e.vencida) {
      _datos.remove(clave);
      return null;
    }
    return e.valor as T;
  }

  void guardar(String clave, dynamic valor, Duration ttl) {
    _datos[clave] = _Entrada(valor, DateTime.now().add(ttl));
  }

  void invalidar(String clave) {
    _datos.remove(clave);
  }

  /// Borra todas las claves que empiecen por [prefijo].
  void invalidarPrefijo(String prefijo) {
    _datos.removeWhere((k, _) => k.startsWith(prefijo));
  }

  /// Borra todo (cambio de sesión).
  void limpiar() {
    _datos.clear();
  }
}

class _Entrada {
  _Entrada(this.valor, this.vence);
  final dynamic valor;
  final DateTime vence;
  bool get vencida => DateTime.now().isAfter(vence);
}
