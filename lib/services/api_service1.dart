import 'api_client.dart';
import '../models/cart_item.dart';

class ApiService1 {

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

        double precio = item.price;

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
      print('📤 Enviando a API (formato JavaScript/PHP)...');
      
      // ✅ ENVIAR CON ApiClient centralizado
      final responseData = await ApiClient.post(
        '/purchase/process',
        body: requestData,
        timeout: const Duration(seconds: 90), // Timeout más largo para SAP
      );

      print('✅ === COMPRA EXITOSA ===');
      return {
        'success': true,
        'message': responseData['message'] ?? 'Compra procesada exitosamente',
        'docEntry': responseData['DocEntry'],
        'docNum': responseData['DocNum'],
        'total': totalIncluido,
        'emailSent': responseData['emailSent'] ?? false,
      };

    } catch (e) {
      print('❌ Error en processPurchase: $e');
      throw Exception('Error al procesar compra: $e');
    }
  }

  // ✅ FUNCIÓN MEJORADA: Validar disponibilidad de productos
  static Future<Map<String, dynamic>> validateProductAvailability(List<CartItem> cartItems) async {
    try {
      // Preparar datos para validación
      final productos = cartItems.map((item) {
        final precio = item.price;

        return {
          'codigo': item.codigoSap,
          'cantidad': item.quantity,
          'precio': precio,
          'descripcion': item.title,
        };
      }).toList();

      final requestData = {'productos': productos};

      print('📤 Enviando validación a API...');
      final responseData = await ApiClient.post(
        '/purchase/validate',
        body: requestData,
        timeout: const Duration(seconds: 15),
      );

      print('✅ Validación completada: ${responseData['success']}');
      return responseData;
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

      final responseData = await ApiClient.get(
        '/invoices/paid/${Uri.encodeComponent(cedula)}',
        timeout: const Duration(seconds: 10),
      );

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
    } catch (e) {
      print('❌ ApiService1: Error en getPurchaseHistory: $e');
      return [];
    }
  }

  // 🧪 Función para probar la conexión con la API (MEJORADA)
  static Future<bool> testConnection() async {
    try {
      print('🧪 ApiService1: Probando conexión con API...');

      final url = await ApiClient.getWorkingUrl();
      if (url.isNotEmpty) {
        print('✅ ApiService1: Conexión exitosa con API');
        return true;
      }
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

      final responseData = await ApiClient.get(
        '/invoices/by-cardcode/${Uri.encodeComponent(cedula)}',
        timeout: const Duration(seconds: 10),
      );

      if (responseData['success'] == true) {
        print('✅ ApiService1: Estadísticas obtenidas exitosamente');
        return responseData['statistics'];
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

      final responseData = await ApiClient.get(
        '/client/data/${Uri.encodeComponent(cardCode)}',
        timeout: const Duration(seconds: 10),
      );

      if (responseData is Map) {
        return Map<String, dynamic>.from(responseData);
      }

      throw Exception('Error al obtener datos del cliente');
    } catch (e) {
      print('❌ ApiService1: Error en getClientData: $e');
      throw Exception('Error al obtener datos del cliente: $e');
    }
  }
}
