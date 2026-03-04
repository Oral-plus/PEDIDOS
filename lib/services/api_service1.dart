import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/cart_item.dart';

class ApiService1 {
  // 🔧 CONFIGURACIÓN ACTUALIZADA - URLs que funcionan según el test
  static const List<String> _baseUrls = [
    'https://pedidos.oral-plus.com/api',  // ✅ IP principal que funciona
    'https://pedidos.oral-plus.com/api',   // ✅ IP alternativa que funciona
  ];
  
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Connection': 'keep-alive',
    'Accept-Encoding': 'gzip, deflate',
    'User-Agent': 'Flutter-App/1.0',
  };

  // 🔧 Función para encontrar URL que funciona
  static Future<String?> _findWorkingUrl() async {
    for (String baseUrl in _baseUrls) {
      try {
        print('🧪 Probando conexión con: $baseUrl');
        
        final response = await http.get(
          Uri.parse('$baseUrl/test'),
          headers: _headers,
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            print('✅ Conexión exitosa con: $baseUrl');
            return baseUrl;
          }
        }
      } catch (e) {
        print('❌ Error conectando a $baseUrl: $e');
        continue;
      }
    }
    return null;
  }

  // ✅ FUNCIÓN CORREGIDA: Procesar compra con URL correcta
  static Future<Map<String, dynamic>> processPurchase({
    required List<CartItem> cartItems,
    required String cedula,
    required String nombre,
    required String correo,
    required String telefono,
    String? observaciones,
  }) async {
    try {
      print('💳 === INICIANDO COMPRA (con URL correcta) ===');
      print('📋 Cédula: $cedula');
      print('👤 Nombre: $nombre');
      print('📧 Correo: $correo');
      print('📞 Teléfono: $telefono');
      print('📦 Productos: ${cartItems.length}');

      // ✅ VALIDACIONES BÁSICAS
      if (cedula.trim().isEmpty) throw Exception('La cédula es requerida');
      if (nombre.trim().isEmpty) throw Exception('El nombre es requerido');
      if (correo.trim().isEmpty) throw Exception('El correo es requerido');
      if (cartItems.isEmpty) throw Exception('El carrito está vacío');

      // 🔧 BUSCAR URL QUE FUNCIONE
      print('🔍 Buscando servidor disponible...');
      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        throw Exception('No se puede conectar al servidor. Verifica que esté ejecutándose en el puerto 3006.');
      }
      print('✅ Usando servidor: $workingUrl');

      // ✅ PREPARAR PRODUCTOS EXACTAMENTE COMO JAVASCRIPT
      final productos = <Map<String, dynamic>>[];
      double subtotalCalculado = 0.0;

      for (int i = 0; i < cartItems.length; i++) {
        final item = cartItems[i];
        
        if (item.codigoSap.trim().isEmpty) {
          throw Exception('Producto ${i + 1}: Código SAP vacío');
        }
        if (item.quantity <= 0) {
          throw Exception('Producto ${i + 1}: Cantidad inválida');
        }

        // Limpiar precio exactamente como JavaScript
        String cleanPrice = item.price
            .replaceAll('\$', '')
            .replaceAll(',', '')
            .replaceAll('.', '')
            .replaceAll(' ', '')
            .trim();

        double precio = 0.0;
        try {
          precio = double.parse(cleanPrice);
        } catch (e) {
          // Si falla, calcular desde el total
          precio = item.totalPrice / item.quantity;
        }

        if (precio <= 0) {
          throw Exception('Producto ${i + 1}: Precio inválido');
        }

        // ✅ FORMATO EXACTO COMO JAVASCRIPT - con todos los campos
        productos.add({
          'nombre': item.title.trim(),
          'codigo': item.codigoSap.trim(), // ✅ Campo 'codigo' como en JS
          'textura': item.textura ?? 'Media',
          'precio': precio,
          'cantidad': item.quantity,
          'total': precio * item.quantity,
          'img': item.image,
        });

        subtotalCalculado += precio * item.quantity;
      }

      // ✅ CALCULAR TOTALES EXACTAMENTE COMO JAVASCRIPT
      double total = subtotalCalculado / 1.19; // Sin IVA
      double totalComision = (total * 3) / 100; // 3% comisión
      double totalIva = ((total - totalComision) * 19) / 100; // 19% IVA
      double totalIncluido = total - totalComision + totalIva;

      // ✅ DATOS EXACTOS COMO JAVASCRIPT/PHP
      final requestData = {
        'cedula': cedula.trim(),
        'nombre': nombre.trim(),
        'direccion': '', // Agregar si tienes dirección
        'telefono': telefono.trim(),
        'correo': correo.trim(),
        'subtotal': '\$${totalIncluido.toStringAsFixed(0)}', // Formato con $
        'productos': productos, // ✅ Array completo de productos
        'observaciones': observaciones?.trim() ?? '',
      };

      print('📤 Enviando a API (formato JavaScript/PHP):');
      print(json.encode(requestData));

      // ✅ CREAR CLIENTE HTTP CON CONFIGURACIÓN ESPECÍFICA
      final client = http.Client();
      
      try {
        // ✅ ENVIAR CON CONFIGURACIÓN MEJORADA
        final response = await client.post(
          Uri.parse('$workingUrl/purchase/process'),
          headers: _headers,
          body: json.encode(requestData),
        ).timeout(
          const Duration(seconds: 90), // Timeout más largo para SAP
          onTimeout: () {
            throw TimeoutException('La operación tardó demasiado tiempo', const Duration(seconds: 90));
          },
        );

        print('📡 Respuesta API: ${response.statusCode}');
        print('📄 Headers respuesta: ${response.headers}');
        print('📄 Body respuesta: ${response.body}');

        if (response.statusCode == 200) {
          final responseData = json.decode(utf8.decode(response.bodyBytes));

          if (responseData['success'] == true) {
            print('✅ === COMPRA EXITOSA ===');
            return {
              'success': true,
              'message': responseData['message'] ?? 'Compra procesada exitosamente',
              'docEntry': responseData['DocEntry'],
              'docNum': responseData['DocNum'],
              'total': totalIncluido,
              'emailSent': responseData['emailSent'] ?? false,
            };
          } else {
            throw Exception(responseData['message'] ?? 'Error al procesar la compra');
          }
        } else {
          // Manejar errores HTTP específicos
          String errorMsg = 'Error del servidor: ${response.statusCode}';
          try {
            final errorData = json.decode(utf8.decode(response.bodyBytes));
            errorMsg = errorData['message'] ?? errorMsg;
          } catch (e) {
            // Si no se puede parsear, usar mensaje genérico
            errorMsg += ' - ${response.body}';
          }
          throw Exception(errorMsg);
        }
      } finally {
        client.close();
      }

    } on SocketException catch (e) {
      print('❌ Error de socket: $e');
      throw Exception('Error de red: No se puede conectar al servidor. Verifica tu conexión a internet y que el servidor esté ejecutándose.');
    } on TimeoutException catch (e) {
      print('❌ Error de timeout: $e');
      throw Exception('Timeout: La operación tardó demasiado tiempo. El servidor SAP puede estar ocupado.');
    } on FormatException catch (e) {
      print('❌ Error de formato: $e');
      throw Exception('Error en el formato de datos recibidos del servidor.');
    } catch (e) {
      print('❌ Error en processPurchase: $e');
      
      // Mejorar mensajes de error
      String errorMessage = e.toString();
      if (errorMessage.contains('ClientException') || errorMessage.contains('Failed to fetch')) {
        errorMessage = 'Error de conexión: No se puede conectar al servidor. Verifica que el servidor esté ejecutándose.';
      } else if (errorMessage.contains('Connection refused')) {
        errorMessage = 'Conexión rechazada: El servidor no está disponible en el puerto 3006.';
      } else if (errorMessage.contains('Network is unreachable')) {
        errorMessage = 'Red no disponible: Verifica tu conexión a internet.';
      }
      
      throw Exception(errorMessage);
    }
  }

  // ✅ FUNCIÓN MEJORADA: Validar disponibilidad de productos
  static Future<Map<String, dynamic>> validateProductAvailability(List<CartItem> cartItems) async {
    try {
      print('✅ ApiService1: Validando disponibilidad de ${cartItems.length} productos');

      // Buscar URL que funcione
      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        throw Exception('No se puede conectar al servidor');
      }

      // Preparar datos para validación
      final productos = cartItems.map((item) {
        final cleanPrice = item.price.replaceAll('\$', '').replaceAll(',', '').replaceAll('.', '');
        final precio = double.tryParse(cleanPrice) ?? 0.0;

        return {
          'codigo': item.codigoSap,
          'cantidad': item.quantity,
          'precio': precio,
          'descripcion': item.title,
        };
      }).toList();

      final requestData = {'productos': productos};

      print('📤 Enviando validación a API...');

      final response = await http.post(
        Uri.parse('$workingUrl/purchase/validate'),
        headers: _headers,
        body: json.encode(requestData),
      ).timeout(const Duration(seconds: 15));

      print('📡 Respuesta validación: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));
        print('✅ Validación completada: ${responseData['success']}');
        return responseData;
      } else {
        throw Exception('Error en validación: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ApiService1: Error en validateProductAvailability: $e');
      return {
        'success': false,
        'message': 'Error al validar disponibilidad: $e',
      };
    }
  }

  // 📋 Función para obtener historial de compras
  static Future<List<Map<String, dynamic>>> getPurchaseHistory(String cedula) async {
    try {
      print('📋 ApiService1: Obteniendo historial para cédula: $cedula');

      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        throw Exception('No se puede conectar al servidor');
      }

      final response = await http.get(
        Uri.parse('$workingUrl/invoices/paid/${Uri.encodeComponent(cedula)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      print('📡 ApiService1: Status historial: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));

        if (responseData['success'] == true && responseData['paidInvoices'] is List) {
          final paidInvoices = List<Map<String, dynamic>>.from(responseData['paidInvoices']);

          // Convertir facturas pagadas a formato de historial de compras
          final purchaseHistory = paidInvoices.map((invoice) => {
            'id': invoice['docNum'],
            'fecha': invoice['formattedPaymentDate'],
            'total': invoice['formattedAmount'],
            'estado': 'Pagada',
            'productos': [], // Aquí podrías agregar detalles de productos si los tienes
            'docEntry': invoice['transId'],
            'docNum': invoice['docNum'],
          }).toList();

          print('✅ ApiService1: ${purchaseHistory.length} compras en historial');
          return purchaseHistory;
        }

        return [];
      } else {
        print('❌ ApiService1: Error al obtener historial: ${response.statusCode}');
        throw Exception('Error al obtener historial: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ApiService1: Error en getPurchaseHistory: $e');
      return [];
    }
  }

  // 🧪 Función para probar la conexión con la API (MEJORADA)
  static Future<bool> testConnection() async {
    try {
      print('🧪 ApiService1: Probando conexión con API...');

      final workingUrl = await _findWorkingUrl();
      if (workingUrl != null) {
        print('✅ ApiService1: Conexión exitosa con API');
        return true;
      }

      print('❌ ApiService1: No se pudo conectar a ningún servidor');
      return false;
    } catch (e) {
      print('❌ ApiService1: Error de conexión: $e');
      return false;
    }
  }

  // 📊 Función para obtener estadísticas de facturas
  static Future<Map<String, dynamic>?> getInvoiceStatistics(String cedula) async {
    try {
      print('📊 ApiService1: Obteniendo estadísticas para cédula: $cedula');

      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        throw Exception('No se puede conectar al servidor');
      }

      final response = await http.get(
        Uri.parse('$workingUrl/invoices/by-cardcode/${Uri.encodeComponent(cedula)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));

        if (responseData['success'] == true) {
          print('✅ ApiService1: Estadísticas obtenidas exitosamente');
          return responseData['statistics'];
        }
      }

      return null;
    } catch (e) {
      print('❌ ApiService1: Error obteniendo estadísticas: $e');
      return null;
    }
  }

  // 👤 NUEVA FUNCIÓN: Obtener datos del cliente
  static Future<Map<String, dynamic>> getClientData(String cardCode) async {
    try {
      print('👤 ApiService1: Obteniendo datos para cliente: $cardCode');

      final workingUrl = await _findWorkingUrl();
      if (workingUrl == null) {
        throw Exception('No se puede conectar al servidor');
      }

      final response = await http.get(
        Uri.parse('$workingUrl/client/data/${Uri.encodeComponent(cardCode)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));

        if (responseData is Map) {
          return Map<String, dynamic>.from(responseData);
        }
      }

      throw Exception('Error al obtener datos del cliente: ${response.statusCode}');
    } catch (e) {
      print('❌ ApiService1: Error en getClientData: $e');
      throw Exception('Error al obtener datos del cliente: $e');
    }
  }
}
