import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio para conectar con API-EASY (auth + clientes por vendor)
class ApiEasyService {
  ApiEasyService._();
  static final ApiEasyService _instance = ApiEasyService._();
  factory ApiEasyService() => _instance;

  /// URL base de la API
  static const String baseUrl = 'http://localhost:3000';

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
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: _headers,
            body: jsonEncode({'usuario': usuario, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

      if (res.statusCode == 200 && data['success'] == true) {
        final d = data['data'] as Map<String, dynamic>? ?? {};
        _token = d['token']?.toString();
        _usuario = d['usuario'] as Map<String, dynamic>?;
        _loginUsuario = usuario;
        return {'success': true, 'message': data['message'] ?? 'Inicio de sesión exitoso'};
      }

      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Usuario o contraseña incorrectos',
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
      final res = await http
          .get(Uri.parse('$baseUrl/api/clientes'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

      if (res.statusCode == 200 && data['success'] == true) {
        final list = data['data'] as List<dynamic>? ?? [];
        return {'success': true, 'data': list, 'total': data['total'] ?? list.length};
      }

      if (res.statusCode == 401) {
        clearSession();
        return {'success': false, 'message': 'Sesión expirada', 'data': <dynamic>[]};
      }

      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Error al cargar clientes',
        'data': <dynamic>[],
      };
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}', 'data': <dynamic>[]};
    }
  }

  /// GET /api/clientes/:codigo - Detalle de un cliente
  Future<Map<String, dynamic>?> getClientePorCodigo(String codigo) async {
    if (_token == null || _token!.isEmpty) return null;

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/clientes/$codigo'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

      if (res.statusCode == 200 && data['success'] == true) {
        return data['data'] as Map<String, dynamic>?;
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
      final res = await http
          .get(Uri.parse('$baseUrl/api/clientes/cartera/$codigo'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

      if (res.statusCode == 200 && data['success'] == true) {
        return data['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
