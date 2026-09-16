import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'claves_rastreo.dart';
import 'punto_ubicacion.dart';

abstract class AlmacenCola {
  Future<String?> leer();
  Future<void> escribir(String contenido);
}

class AlmacenPreferencias implements AlmacenCola {
  const AlmacenPreferencias();

  @override
  Future<String?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(ClavesRastreo.cola);
  }

  @override
  Future<void> escribir(String contenido) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ClavesRastreo.cola, contenido);
  }
}

class ColaUbicaciones {
  final AlmacenCola almacen;
  final int maximo;

  ColaUbicaciones(this.almacen, {this.maximo = 2000});

  Future<List<PuntoUbicacion>> todos() async {
    final crudo = await almacen.leer();
    if (crudo == null || crudo.isEmpty) return [];
    try {
      final lista = jsonDecode(crudo);
      if (lista is! List) return [];
      return lista
          .whereType<Map>()
          .map((m) => PuntoUbicacion.desdeJson(Map<String, dynamic>.from(m)))
          .whereType<PuntoUbicacion>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardar(List<PuntoUbicacion> puntos) =>
      almacen.escribir(jsonEncode(puntos.map((p) => p.toJson()).toList()));

  Future<int> agregar(PuntoUbicacion punto) async {
    final puntos = await todos();
    if (puntos.any((p) => p.idLocal == punto.idLocal)) return puntos.length;
    puntos.add(punto);
    final recortados = puntos.length > maximo ? puntos.sublist(puntos.length - maximo) : puntos;
    await _guardar(recortados);
    return recortados.length;
  }

  Future<List<PuntoUbicacion>> pendientesDe(String usuario, {int limite = 200}) async {
    final puntos = await todos();
    return puntos.where((p) => p.usuario == usuario).take(limite).toList();
  }

  Future<void> confirmar(Iterable<String> idsLocales) async {
    final ids = idsLocales.toSet();
    if (ids.isEmpty) return;
    final puntos = await todos();
    final restantes = puntos.where((p) => !ids.contains(p.idLocal)).toList();
    if (restantes.length != puntos.length) await _guardar(restantes);
  }

  Future<int> descartarAjenos(String usuario) async {
    final puntos = await todos();
    final propios = puntos.where((p) => p.usuario == usuario).toList();
    if (propios.length != puntos.length) await _guardar(propios);
    return puntos.length - propios.length;
  }
}
