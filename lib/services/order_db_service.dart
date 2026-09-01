import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cart_item.dart';
import 'api_easy_service.dart';
import 'cache_service.dart';
import 'shared_http.dart';

class OrderDbService {
  OrderDbService._();
  static final OrderDbService _instance = OrderDbService._();
  factory OrderDbService() => _instance;

  static Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = ApiEasyService().token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static Future<String> _baseUrl() => ApiEasyService().baseUrl();

  static Map<String, dynamic> _leerJson(http.Response res) {
    final tipo = res.headers['content-type'] ?? '';
    if (tipo.contains('application/json')) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  static String _mensajeError(http.Response res, Map<String, dynamic> data, String porDefecto) {
    final msg = data['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    if (res.statusCode == 401) return 'Sesión inválida o expirada. Inicia sesión nuevamente.';
    return '$porDefecto (${res.statusCode})';
  }

  static Future<Map<String, dynamic>> saveOrder({
    required List<CartItem> cartItems,
    required String cedula,
    required String nombre,
    required String correo,
    required String telefono,
    String? direccion,
    String? observaciones,
    String? codigoCliente,
    String? vendedor,
    String? ciudad,
  }) async {
    try {
      final workingUrl = await _baseUrl();

      final productos = <Map<String, dynamic>>[];
      for (final item in cartItems) {
        if (item.codigoSap.isEmpty || item.quantity <= 0) continue;
        productos.add({
          'codigo': item.codigoSap,
          'nombre': item.title,
          'textura': item.textura ?? 'Media',
          'precio': item.price,
          'cantidad': item.quantity,
          'total': item.totalPrice,
        });
      }

      if (productos.isEmpty) {
        return {'success': false, 'message': 'No hay productos válidos en el carrito.'};
      }

      final subtotal = productos.fold<double>(0, (s, p) => s + ((p['total'] as num?)?.toDouble() ?? 0));

      final body = {
        'cedula': cedula.trim(),
        'nombre': nombre.trim(),
        'correo': correo.trim(),
        'telefono': telefono.trim(),
        'direccion': (direccion ?? '').trim().isEmpty ? null : direccion!.trim(),
        'subtotal': subtotal,
        'productos': productos,
        'observaciones': (observaciones ?? '').trim().isEmpty ? null : observaciones!.trim(),
        'codigoCliente': (codigoCliente ?? cedula).trim(),
        'vendedor': vendedor?.trim(),
        'ciudad': ciudad?.trim(),
      };

      final res = await SharedHttp.client
          .post(
            Uri.parse('$workingUrl/api/orders'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final data = _leerJson(res);

      if (res.statusCode == 200 && data['success'] == true) {
        CacheService().invalidarPrefijo('pedidos:');
        return {
          'success': true,
          'message': data['message'] ?? 'Pedido registrado correctamente',
          'docEntry': data['docEntry'],
          'docNum': data['docNum'],
          'emailSent': data['emailSent'] ?? false,
        };
      }

      return {
        'success': false,
        'message': _mensajeError(res, data, 'Error al registrar el pedido'),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> getOrdersByClient(String codigoCliente, {String? estado, int page = 1}) async {
    try {
      final workingUrl = await _baseUrl();

      String url = '$workingUrl/api/orders/$codigoCliente?page=$page';
      if (estado != null && estado.isNotEmpty) url += '&estado=$estado';

      final res = await SharedHttp.client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = _leerJson(res);
      if (data.isEmpty) {
        return {'success': false, 'message': _mensajeError(res, data, 'Error al consultar pedidos')};
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> getOrderDetail(String numeroPedido) async {
    try {
      final workingUrl = await _baseUrl();

      final res = await SharedHttp.client
          .get(Uri.parse('$workingUrl/api/orders/detail/$numeroPedido'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = _leerJson(res);
      if (data.isEmpty) {
        return {'success': false, 'message': _mensajeError(res, data, 'Error al consultar el pedido')};
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
