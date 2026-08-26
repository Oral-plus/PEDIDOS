import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'shared_http.dart';

class ApiClient {
  static const List<String> _baseUrls = [
    'https://pedidos.oral-plus.com/api',
  ];

  static const Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Connection': 'keep-alive',
    'Accept-Encoding': 'gzip',
    'User-Agent': 'Flutter-App/1.0',
  };

  /// Se llama cuando un host no responde (sin red o timeout), para que quien
  /// tenga cacheada esa URL base la descarte.
  static void Function(String baseUrl)? onConnectionError;

  static http.Client get _http => SharedHttp.client;

  /// Devuelve la primera URL base que responda; lanza excepción si ninguna sirve.
  static Future<String> getWorkingUrl() async {
    for (String baseUrl in _baseUrls) {
      try {
        final response = await _http.get(
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

  /// GET con resolución de URL, timeout y manejo de errores.
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
      final response = await _http.get(uri, headers: finalHeaders).timeout(timeout);
      return await _processResponse(response);
    } on SocketException {
      onConnectionError?.call(baseURL);
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      onConnectionError?.call(baseURL);
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  /// POST
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
      final response = await _http.post(
        uri,
        headers: finalHeaders,
        body: json.encode(body),
      ).timeout(timeout);
      return await _processResponse(response);
    } on SocketException {
      onConnectionError?.call(baseURL);
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      onConnectionError?.call(baseURL);
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  /// PUT
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
      final response = await _http.put(
        uri,
        headers: finalHeaders,
        body: json.encode(body),
      ).timeout(timeout);
      return await _processResponse(response);
    } on SocketException {
      onConnectionError?.call(baseURL);
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      onConnectionError?.call(baseURL);
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  /// DELETE
  static Future<dynamic> delete(String endpoint, {
    String? customBaseUrl,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final baseURL = customBaseUrl ?? await getWorkingUrl();
    final uri = Uri.parse('$baseURL$endpoint');
    final finalHeaders = Map<String, String>.from(_defaultHeaders);
    if (headers != null) finalHeaders.addAll(headers);

    try {
      final response = await _http.delete(uri, headers: finalHeaders).timeout(timeout);
      return await _processResponse(response);
    } on SocketException {
      onConnectionError?.call(baseURL);
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet.');
    } on TimeoutException {
      onConnectionError?.call(baseURL);
      throw Exception('Timeout: La operación tardó demasiado tiempo.');
    } catch (e) {
      throw Exception('Error en la petición: $e');
    }
  }

  // Por encima de este tamaño (la lista de clientes, por ejemplo) el JSON se
  // decodifica en otro isolate para no congelar la interfaz.
  static const int _umbralIsolate = 64 * 1024;

  static dynamic _decodificar(Uint8List bytes) => json.decode(utf8.decode(bytes));

  static Future<dynamic> _processResponse(http.Response response) async {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw Exception('Respuesta vacía del servidor');
    }

    dynamic parsed;
    try {
      parsed = bytes.length > _umbralIsolate
          ? await compute(_decodificar, bytes)
          : _decodificar(bytes);
    } on FormatException {
      throw Exception('Error en el formato de datos recibidos del servidor. (${response.statusCode})');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return parsed;
    }
    String errorMsg = parsed['message']?.toString() ??
        parsed['error']?.toString() ??
        'Error del servidor: ${response.statusCode}';
    throw Exception(errorMsg);
  }
}
