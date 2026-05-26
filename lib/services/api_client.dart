import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  static const List<String> _baseUrls = [
    'https://pedidos.oral-plus.com/api',
    'https://pedidos.oral-plus.com/api', // Same for now from api_service1, but could be different IPs
  ];

  static const Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Connection': 'keep-alive',
    'Accept-Encoding': 'gzip, deflate',
    'User-Agent': 'Flutter-App/1.0',
  };

  /// Finds and returns the first working base URL from the predefined list.
  /// Throws an exception if none are working.
  static Future<String> getWorkingUrl() async {
    for (String baseUrl in _baseUrls) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/test'),
          headers: _defaultHeaders,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            return baseUrl;
          }
        }
      } catch (_) {
        continue;
      }
    }
    throw Exception('No se puede conectar al servidor. Verifica que esté en línea.');
  }

  /// Centralized GET request that handles finding the URL, parsing errors, timeouts, etc.
  static Future<dynamic> get(String endpoint, {
    String? customBaseUrl, 
    Map<String, String>? headers, 
    Duration timeout = const Duration(seconds: 15)
  }) async {
    final baseURL = customBaseUrl ?? await getWorkingUrl();
    final uri = Uri.parse('$baseURL$endpoint');
    final finalHeaders = Map<String, String>.from(_defaultHeaders);
    if (headers != null) finalHeaders.addAll(headers);

    try {
      final response = await http.get(uri, headers: finalHeaders).timeout(timeout);
      return _processResponse(response);
    } on SocketException {
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  /// Centralized POST request
  static Future<dynamic> post(String endpoint, {
    required Map<String, dynamic> body,
    String? customBaseUrl,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20)
  }) async {
    final baseURL = customBaseUrl ?? await getWorkingUrl();
    final uri = Uri.parse('$baseURL$endpoint');
    final finalHeaders = Map<String, String>.from(_defaultHeaders);
    if (headers != null) finalHeaders.addAll(headers);

    try {
      final response = await http.post(
        uri,
        headers: finalHeaders,
        body: json.encode(body),
      ).timeout(timeout);
      return _processResponse(response);
    } on SocketException {
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  /// Centralized PUT request
  static Future<dynamic> put(String endpoint, {
    required Map<String, dynamic> body,
    String? customBaseUrl,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final baseURL = customBaseUrl ?? await getWorkingUrl();
    final uri = Uri.parse('$baseURL$endpoint');
    final finalHeaders = Map<String, String>.from(_defaultHeaders);
    if (headers != null) finalHeaders.addAll(headers);

    try {
      final response = await http.put(
        uri,
        headers: finalHeaders,
        body: json.encode(body),
      ).timeout(timeout);
      return _processResponse(response);
    } on SocketException {
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  static dynamic _processResponse(http.Response response) {
    if (response.body.isEmpty) {
      throw Exception('Respuesta vacía del servidor');
    }

    try {
      final parsed = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return parsed;
      } else {
        String errorMsg = parsed['message'] ?? 'Error del servidor: ${response.statusCode}';
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Error en el formato de datos recibidos del servidor. (${response.statusCode})');
      } else {
        rethrow;
      }
    }
  }
}
