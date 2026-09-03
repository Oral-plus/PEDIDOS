import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'device_service.dart';
import 'shared_http.dart';

class ApiEasyService {
  ApiEasyService._() {
    ApiClient.onConnectionError = _olvidarBaseUrl;
  }
  static final ApiEasyService _instance = ApiEasyService._();
  factory ApiEasyService() => _instance;

  static const List<String> _baseUrls = [
    'https://gestores-api.oral-plus.com',
    'http://192.168.2.249:3000',
    'http://192.168.2.73:3000',
    'http://10.0.2.2:3000',
    'http://localhost:3000',
  ];

  static const _tokenKey = 'auth_token';
  static const _usuarioKey = 'auth_usuario';
  static const _loginUsuarioKey = 'login_usuario';
  static const _expiraKey = 'auth_expira';

  String? _token;
  DateTime? _expira;
  Map<String, dynamic>? _usuario;
  String _loginUsuario = '';
  String? _resolvedBaseUrl;
  bool _sessionRestored = false;
  final CacheService _cache = CacheService();

  String? get token => _token;
  Map<String, dynamic>? get usuario => _usuario;
  String get loginUsuario => _loginUsuario;
  bool get hasSession => _token != null && _token!.isNotEmpty && !sesionVencida;

  DateTime? get expira => _expira;

  bool get sesionVencida => _expira == null || !DateTime.now().isBefore(_expira!);

  bool get esSoporte => _usuario?['rol']?.toString() == 'soporte';

  void setToken(String? t) {
    _token = t;
  }

  void setUsuario(Map<String, dynamic>? u) {
    _usuario = u;
  }

