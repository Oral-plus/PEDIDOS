import 'dart:convert';
import '../models/cart_item.dart';
import 'api_easy_service.dart';
import 'cache_service.dart';
import 'shared_http.dart';

class OrderDbService {
  OrderDbService._();
  static final OrderDbService _instance = OrderDbService._();
  factory OrderDbService() => _instance;

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<String> _baseUrl() => ApiEasyService().baseUrl();

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

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

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
        'message': data['message']?.toString() ?? 'Error al registrar el pedido',
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

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
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

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
