import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cart_item.dart';

/// Servicio para guardar pedidos en base de datos (en lugar de SAP)
class OrderDbService {
  OrderDbService._();
  static final OrderDbService _instance = OrderDbService._();
  factory OrderDbService() => _instance;

  static const List<String> _baseUrls = [
    'http://localhost:3000',
    'http://10.0.2.2:3000',
    'http://192.168.2.244:3000',
  ];

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static String? _workingUrl;

  static Future<String?> _findWorkingUrl() async {
    if (_workingUrl != null) return _workingUrl;
    for (final baseUrl in _baseUrls) {
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/api/test'), headers: _headers)
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
          if (data['success'] == true) {
            _workingUrl = baseUrl;
            return baseUrl;
          }
        }
      } catch (_) {
        continue;
      }
    }
    // Si no se pudo probar, usar la primera URL por defecto
    _workingUrl = _baseUrls.first;
    return _workingUrl;
  }

  /// Guardar pedido en base de datos Pedidos (BD independiente)
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
      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        return {
          'success': false,
          'message': 'No se puede conectar al servidor. Verifica que la API esté ejecutándose.',
        };
      }

      final productos = <Map<String, dynamic>>[];
      for (final item in cartItems) {
        if (item.codigoSap.isEmpty || item.quantity <= 0) continue;
        productos.add({
          'codigo': item.codigoSap,
          'nombre': item.title,
          'textura': item.textura ?? 'Media',
          'precio': item.numericPrice,
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

      final res = await http
          .post(
            Uri.parse('$workingUrl/api/orders'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};

      if (res.statusCode == 200 && data['success'] == true) {
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

  /// Obtener pedidos de un cliente desde BD Pedidos
  static Future<Map<String, dynamic>> getOrdersByClient(String codigoCliente, {String? estado, int page = 1}) async {
    try {
      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        return {'success': false, 'message': 'No se puede conectar al servidor.'};
      }

      String url = '$workingUrl/api/orders/$codigoCliente?page=$page';
      if (estado != null && estado.isNotEmpty) url += '&estado=$estado';

      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Obtener detalle de un pedido específico desde BD Pedidos
  static Future<Map<String, dynamic>> getOrderDetail(String numeroPedido) async {
    try {
      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        return {'success': false, 'message': 'No se puede conectar al servidor.'};
      }

      final res = await http
          .get(Uri.parse('$workingUrl/api/orders/detail/$numeroPedido'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