  Future<void> restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_tokenKey);
      final storedUsuario = prefs.getString(_usuarioKey);
      final storedLogin = prefs.getString(_loginUsuarioKey);

      if (storedToken != null && storedToken.isNotEmpty) {
        _token = storedToken;
        _loginUsuario = storedLogin ?? '';
        final expiraMs = prefs.getInt(_expiraKey);
        _expira = expiraMs != null
            ? DateTime.fromMillisecondsSinceEpoch(expiraMs)
            : _expiraDeToken(storedToken);
        if (sesionVencida) {
          _token = null;
          _expira = null;
          _loginUsuario = '';
          await _persistSession();
          return;
        }
        if (storedUsuario != null && storedUsuario.isNotEmpty) {
          final decoded = jsonDecode(storedUsuario);
          if (decoded is Map) {
            _usuario = Map<String, dynamic>.from(decoded);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token != null && _token!.isNotEmpty) {
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_loginUsuarioKey, _loginUsuario);
        if (_expira != null) {
          await prefs.setInt(_expiraKey, _expira!.millisecondsSinceEpoch);
        } else {
          await prefs.remove(_expiraKey);
        }
        if (_usuario != null) {
          await prefs.setString(_usuarioKey, jsonEncode(_usuario));
        } else {
          await prefs.remove(_usuarioKey);
        }
      } else {
        await prefs.remove(_tokenKey);
        await prefs.remove(_usuarioKey);
        await prefs.remove(_loginUsuarioKey);
        await prefs.remove(_expiraKey);
      }
    } catch (_) {}
  }

  Future<void> clearSession() async {
    _token = null;
    _expira = null;
    _usuario = null;
    _loginUsuario = '';
    _cache.limpiar();
    await _persistSession();
  }

  Future<void> logout() async {
    final token = _token;
    if (token != null && token.isNotEmpty) {
      try {
        final baseUrl = await _resolveBaseUrl().timeout(const Duration(seconds: 5));
        await ApiClient.post(
          '/api/auth/logout',
          body: const {},
          customBaseUrl: baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          timeout: const Duration(seconds: 6),
        );
      } catch (_) {}
    }
    await clearSession();
  }

  static DateTime? _expiraDeToken(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is num) return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {}
    return null;
  }

  static DateTime? _expiraDeRespuesta(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return null;
    return DateTime.tryParse(data['expira']?.toString() ?? '')?.toLocal();
  }

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  Future<String> baseUrl() => _resolveBaseUrl();

  static const _baseUrlKey = 'api_base_url';
  static const _sondaLan = Duration(milliseconds: 1500);
  static const _sondaPublica = Duration(seconds: 6);
  Future<String>? _resolviendo;
  DateTime? _ultimaBusquedaFallida;

  Future<String> _resolveBaseUrl() {
    final cached = _resolvedBaseUrl;
    if (cached != null) return Future.value(cached);
    return _resolviendo ??=
        _buscarBaseUrl().whenComplete(() => _resolviendo = null);
  }

  Future<String> _buscarBaseUrl() async {
    final fallo = _ultimaBusquedaFallida;
    if (fallo != null &&
        DateTime.now().difference(fallo) < const Duration(seconds: 30)) {
      return _baseUrls.first;
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final guardado = prefs?.getString(_baseUrlKey);

    final sondas = <String, Future<bool>>{
      for (final u in _baseUrls) u: _responde(u),
    };
    final orden = [
      _baseUrls.first,
      if (guardado != null && sondas.containsKey(guardado)) guardado,
      ..._baseUrls.skip(1),
    ];
    for (final u in orden) {
      if (await sondas[u]!) {
        _resolvedBaseUrl = u;
        _ultimaBusquedaFallida = null;
        if (u != guardado) {
          try {
            await prefs?.setString(_baseUrlKey, u);
          } catch (_) {}
        }
        return u;
      }
    }

    _ultimaBusquedaFallida = DateTime.now();
    return _baseUrls.first;
  }

  Future<bool> _responde(String baseUrl) async {
    try {
      final res = await ApiClient.get(
        '/api/test',
        customBaseUrl: baseUrl,
        timeout: baseUrl.startsWith('https://') ? _sondaPublica : _sondaLan,
      );
      return res is Map && res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  void _olvidarBaseUrl(String baseUrl) {
    if (_resolvedBaseUrl == baseUrl) _resolvedBaseUrl = null;
  }

  Map<String, dynamic>? _extractUsuario(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      final nested = data['usuario'] ?? data['user'];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }

    final direct = res['usuario'] ?? res['user'];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    return null;
  }

  String? _extractToken(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      final nested = data['token']?.toString();
      if (nested != null && nested.isNotEmpty) return nested;
    }

    final direct = res['token']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    return null;
  }

  String _extractErrorMessage(Map<String, dynamic> res, Object? error) {
    if (error != null) {
      final text = error.toString();
      if (text.contains('PIN incorrecto') ||
          text.contains('incorrectos') ||
          text.contains('no encontrado')) {
        return text.replaceFirst('Exception: ', '');
      }
    }

    return res['message']?.toString() ??
        res['error']?.toString() ??
        'Credenciales incorrectas';
  }

  Future<Map<String, dynamic>> login(String usuario, String password) async {
    try {
      final baseUrl = await _resolveBaseUrl();
      final idServicio = await DeviceService().obtenerIdServicio();
      final res = await ApiClient.post(
        '/api/auth/login',
        body: {
          'usuario': usuario,
          'password': password,
          'documento': usuario,
          'pin': password,
          'id_servicio': idServicio,
          'plataforma': Platform.isAndroid
              ? 'android'
              : (Platform.isIOS ? 'ios' : 'otro'),
        },
        customBaseUrl: baseUrl,
        timeout: const Duration(seconds: 15),
      );

      final response = Map<String, dynamic>.from(res as Map);

      if (response['needsActivation'] == true) {
        return {
          'success': false,
          'needsActivation': true,
          'id_servicio': response['id_servicio']?.toString() ?? idServicio,
          'message': response['message']?.toString() ??
              'Dispositivo pendiente de autorización',
        };
      }

      if (response['success'] == true) {
        final token = _extractToken(response);
        if (token == null || token.isEmpty) {
          return {
            'success': false,
            'message': 'El servidor no devolvió un token de sesión válido',
          };
        }

        _token = token;
        _expira = _expiraDeRespuesta(response) ??
            _expiraDeToken(token) ??
            DateTime.now().add(const Duration(hours: 12));
        _usuario = _extractUsuario(response);
        _loginUsuario = usuario;
        _cache.limpiar();
        await _persistSession();

        return {
          'success': true,
          'message': response['message']?.toString() ?? 'Inicio de sesión exitoso',
        };
      }

      return {
        'success': false,
        'message': _extractErrorMessage(response, null),
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      };
    }
  }

  Future<String> _baseUrlForRequest() async {
    return _resolvedBaseUrl ?? await _resolveBaseUrl();
  }


  Future<Map<String, dynamic>> getDispositivos({String? buscar}) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
    }
    try {
      final query = (buscar != null && buscar.trim().isNotEmpty)
          ? '?buscar=${Uri.encodeQueryComponent(buscar.trim())}'
          : '';
      final res = await ApiClient.get(
        '/api/dispositivos$query',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        final list = res['data'] as List<dynamic>? ?? [];
        return {'success': true, 'data': list, 'total': res['total'] ?? list.length};
      }
      return {
        'success': false,
        'message': res['message']?.toString() ?? 'Error al cargar dispositivos',
        'data': <dynamic>[],
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
        'data': <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> getUsuarios({String? buscar}) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
    }
    try {
      final query = (buscar != null && buscar.trim().isNotEmpty)
          ? '?buscar=${Uri.encodeQueryComponent(buscar.trim())}'
          : '';
      final res = await ApiClient.get(
        '/api/usuarios$query',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      if (res['success'] == true) {
        final list = res['data'] as List<dynamic>? ?? [];
        return {
          'success': true,
          'data': list,
          'total': res['total'] ?? list.length,
          'soporte': (res['soporte'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[],
          'avisos': (res['avisos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[],
        };
      }
      return {
        'success': false,
        'message': res['message']?.toString() ?? 'Error al cargar usuarios',
        'data': <dynamic>[],
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
        'data': <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> setDispositivoEstado(
      String idServicio, String estado) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/dispositivos/${Uri.encodeComponent(idServicio)}/estado',
        body: {'estado': estado},
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      return {
        'success': res['success'] == true,
        'estado': res['estado']?.toString() ?? estado,
        'message': res['message']?.toString() ??
            (res['success'] == true ? 'Estado actualizado' : 'No se pudo actualizar'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      };
    }
  }

  Future<Map<String, dynamic>> deleteDispositivo(String idServicio) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.delete(
        '/api/dispositivos/${Uri.encodeComponent(idServicio)}',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ??
            (res['success'] == true ? 'Dispositivo eliminado' : 'No se pudo eliminar'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceFirst('Exception: ', ''),
      };
    }
  }


  Future<Map<String, dynamic>> getProductosAdmin() async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
    }
    try {
      final res = await ApiClient.get(
        '/api/productos/admin',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 40),
      );
      if (res['success'] == true) {
        return {
          'success': true,
          'data': res['productos'] as List<dynamic>? ?? [],
          'categorias': (res['categorias'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[],
          'fuente': res['fuente']?.toString() ?? '',
          'actualizado': res['actualizado']?.toString() ?? '',
        };
      }
      return {'success': false, 'message': res['message']?.toString() ?? 'Error al cargar productos', 'data': <dynamic>[]};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', ''), 'data': <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> subirImagenProducto(String codigo, String rutaArchivo) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final base = await _baseUrlForRequest();
      final req = http.MultipartRequest(
        'PUT',
        Uri.parse('$base/api/productos/${Uri.encodeComponent(codigo)}/imagen'),
      );
      req.headers['Authorization'] = 'Bearer $_token';
      req.headers['Accept'] = 'application/json';
      req.files.add(await http.MultipartFile.fromPath('imagen', rutaArchivo));
      final streamed = await SharedHttp.client.send(req).timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && data is Map && data['success'] == true) {
        return {'success': true, 'imagenUrl': data['imagenUrl']?.toString()};
      }
      return {
        'success': false,
        'message': (data is Map ? data['message']?.toString() : null) ?? 'No se pudo subir la imagen',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> subirEvidencia(
    String rutaArchivo, {
    required String origen,
    String numeroRecaudo = '',
    String numeroPedido = '',
    String clienteId = '',
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final base = await _baseUrlForRequest();
      final req = http.MultipartRequest('POST', Uri.parse('$base/api/evidencias'));
      req.headers['Authorization'] = 'Bearer $_token';
      req.headers['Accept'] = 'application/json';
      req.fields['origen'] = origen;
      if (numeroRecaudo.isNotEmpty) req.fields['numeroRecaudo'] = numeroRecaudo;
      if (numeroPedido.isNotEmpty) req.fields['numeroPedido'] = numeroPedido;
      if (clienteId.isNotEmpty) req.fields['clienteId'] = clienteId;
      req.files.add(await http.MultipartFile.fromPath('foto', rutaArchivo));
      final streamed = await SharedHttp.client.send(req).timeout(const Duration(seconds: 45));
      final res = await http.Response.fromStream(streamed);
      final tipo = res.headers['content-type'] ?? '';
      if (tipo.contains('application/json')) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (res.statusCode == 200 && data is Map && data['success'] == true) {
          return {'success': true, 'id': (data['data'] is Map) ? data['data']['id'] : null};
        }
        return {
          'success': false,
          'message': (data is Map ? data['message']?.toString() : null) ?? 'No se pudo subir la evidencia',
        };
      }
      return {'success': false, 'message': 'No se pudo subir la evidencia (${res.statusCode})'};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> eliminarImagenProducto(String codigo) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.delete(
        '/api/productos/${Uri.encodeComponent(codigo)}/imagen',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      return {'success': res['success'] == true, 'message': res['message']?.toString() ?? ''};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> guardarConfigProducto(String codigo, Map<String, dynamic> cambios) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.put(
        '/api/productos/${Uri.encodeComponent(codigo)}/config',
        body: cambios,
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      return {'success': res['success'] == true, 'message': res['message']?.toString() ?? ''};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> refrescarCatalogo() async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/productos/refrescar',
        body: const {},
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 60),
      );
      return {
        'success': res['success'] == true,
        'articulos': res['articulos'],
        'fuente': res['fuente']?.toString() ?? '',
        'message': res['message']?.toString() ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> getClientes({bool forzar = false}) {
    return _cache.obtener(
      'clientes',
      const Duration(minutes: 10),
      _getClientesRed,
      forzar: forzar,
      guardarSi: (r) => r['success'] == true,
    );
  }

  Future<Map<String, dynamic>> _getClientesRed() async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
    }

    try {
      final res = await ApiClient.get(
        '/api/clientes',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );

      if (res['success'] == true) {
        final list = res['data'] as List<dynamic>? ?? [];
        return {'success': true, 'data': list, 'total': res['total'] ?? list.length};
      }

      return {
        'success': false,
        'message': res['message']?.toString() ?? 'Error al cargar clientes',
        'data': <dynamic>[],
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
      }
      return {'success': false, 'message': 'Error: ${e.toString()}', 'data': <dynamic>[]};
    }
  }

  bool _esSesionExpirada(Object e) {
    if (e is ApiException) return e.noAutorizado;
    final s = e.toString().toLowerCase();
    return s.contains('401') || s.contains('sesión expirada') || s.contains('sesion expirada');
  }

  Future<Map<String, dynamic>?> getClientePorCodigo(String codigo) {
    return _cache.obtener(
      'cliente:$codigo',
      const Duration(minutes: 5),
      () => _getClientePorCodigoRed(codigo),
    );
  }

  Future<Map<String, dynamic>?> _getClientePorCodigoRed(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;

    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );

      if (res['success'] == true) {
        return res['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> actualizarDatosCliente(
    String codigo, {
    String nombre = '',
    String direccion = '',
    String telefono = '',
    String correo = '',
    String ciudad = '',
    int? rutaId,
    Map<String, dynamic>? anteriores,
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/actualizar-datos',
        body: {
          'nombre': nombre,
          'direccion': direccion,
          'telefono': telefono,
          'correo': correo,
          'ciudad': ciudad,
          if (rutaId != null) 'rutaId': rutaId,
          if (anteriores != null) 'anteriores': anteriores,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      if (res['success'] == true) {
        _cache.invalidar('cliente:$codigo');
        _cache.invalidar('clientes');
      }
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ?? '',
        'fechaActualizacion':
            (res['data'] is Map) ? res['data']['fechaActualizacion'] : null,
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada'};
      }
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> guardarGestionPedido({
    String numeroPedido = '',
    required String clienteId,
    String clienteNombre = '',
    double subtotal = 0,
    double descuento = 0,
    double impuesto = 0,
    double flete = 0,
    double total = 0,
    String formaPago = '',
    String bancoPago = '',
    String referenciaPago = '',
    String numeroRecaudo = '',
    int? plazoDias,
    String fechaEntrega = '',
    String observaciones = '',
    int evidencias = 0,
    String estado = 'GUARDADO',
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/pedidos/gestion',
        body: {
          'numeroPedido': numeroPedido,
          'clienteId': clienteId,
          'clienteNombre': clienteNombre,
          'subtotal': subtotal,
          'descuento': descuento,
          'impuesto': impuesto,
          'flete': flete,
          'total': total,
          'formaPago': formaPago,
          'bancoPago': bancoPago,
          'referenciaPago': referenciaPago,
          if (numeroRecaudo.isNotEmpty) 'numeroRecaudo': numeroRecaudo,
          if (plazoDias != null) 'plazoDias': plazoDias,
          'fechaEntrega': fechaEntrega,
          'observaciones': observaciones,
          'evidencias': evidencias,
          'estado': estado,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ?? '',
        'id': (res['data'] is Map) ? res['data']['id'] : null,
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada'};
      }
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> getDocumentosCliente(String codigo) async {
    if (_token == null || _token!.isEmpty) {
      return {'documentos': <Map<String, dynamic>>[], 'totalSaldo': 0.0};
    }
    final datos = await _cache.obtener<Map<String, dynamic>?>(
      'documentos:$codigo',
      const Duration(minutes: 2),
      () => _getDocumentosClienteRed(codigo),
    );
    return datos ?? {'documentos': <Map<String, dynamic>>[], 'totalSaldo': 0.0};
  }

  Future<Map<String, dynamic>?> _getDocumentosClienteRed(String codigo) async {
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/documentos',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      if (res['success'] == true) {
        final list = (res['data'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return {
          'documentos': list,
          'totalSaldo': (res['totalSaldo'] as num?)?.toDouble() ?? 0.0,
        };
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _recaudoConFotos(
    Map<String, dynamic> campos,
    List<String> fotos,
  ) async {
    final base = await _baseUrlForRequest();
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/recaudos'));
    req.headers['Authorization'] = 'Bearer $_token';
    req.headers['Accept'] = 'application/json';
    campos.forEach((k, v) {
      req.fields[k] = v is String ? v : jsonEncode(v);
    });
    for (final ruta in fotos) {
      req.files.add(await http.MultipartFile.fromPath('fotos', ruta));
    }
    final streamed = await SharedHttp.client.send(req).timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    final tipo = res.headers['content-type'] ?? '';
    if (tipo.contains('application/json')) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return {'success': false, 'message': 'No se pudo guardar el recaudo (${res.statusCode})'};
  }

  Future<Map<String, dynamic>> guardarRecaudo({
    String numeroRecaudo = '',
    required String clienteId,
    String clienteNombre = '',
    String formaPago = '',
    String bancoPago = '',
    String referenciaPago = '',
    double totalDocumentos = 0,
    double totalAplicado = 0,
    double totalRecaudo = 0,
    double saldo = 0,
    String notas = '',
    required List<Map<String, dynamic>> documentos,
    List<String> fotos = const [],
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    final campos = <String, dynamic>{
      'numeroRecaudo': numeroRecaudo,
      'clienteId': clienteId,
      'clienteNombre': clienteNombre,
      'formaPago': formaPago,
      'bancoPago': bancoPago,
      'referenciaPago': referenciaPago,
      'totalDocumentos': totalDocumentos,
      'totalAplicado': totalAplicado,
      'totalRecaudo': totalRecaudo,
      'saldo': saldo,
      'notas': notas,
      'documentos': documentos,
    };
    try {
      // Con fotos se envia todo en una sola peticion para que el servidor
      // guarde recaudo, documentos y evidencias en la misma transaccion.
      final res = fotos.isEmpty
          ? await ApiClient.post(
              '/api/recaudos',
              body: campos,
              customBaseUrl: await _baseUrlForRequest(),
              headers: _headers,
              timeout: const Duration(seconds: 25),
            )
          : await _recaudoConFotos(campos, fotos);
      if (res['success'] == true) {
        _cache.invalidar('documentos:$clienteId');
        _cache.invalidar('cartera:$clienteId');
      }
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ?? '',
        'numeroRecaudo': (res['data'] is Map) ? res['data']['numeroRecaudo'] : null,
        'evidencias': (res['data'] is Map) ? (res['data']['evidencias'] ?? 0) : 0,
        'reciboCaja': (res['data'] is Map) ? res['data']['reciboCaja'] : null,
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada'};
      }
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  /// GET /api/talonarios/siguiente - recibo de caja que le sigue al usuario
  /// (talonario cuyo prefijo es el usuario de inicio de sesión).
  Future<Map<String, dynamic>?> getSiguienteReciboCaja() async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/talonarios/siguiente',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );
      if (res is Map && res['success'] == true) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getCarteraCliente(String codigo) {
    return _cache.obtener(
      'cartera:$codigo',
      const Duration(minutes: 2),
      () => _getCarteraClienteRed(codigo),
    );
  }

  Future<Map<String, dynamic>?> _getCarteraClienteRed(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;

    try {
      final res = await ApiClient.get(
        '/api/clientes/cartera/$codigo',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );

      if (res['success'] == true) {
        return res['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getGeocodeCliente(String codigo, {String? address}) async {
    if (_token == null || _token!.isEmpty) return null;
    final clave = 'geo:$codigo:${(address ?? '').trim().toUpperCase()}';

    final enMemoria = _cache.leer<Map<String, dynamic>>(clave);
    if (enMemoria != null) return enMemoria;

    const maxEdad = Duration(days: 30);
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getString(clave);
      if (guardado != null) {
        final decoded = jsonDecode(guardado);
        if (decoded is Map) {
          final ts = decoded['ts'];
          final geoRaw = decoded['geo'];
          if (ts is num && geoRaw is Map) {
            final edad = DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ts.toInt()));
            if (edad <= maxEdad) {
              final geo = Map<String, dynamic>.from(geoRaw);
              _cache.guardar(clave, geo, maxEdad - edad);
              return geo;
            }
            await prefs.remove(clave);
          } else {
            final geo = Map<String, dynamic>.from(decoded);
            await prefs.setString(clave, _sobreGeo(geo));
            _cache.guardar(clave, geo, maxEdad);
            return geo;
          }
        }
      }
    } catch (_) {}

    final geo = await _cache.obtener<Map<String, dynamic>?>(
      clave,
      maxEdad,
      () => _getGeocodeClienteRed(codigo, address),
    );
    if (geo != null) {
      try {
        await prefs?.setString(clave, _sobreGeo(geo));
      } catch (_) {}
    }
    return geo;
  }

  static String _sobreGeo(Map<String, dynamic> geo) =>
      jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch, 'geo': geo});

  Future<Map<String, dynamic>?> _getGeocodeClienteRed(String codigo, String? address) async {
    try {
      final qp = address != null && address.isNotEmpty
          ? '?address=${Uri.encodeQueryComponent(address)}'
          : '';
      final res = await ApiClient.get(
        '/api/clientes/$codigo/geocode$qp',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getTareasCliente(String codigo) {
    return _cache.obtener(
      'tareas:$codigo',
      const Duration(minutes: 5),
      () => _getTareasClienteRed(codigo),
    );
  }

  Future<Map<String, dynamic>?> _getTareasClienteRed(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/tareas',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getSugerenciasIA(String codigo, {
    Map<String, dynamic>? cliente,
    Map<String, dynamic>? ruta,
    bool forzar = false,
  }) {
    return _cache.obtener(
      'sugerenciaIA:$codigo',
      const Duration(hours: 1),
      () => _getSugerenciasIARed(codigo, cliente: cliente, ruta: ruta, forzar: forzar),
      forzar: forzar,
    );
  }

  Future<String?> _getSugerenciasIARed(String codigo, {
    Map<String, dynamic>? cliente,
    Map<String, dynamic>? ruta,
    bool forzar = false,
  }) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/ia/sugerencias',
        body: {
          if (cliente != null) 'cliente': cliente,
          if (ruta != null) 'ruta': ruta,
          if (forzar) 'forzar': true,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 30),
      );
      if (res['success'] == true) {
        return (res['data'] as Map)['respuesta']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> chatIA(String codigo, String pregunta, {
    Map<String, dynamic>? cliente,
    Map<String, dynamic>? ruta,
  }) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/ia/chat',
        body: {
          'pregunta': pregunta,
          if (cliente != null) 'cliente': cliente,
          if (ruta != null) 'ruta': ruta,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 30),
      );
      if (res['success'] == true) {
        return (res['data'] as Map)['respuesta']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getMisRutas({String periodo = 'todas', bool forzar = false}) {
    return _cache.obtener(
      'rutasMias:$periodo',
      const Duration(minutes: 2),
      () => _getMisRutasRed(periodo),
      forzar: forzar,
    );
  }

  Future<Map<String, dynamic>?> _getMisRutasRed(String periodo) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/rutas/mias?periodo=$periodo',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> crearRutaExtra({
    required String clienteId,
    String clienteNombre = '',
    String ciudad = '',
    required String motivo,
    required String observacion,
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/rutas/extra',
        body: {
          'clienteId': clienteId,
          'clienteNombre': clienteNombre,
          'ciudad': ciudad,
          'motivo': motivo,
          'observacion': observacion,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 20),
      );
      if (res['success'] == true) {
        _cache.invalidarPrefijo('rutasMias:');
        _cache.invalidar('rutasCliente:$clienteId');
      }
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ?? '',
        'id': (res['data'] is Map) ? res['data']['id'] : null,
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada'};
      }
      final msg = e.toString().replaceFirst('Exception: ', '');
      return {'success': false, 'message': msg};
    }
  }

  Future<Map<String, dynamic>?> getRutasCliente(String codigo, {int limite = 100}) {
    return _cache.obtener(
      'rutasCliente:$codigo',
      const Duration(minutes: 2),
      () => _getRutasClienteRed(codigo, limite),
    );
  }

  Future<Map<String, dynamic>?> _getRutasClienteRed(String codigo, int limite) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/rutas?limite=$limite',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getFacturasHistoricasCliente(String codigo, {int limite = 100}) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/facturas-historico?limite=$limite',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getComentariosCliente(String codigo) async {
    if (_token == null || _token!.isEmpty) {
      return {'comentarios': <Map<String, dynamic>>[], 'freeText': ''};
    }

    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/comentarios',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );

      if (res['success'] == true) {
        final list = res['data'] as List<dynamic>? ?? [];
        return {
          'comentarios': list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
          'freeText': res['freeText']?.toString() ?? '',
        };
      }
    } catch (_) {}
    return {'comentarios': <Map<String, dynamic>>[], 'freeText': ''};
  }

  Future<Map<String, dynamic>?> crearComentarioCliente(String codigo, String comentario) async {
    if (_token == null || _token!.isEmpty) return null;
    final texto = comentario.trim();
    if (texto.isEmpty) return null;

    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/comentarios',
        body: {'comentario': texto},
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );

      if (res['success'] == true) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> registrarVisita(
    String codigo, {
    String? estadoCliente,
    String observacion = '',
    String? motivo,
    int? rutaId,
    double? totalPedidos,
    double? totalCartera,
    double? totalRecaudos,
    String? metodoPago,
    String? bancoPago,
    String? referenciaPago,
    String? numeroRecaudo,
    DateTime? horaInicio,
    DateTime? horaFin,
    int? duracionSegundos,
    String? encuestaTipo,
    Map<String, dynamic>? encuestaRespuestas,
    bool segundaVisita = false,
    String? motivoSegundaVisita,
  }) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/visita',
        body: {
          if (estadoCliente != null && estadoCliente.isNotEmpty) 'estadoCliente': estadoCliente,
          if (observacion.isNotEmpty) 'observacion': observacion,
          if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
          if (rutaId != null) 'rutaId': rutaId,
          if (totalPedidos != null) 'totalPedidos': totalPedidos,
          if (totalCartera != null) 'totalCartera': totalCartera,
          if (totalRecaudos != null) 'totalRecaudos': totalRecaudos,
          if (metodoPago != null && metodoPago.isNotEmpty) 'metodoPago': metodoPago,
          if (bancoPago != null && bancoPago.isNotEmpty) 'bancoPago': bancoPago,
          if (referenciaPago != null && referenciaPago.isNotEmpty) 'referenciaPago': referenciaPago,
          if (numeroRecaudo != null && numeroRecaudo.isNotEmpty) 'numeroRecaudo': numeroRecaudo,
          if (horaInicio != null) 'horaInicio': horaInicio.toIso8601String(),
          if (horaFin != null) 'horaFin': horaFin.toIso8601String(),
          if (duracionSegundos != null) 'duracionSegundos': duracionSegundos,
          if (encuestaTipo != null && encuestaTipo.isNotEmpty) 'encuestaTipo': encuestaTipo,
          if (encuestaRespuestas != null) 'encuestaRespuestas': encuestaRespuestas,
          if (segundaVisita) 'segundaVisita': true,
          if (motivoSegundaVisita != null && motivoSegundaVisita.isNotEmpty)
            'motivoSegundaVisita': motivoSegundaVisita,
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        _cache.invalidar('cartera:$codigo');
        _cache.invalidar('tareas:$codigo');
        _cache.invalidar('visitasHoy:$codigo');
        _cache.invalidar('ultimaVisita:$codigo');
        _cache.invalidar('rutasCliente:$codigo');
        _cache.invalidarPrefijo('rutasMias:');
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getVisitasHoy(String codigo) {
    return _cache.obtener(
      'visitasHoy:$codigo',
      const Duration(minutes: 1),
      () => _getVisitasHoyRed(codigo),
    );
  }

  Future<Map<String, dynamic>?> _getVisitasHoyRed(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/visitas-hoy',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );
      if (res['success'] == true && res['data'] != null) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getUltimoPedido(String codigo, {DateTime? desde}) {
    return _cache.obtener(
      'pedidos:$codigo:ultimo:${desde?.toIso8601String() ?? ''}',
      const Duration(minutes: 2),
      () => _getUltimoPedidoRed(codigo, desde),
    );
  }

  Future<Map<String, dynamic>?> _getUltimoPedidoRed(String codigo, DateTime? desde) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final qp = desde != null ? '?desde=${Uri.encodeQueryComponent(desde.toIso8601String())}' : '';
      final res = await ApiClient.get(
        '/api/clientes/$codigo/ultimo-pedido$qp',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 12),
      );
      if (res['success'] == true && res['data'] != null) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<double> getTotalPedidos(String codigo, {DateTime? desde}) async {
    if (_token == null || _token!.isEmpty) return 0;
    final total = await _cache.obtener<double?>(
      'pedidos:$codigo:total:${desde?.toIso8601String() ?? ''}',
      const Duration(minutes: 2),
      () => _getTotalPedidosRed(codigo, desde),
    );
    return total ?? 0;
  }

  Future<double?> _getTotalPedidosRed(String codigo, DateTime? desde) async {
    try {
      final qp = desde != null ? '?desde=${Uri.encodeQueryComponent(desde.toIso8601String())}' : '';
      final res = await ApiClient.get(
        '/api/clientes/$codigo/pedidos-total$qp',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );
      if (res['success'] == true && res['data'] != null) {
        return (res['data']['total'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getUltimaVisita(String codigo) {
    return _cache.obtener(
      'ultimaVisita:$codigo',
      const Duration(minutes: 2),
      () => _getUltimaVisitaRed(codigo),
    );
  }

  Future<Map<String, dynamic>?> _getUltimaVisitaRed(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/visita/ultima',
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );
      if (res['success'] == true && res['data'] != null) {
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> actualizarFreeTextCliente(String codigo, String texto) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.put(
        '/api/clientes/$codigo/free-text',
        body: {'texto': texto},
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );
      if (res['success'] == true) {
        return res['freeText']?.toString() ?? '';
      }
    } catch (_) {}
    return null;
  }
}
