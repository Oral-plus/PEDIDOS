import 'dart:collection';
import 'dart:io';

class CacheService {
  CacheService._();
  static final CacheService _instance = CacheService._();
  factory CacheService() => _instance;

  static int _calcularTope() {
    final nucleos = Platform.numberOfProcessors;
    final tope = nucleos * 400;
    return tope.clamp(600, 6000);
  }

  late final int _maxEntradas = _calcularTope();

  final LinkedHashMap<String, _Entrada> _datos = LinkedHashMap<String, _Entrada>();
  final Map<String, Future<dynamic>> _enVuelo = {};

  Future<T> obtener<T>(
    String clave,
    Duration ttl,
    Future<T> Function() cargar, {
    bool forzar = false,
    bool Function(T valor)? guardarSi,
  }) async {
    if (!forzar) {
      final e = _datos[clave];
      if (e != null && !e.vencida) {
        _tocar(clave, e);
        return e.valor as T;
      }
      final pendiente = _enVuelo[clave];
      if (pendiente != null) return await pendiente as T;
    }

    final futuro = cargar();
    _enVuelo[clave] = futuro;
    try {
      final valor = await futuro;
      if (valor != null && (guardarSi == null || guardarSi(valor))) {
        _poner(clave, _Entrada(valor, DateTime.now().add(ttl)));
      }
      return valor;
    } finally {
      if (identical(_enVuelo[clave], futuro)) _enVuelo.remove(clave);
    }
  }

  T? leer<T>(String clave) {
    final e = _datos[clave];
    if (e == null) return null;
    if (e.vencida) {
      _datos.remove(clave);
      return null;
    }
    _tocar(clave, e);
    return e.valor as T;
  }

  void guardar(String clave, dynamic valor, Duration ttl) {
    _poner(clave, _Entrada(valor, DateTime.now().add(ttl)));
  }

  void invalidar(String clave) {
    _datos.remove(clave);
  }

  void invalidarPrefijo(String prefijo) {
    _datos.removeWhere((k, _) => k.startsWith(prefijo));
  }

  void limpiar() {
    _datos.clear();
  }

  int get longitud => _datos.length;

  int get capacidad => _maxEntradas;

  void _tocar(String clave, _Entrada e) {
    _datos.remove(clave);
    _datos[clave] = e;
  }

  void _poner(String clave, _Entrada e) {
    _datos.remove(clave);
    _datos[clave] = e;
    if (_datos.length > _maxEntradas) _desalojar();
  }

  void _desalojar() {
    _datos.removeWhere((_, e) => e.vencida);
    while (_datos.length > _maxEntradas && _datos.isNotEmpty) {
      _datos.remove(_datos.keys.first);
    }
  }
}

class _Entrada {
  _Entrada(this.valor, this.vence);
  final dynamic valor;
  final DateTime vence;
  bool get vencida => DateTime.now().isAfter(vence);
}
