import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/producto.dart';
import 'api_client.dart';
import 'api_easy_service.dart';
import 'cache_service.dart';
import 'shared_http.dart';

class CatalogoService {
  CatalogoService._();
  static final CatalogoService _instance = CatalogoService._();
  factory CatalogoService() => _instance;

  static const _ttl = Duration(minutes: 10);
  final CacheService _cache = CacheService();

  String? ultimoError;

  Future<Catalogo?> obtener(String codigoCliente, {bool forzar = false}) {
    final cliente = codigoCliente.trim();
    return _cache.obtener<Catalogo?>(
      'catalogo:$cliente',
      _ttl,
      () => _descargar(cliente),
      forzar: forzar,
    );
  }

  void invalidar() => _cache.invalidarPrefijo('catalogo:');

  Future<Catalogo?> _descargar(String cliente) async {
    final api = ApiEasyService();
    final base = await api.baseUrl();
    final guardado = await _leerDisco(cliente);
    final token = api.token;
    ultimoError = null;
    if (token == null || token.isEmpty) {
      ultimoError = 'Inicia sesión para ver el catálogo';
      return guardado == null ? null : Catalogo.fromJson(guardado.cuerpo, baseUrl: base);
    }

    try {
      final uri = Uri.parse('$base/api/productos').replace(queryParameters: {'cliente': cliente});
      final res = await SharedHttp.client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (guardado?.etag != null) 'If-None-Match': guardado!.etag!,
      }).timeout(const Duration(seconds: 25));

      if (res.statusCode == 304 && guardado != null) {
        return Catalogo.fromJson(guardado.cuerpo, baseUrl: base);
      }
      if (res.statusCode == 200) {
        final bytes = res.bodyBytes;
        final decoded = bytes.length > 64 * 1024
            ? await compute(_decodificar, bytes)
            : _decodificar(bytes);
        if (decoded is Map && decoded['success'] == true) {
          final cuerpo = Map<String, dynamic>.from(decoded);
          await _guardarDisco(cliente, res.headers['etag'], cuerpo);
          return Catalogo.fromJson(cuerpo, baseUrl: base);
        }
      }
      ultimoError = _mensajeDe(res);
      if (res.statusCode == 401) {
        ApiClient.onSesionInvalida?.call(ultimoError ?? 'Tu sesión expiró. Inicia sesión de nuevo.');
      }
    } catch (_) {
      ultimoError = 'Sin conexión con el servidor. Revisa la red e intenta de nuevo.';
    }
    return guardado == null ? null : Catalogo.fromJson(guardado.cuerpo, baseUrl: base);
  }

  static String _mensajeDe(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final msg = decoded is Map ? decoded['message']?.toString() : null;
      if (msg != null && msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'No se pudo cargar el catálogo (${res.statusCode})';
  }

  static dynamic _decodificar(Uint8List bytes) => jsonDecode(utf8.decode(bytes));

  Future<File> _archivo(String cliente) async {
    final dir = await getApplicationSupportDirectory();
    final nombre = cliente.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/catalogo_${nombre.isEmpty ? 'general' : nombre}.json');
  }

  Future<_CatalogoGuardado?> _leerDisco(String cliente) async {
    try {
      final f = await _archivo(cliente);
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return null;
      final cuerpo = decoded['cuerpo'];
      if (cuerpo is! Map) return null;
      return _CatalogoGuardado(decoded['etag']?.toString(), Map<String, dynamic>.from(cuerpo));
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardarDisco(String cliente, String? etag, Map<String, dynamic> cuerpo) async {
    try {
      final f = await _archivo(cliente);
      await f.writeAsString(jsonEncode({'etag': etag, 'cuerpo': cuerpo}), flush: true);
    } catch (_) {}
  }
}

class _CatalogoGuardado {
  final String? etag;
  final Map<String, dynamic> cuerpo;
  _CatalogoGuardado(this.etag, this.cuerpo);
}
