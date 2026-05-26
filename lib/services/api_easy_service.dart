import 'api_client.dart';

/// Servicio para conectar con API-EASY (auth + clientes por vendor)
class ApiEasyService {
  ApiEasyService._();
  static final ApiEasyService _instance = ApiEasyService._();
  factory ApiEasyService() => _instance;

  /// URL base de la API
  static const String baseUrl = 'http://192.168.2.73:3000';

  String? _token;
  Map<String, dynamic>? _usuario;
  String _loginUsuario = '';

  String? get token => _token;
  Map<String, dynamic>? get usuario => _usuario;
  String get loginUsuario => _loginUsuario;
  bool get hasSession => _token != null && _token!.isNotEmpty;

  void setToken(String? t) {
    _token = t;
  }

  void setUsuario(Map<String, dynamic>? u) {
    _usuario = u;
  }

  void clearSession() {
    _token = null;
    _usuario = null;
    _loginUsuario = '';
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

  /// POST /api/auth/login
  /// Body: { usuario, password }
  Future<Map<String, dynamic>> login(String usuario, String password) async {
    try {
      final res = await ApiClient.post(
        '/api/auth/login',
        body: {'usuario': usuario, 'password': password},
        customBaseUrl: baseUrl,
        timeout: const Duration(seconds: 15),
      );

      if (res['success'] == true) {
        final d = res['data'] as Map<String, dynamic>? ?? {};
        _token = d['token']?.toString();
        _usuario = d['usuario'] as Map<String, dynamic>?;
        _loginUsuario = usuario;
        return {'success': true, 'message': res['message'] ?? 'Inicio de sesión exitoso'};
      }

      return {
        'success': false,
        'message': res['message']?.toString() ?? 'Usuario o contraseña incorrectos',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error de conexión: ${e.toString()}'};
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
        customBaseUrl: baseUrl,
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
      if (e.toString().contains('401')) {
        clearSession();
        return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
      }
      return {'success': false, 'message': 'Error: ${e.toString()}', 'data': <dynamic>[]};
    }
  }

  /// GET /api/clientes/:codigo - Detalle de un cliente
  Future<Map<String, dynamic>?> getClientePorCodigo(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;

    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo',
        customBaseUrl: baseUrl,
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

  /// GET /api/clientes/cartera/:codigo - Cartera completa del cliente desde SAP
  Future<Map<String, dynamic>?> getCarteraCliente(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;

    try {
      final res = await ApiClient.get(
        '/api/clientes/cartera/$codigo',
        customBaseUrl: baseUrl,
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

  /// GET /api/clientes/:codigo/comentarios
  /// Returns { 'comentarios': List, 'freeText': String }
  Future<Map<String, dynamic>> getComentariosCliente(String codigo) async {
    if (_token == null || _token!.isEmpty) {
      return {'comentarios': <Map<String, dynamic>>[], 'freeText': ''};
    }

    try {
      final res = await ApiClient.get(
        '/api/clientes/$codigo/comentarios',
        customBaseUrl: baseUrl,
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
        customBaseUrl: baseUrl,
        headers: _headers,
        timeout: const Duration(seconds: 15),
      );

      if (res['success'] == true) {
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
        customBaseUrl: baseUrl,
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
