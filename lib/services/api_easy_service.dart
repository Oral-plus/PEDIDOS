import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'device_service.dart';

/// Servicio para conectar con API-EASY (auth + clientes por vendor)
class ApiEasyService {
  ApiEasyService._();
  static final ApiEasyService _instance = ApiEasyService._();
  factory ApiEasyService() => _instance;

  static const List<String> _baseUrls = [
    // URL publica: el proxy del servidor 192.168.2.249 enruta /pedidos-api/*
    // al backend de pedidos (server.js:3000) quitando el prefijo. Funciona
    // dentro y fuera de la oficina (el router hace hairpin NAT). El dominio
    // "pelado" (sin prefijo) responde la API SAP, que NO tiene rutas de auth.
    'https://pedidos.oral-plus.com/pedidos-api',
    // Acceso directo por LAN al backend desplegado en el servidor .249
    // (sirve aunque se caiga el internet de la oficina).
    'http://192.168.2.249:3000',
    // PC de desarrollo (fallback mientras el backend siga corriendo ahi).
    'http://192.168.2.73:3000',
    'http://10.0.2.2:3000',
    'http://localhost:3000',
  ];

  static const _tokenKey = 'auth_token';
  static const _usuarioKey = 'auth_usuario';
  static const _loginUsuarioKey = 'login_usuario';

  String? _token;
  Map<String, dynamic>? _usuario;
  String _loginUsuario = '';
  String? _resolvedBaseUrl;
  bool _sessionRestored = false;

  String? get token => _token;
  Map<String, dynamic>? get usuario => _usuario;
  String get loginUsuario => _loginUsuario;
  bool get hasSession => _token != null && _token!.isNotEmpty;

  /// true si la sesión actual es de un usuario de Soporte TI.
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
        if (_usuario != null) {
          await prefs.setString(_usuarioKey, jsonEncode(_usuario));
        } else {
          await prefs.remove(_usuarioKey);
        }
      } else {
        await prefs.remove(_tokenKey);
        await prefs.remove(_usuarioKey);
        await prefs.remove(_loginUsuarioKey);
      }
    } catch (_) {}
  }

  Future<void> clearSession() async {
    _token = null;
    _usuario = null;
    _loginUsuario = '';
    await _persistSession();
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

  Future<String> _resolveBaseUrl() async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;

    String? aliveFallback;

    for (final baseUrl in _baseUrls) {
      try {
        final res = await ApiClient.get(
          '/api/test',
          customBaseUrl: baseUrl,
          timeout: const Duration(seconds: 5),
        );
        if (res is Map && res['success'] == true) {
          // /api/test puede responder en servidores que no tienen las rutas
          // de auth (p. ej. la API SAP remota); verificar antes de aceptar.
          // Como fallback preferimos un servidor local (tiene todos los
          // endpoints) por encima del remoto SAP.
          final esRemoto = baseUrl.contains('pedidos.oral-plus.com');
          if (aliveFallback == null ||
              (!esRemoto && aliveFallback.contains('pedidos.oral-plus.com'))) {
            aliveFallback = baseUrl;
          }
          if (await _hasAuthRoutes(baseUrl)) {
            _resolvedBaseUrl = baseUrl;
            return baseUrl;
          }
        }
      } catch (_) {
        continue;
      }
    }

    // Solo cacheamos cuando encontramos un servidor con auth (arriba). Si solo
    // hay un fallback sin auth (p. ej. el servidor local estaba reiniciándose),
    // lo usamos pero NO lo cacheamos, para reintentar en la próxima llamada y
    // auto-recuperarnos cuando el servidor local vuelva.
    return aliveFallback ?? _baseUrls.first;
  }

  /// Verifica que el servidor exponga /api/auth/login. Un POST vacío debe
  /// responder 400 "Usuario y contraseña son requeridos"; esa firma solo la
  /// da el server.js real. Un 404, una conexión cortada por el proxy o
  /// cualquier error de red significan que este servidor no sirve.
  Future<bool> _hasAuthRoutes(String baseUrl) async {
    try {
      await ApiClient.post(
        '/api/auth/login',
        body: const {},
        customBaseUrl: baseUrl,
        timeout: const Duration(seconds: 5),
      );
      return true;
    } catch (e) {
      return e.toString().contains('requeridos');
    }
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
        'Usuario o contraseña incorrectos';
  }

  /// POST /api/auth/login
  /// Compatible con {usuario,password} y {documento,pin}
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

      // Dispositivo aún no autorizado: el backend responde con needsActivation
      // y el ID para que el vendedor lo envíe a Soporte TI.
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
        _usuario = _extractUsuario(response);
        _loginUsuario = usuario;
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

  // ---------------------------------------------------------------------------
  //  Soporte TI: administración de dispositivos (requiere sesión rol soporte)
  // ---------------------------------------------------------------------------

  /// GET /api/dispositivos — lista dispositivos con la persona asociada.
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

  /// POST /api/dispositivos/:id/estado — activa/desactiva un dispositivo.
  /// estado: 'ACTIVO' | 'DESACTIVADO' | 'PENDIENTE'.
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

  /// DELETE /api/dispositivos/:id — elimina un dispositivo del registro.
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

  /// GET /api/clientes - Lista de clientes del vendor (requiere token)
  Future<Map<String, dynamic>> getClientes() async {
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

  /// Detecta si un error corresponde a sesión expirada / no autorizada.
  bool _esSesionExpirada(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('401') || s.contains('sesión expirada') || s.contains('sesion expirada');
  }

  /// GET /api/clientes/:codigo - Detalle de un cliente
  Future<Map<String, dynamic>?> getClientePorCodigo(String codigo) async {
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

  /// POST /api/clientes/:codigo/actualizar-datos — corrige los datos de
  /// contacto del cliente (se guarda en nuestra BD, no en SAP).
  /// Devuelve { success, message, fechaActualizacion? }.
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

  /// POST /api/pedidos/gestion — guarda la gestión del pedido de la visita
  /// (liquidación, condiciones, forma de pago, evidencias).
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

  /// GET /api/clientes/:codigo/documentos - Facturas abiertas del cliente
  /// (para recaudos). Devuelve { documentos: List, totalSaldo: double }.
  Future<Map<String, dynamic>> getDocumentosCliente(String codigo) async {
    if (_token == null || _token!.isEmpty) {
      return {'documentos': <Map<String, dynamic>>[], 'totalSaldo': 0.0};
    }
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
    return {'documentos': <Map<String, dynamic>>[], 'totalSaldo': 0.0};
  }

  /// POST /api/recaudos - Guarda un recaudo con los documentos cruzados.
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
  }) async {
    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Sesión expirada'};
    }
    try {
      final res = await ApiClient.post(
        '/api/recaudos',
        body: {
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
        },
        customBaseUrl: await _baseUrlForRequest(),
        headers: _headers,
        timeout: const Duration(seconds: 25),
      );
      return {
        'success': res['success'] == true,
        'message': res['message']?.toString() ?? '',
        'numeroRecaudo': (res['data'] is Map) ? res['data']['numeroRecaudo'] : null,
      };
    } catch (e) {
      if (_esSesionExpirada(e)) {
        await clearSession();
        return {'success': false, 'message': 'Sesión expirada'};
      }
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  /// GET /api/clientes/cartera/:codigo - Cartera completa del cliente desde SAP
  Future<Map<String, dynamic>?> getCarteraCliente(String codigo) async {
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

  /// GET /api/clientes/:codigo/geocode — geocodifica la dirección del cliente
  /// Retorna { lat, lng, formattedAddress, placeId }
  Future<Map<String, dynamic>?> getGeocodeCliente(String codigo, {String? address}) async {
    if (_token == null || _token!.isEmpty) return null;
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

  /// GET /api/clientes/:codigo/tareas — tareas asignadas al cliente
  Future<Map<String, dynamic>?> getTareasCliente(String codigo) async {
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

  /// POST /api/clientes/:codigo/ia/sugerencias — recomendaciones IA para la visita
  Future<String?> getSugerenciasIA(String codigo, {
    Map<String, dynamic>? cliente,
    Map<String, dynamic>? ruta,
  }) async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      final res = await ApiClient.post(
        '/api/clientes/$codigo/ia/sugerencias',
        body: {
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

  /// POST /api/clientes/:codigo/ia/chat — pregunta al asistente IA
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

  /// GET /api/rutas/mias?periodo=hoy|semana|mes|todas — mis rutas del periodo
  Future<Map<String, dynamic>?> getMisRutas({String periodo = 'todas'}) async {
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

  /// POST /api/rutas/extra — crea una ruta adicional de urgencia.
  /// Requiere cliente + motivo (por qué visita) + observación.
  /// Devuelve { success, message, id? }.
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
      // ApiClient lanza el mensaje del backend (p. ej. validaciones)
      final msg = e.toString().replaceFirst('Exception: ', '');
      return {'success': false, 'message': msg};
    }
  }

  /// GET /api/clientes/:codigo/rutas — rutas registradas para el cliente
  Future<Map<String, dynamic>?> getRutasCliente(String codigo, {int limite = 100}) async {
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

  /// GET /api/clientes/:codigo/facturas-historico — todas las facturas (pagadas/abiertas)
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

  /// GET /api/clientes/:codigo/comentarios
  /// Returns { 'comentarios': List, 'freeText': String }
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

  /// POST /api/clientes/:codigo/comentarios
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

  /// POST /api/clientes/:codigo/visita — registra / finaliza una visita
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
        return Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// GET /api/clientes/:codigo/visitas-hoy — ¿ya se visitó hoy?
  Future<Map<String, dynamic>?> getVisitasHoy(String codigo) async {
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

  /// GET /api/clientes/:codigo/ultimo-pedido — último pedido con ítems
  Future<Map<String, dynamic>?> getUltimoPedido(String codigo, {DateTime? desde}) async {
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

  /// GET /api/clientes/:codigo/pedidos-total — total de pedidos (opcionalmente desde una fecha)
  Future<double> getTotalPedidos(String codigo, {DateTime? desde}) async {
    if (_token == null || _token!.isEmpty) return 0;
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
    return 0;
  }

  /// GET /api/clientes/:codigo/visita/ultima — última visita registrada
  Future<Map<String, dynamic>?> getUltimaVisita(String codigo) async {
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

  /// PUT /api/clientes/:codigo/free-text — actualizar texto libre en OCRD
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
