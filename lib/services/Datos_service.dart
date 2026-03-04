import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class InvoiceService1 {
  // URLs del servidor local (donde está corriendo tu server.js)
  static const List<String> possibleUrls = [
    'https://pedidos.oral-plus.com/api',
    'https://pedidos.oral-plus.com/api', // IP del servidor si es diferente
    'https://pedidos.oral-plus.com/api',
  ];

  static String? _workingUrl;
  static const Duration timeout = Duration(seconds: 30); // Aumentado para compras

  static bool _isSuccessResponse(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    if (value is int) return value == 1;
    return false;
  }

  /// Encuentra la URL que funciona
  static Future<String?> findWorkingUrl() async {
    if (_workingUrl != null) {
      print('🔄 Usando URL en cache: $_workingUrl');
      return _workingUrl;
    }

    print('🔍 Buscando servidor ORAL-PLUS...');
    print('📡 Probando ${possibleUrls.length} URLs posibles...');

    for (int i = 0; i < possibleUrls.length; i++) {
      final url = possibleUrls[i];
      try {
        print('🔄 [${i + 1}/${possibleUrls.length}] Probando: $url');
        final response = await http.get(
          Uri.parse('$url/test'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (_isSuccessResponse(data['success'])) {
            _workingUrl = url;
            print('✅ Servidor encontrado en: $url');
            return url;
          }
        }
      } catch (e) {
        print('❌ Error en $url: $e');
        continue;
      }
    }

    print('❌ No se pudo encontrar el servidor en ninguna URL');
    return null;
  }

  /// Prueba la conexión básica
  static Future<bool> testConnection() async {
    try {
      final workingUrl = await findWorkingUrl();
      return workingUrl != null;
    } catch (e) {
      print('❌ Error en test de conexión: $e');
      return false;
    }
  }

  /// 👤 MÉTODO PRINCIPAL - OBTENER DATOS DEL CLIENTE (CONECTA A SAP COMO SOCIO DE NEGOCIOS)
  /// Busca en SAP Business One exactamente como tu PHP
  static Future<Map<String, dynamic>?> getClientData(String cardCode) async {
    if (cardCode.isEmpty) {
      throw Exception('CardCode no puede estar vacío');
    }

    print('👤 === CONSULTANDO SOCIO DE NEGOCIOS EN SAP ===');
    print('📋 CardCode: $cardCode');
    print('🔍 Conectando a SAP Business One...');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      print('🌐 URL: $workingUrl/client/data/$cardCode');
      print('🔍 Consultando Socio de Negocio (todos los clientes)...');

      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse('$workingUrl/client/data/$cardCode'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      final responseTime = DateTime.now().difference(startTime).inMilliseconds;
      print('📡 Respuesta SAP: ${response.statusCode} (${responseTime}ms)');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('📄 Respuesta cruda de SAP: $responseBody');

        try {
          final data = json.decode(responseBody);
          print('📋 Datos decodificados: $data');
          print('📋 Tipo de datos: ${data.runtimeType}');

          // Caso 1: SAP no encontró datos (retorna array)
          if (data is List) {
            print('📭 SAP retornó lista (Socio de Negocios no encontrado o filtrado)');
            if (data.isNotEmpty) {
              final message = data[0].toString();
              print('💬 Mensaje de SAP: $message');
              if (message.contains('No se encontraron datos')) {
                print('❌ Socio de Negocios no encontrado en SAP o no cumple filtros');
                return null;
              }
            }
            return null;
          }

          // Caso 2: SAP encontró el Socio de Negocios (retorna objeto)
          if (data is Map<String, dynamic>) {
            print('✅ SAP retornó Map (Socio de Negocios encontrado)');
            // Verificar que tenga los campos de Socio de Negocios
            if (data.containsKey('CardName')) {
              print('✅ SOCIO DE NEGOCIOS ENCONTRADO EN SAP:');
              print('   👤 Nombre: ${data['CardName']}');
              print('   📍 Dirección: ${data['Address'] ?? 'N/A'}');
              print('   📞 Teléfono: ${data['Phone1'] ?? 'N/A'}');
              print('   📧 Email: ${data['E_Mail'] ?? 'N/A'}');
              print('   ⏱️ Tiempo consulta SAP: ${responseTime}ms');

              return {
                'cardCode': cardCode,
                'cardName': data['CardName'] ?? '',
                'address': data['Address'] ?? '',
                'phone': data['Phone1'] ?? '',
                'email': data['E_Mail'] ?? '',
                'queryTime': responseTime,
                'timestamp': DateTime.now().toIso8601String(),
                'success': true,
                'source': 'SAP Business One',
                // Datos raw exactos de SAP
                'rawData': {
                  'CardName': data['CardName'],
                  'Address': data['Address'],
                  'Phone1': data['Phone1'],
                  'E_Mail': data['E_Mail'],
                },
              };
            } else {
              print('⚠️ Respuesta de SAP no contiene CardName: ${data.keys.toList()}');
              print('📄 Contenido completo: $data');
              return null;
            }
          }

          // Caso 3: Respuesta inesperada de SAP
          print('⚠️ Respuesta inesperada de SAP Business One');
          print('📄 Tipo: ${data.runtimeType}');
          print('📄 Contenido: $data');
          return null;
        } catch (jsonError) {
          print('❌ Error decodificando respuesta de SAP: $jsonError');
          print('📄 Respuesta cruda: $responseBody');
          throw Exception('Error procesando respuesta de SAP: $jsonError');
        }
      } else if (response.statusCode == 404) {
        print('📭 Socio de Negocios no encontrado en SAP');
        print('💡 Posibles razones:');
        print('   • CardCode no existe en SAP');
        print('   • Socio pertenece a "Droguerias Cadenas"');
        print('   • Socio pertenece a "Canal Grandes Superf"');
        print('   • Canal es "HARD DISCOUNT NACIONALES"');
        print('   • Canal es "HARD DISCOUNT INDEPENDIENTES"');

        try {
          final errorData = json.decode(response.body);
          print('📄 Detalle SAP: ${errorData['error'] ?? response.body}');
        } catch (e) {
          print('📄 Respuesta SAP: ${response.body}');
        }

        return null;
      } else {
        print('❌ Error conectando a SAP ${response.statusCode}');
        print('📄 Respuesta: ${response.body}');
        throw Exception('Error SAP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error consultando Socio de Negocios en SAP: $e');

      if (e is SocketException) {
        throw Exception('Error de conexión: SAP Business One no está disponible');
      } else if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout: La consulta a SAP tardó demasiado tiempo');
      } else {
        rethrow;
      }
    }
  }

  /// 🛒 NUEVO MÉTODO: Procesar compra en SAP (equivalente a tu PHP)
  static Future<Map<String, dynamic>> processPurchase({
    required List<dynamic> cartItems,
    required String cedula,
    String? observaciones,
  }) async {
    if (cedula.isEmpty) {
      throw Exception('Cédula no puede estar vacía');
    }

    if (cartItems.isEmpty) {
      throw Exception('El carrito no puede estar vacío');
    }

    print('🛒 === PROCESANDO COMPRA EN SAP ===');
    print('📋 Cédula: $cedula');
    print('📦 Productos: ${cartItems.length}');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      // Preparar datos para SAP
      final productos = cartItems.map((item) {
        return {
          'codigo': item.codigoSap ?? item.id,
          'cantidad': item.quantity.toString(),
          'precio': item.price.replaceAll('\$', '').replaceAll(',', ''),
        };
      }).toList();

      // Calcular subtotal
      double subtotal = 0;
      for (var item in cartItems) {
        final price = double.tryParse(item.price.replaceAll('\$', '').replaceAll(',', '')) ?? 0;
        subtotal += price * item.quantity;
      }

      // Obtener datos del cliente para el correo
      final clientData = await getClientData(cedula);
      final correo = clientData?['email'] ?? '';
      final nombre = clientData?['cardName'] ?? '';

      final purchaseData = {
        'cedula': cedula,
        'productos': productos,
        'correo': correo,
        'nombre': nombre,
        'subtotal': subtotal.toStringAsFixed(0),
        'observaciones': observaciones ?? '',
      };

      print('📤 Enviando datos a SAP...');
      print('📄 Datos: ${json.encode(purchaseData)}');

      final startTime = DateTime.now();
      final response = await http.post(
        Uri.parse('$workingUrl/purchase/process'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(purchaseData),
      ).timeout(timeout);

      final responseTime = DateTime.now().difference(startTime).inMilliseconds;
      print('📡 Respuesta SAP: ${response.statusCode} (${responseTime}ms)');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('📄 Respuesta cruda de SAP: $responseBody');

        try {
          final data = json.decode(responseBody);
          print('✅ COMPRA PROCESADA EN SAP:');
          print('   📄 DocEntry: ${data['DocEntry']}');
          print('   📄 DocNum: ${data['DocNum']}');
          print('   📧 Correo enviado: ${data['emailSent']}');
          print('   ⏱️ Tiempo procesamiento: ${responseTime}ms');

          return {
            'success': true,
            'message': data['message'] ?? 'Compra procesada exitosamente en SAP',
            'docEntry': data['DocEntry'],
            'docNum': data['DocNum'],
            'emailSent': data['emailSent'] ?? false,
            'processingTime': responseTime,
            'timestamp': DateTime.now().toIso8601String(),
            'subtotal': subtotal,
            'cedula': cedula,
            'productos': productos.length,
          };
        } catch (jsonError) {
          print('❌ Error decodificando respuesta de compra: $jsonError');
          print('📄 Respuesta cruda: $responseBody');
          throw Exception('Error procesando respuesta de compra: $jsonError');
        }
      } else {
        print('❌ Error procesando compra: ${response.statusCode}');
        print('📄 Respuesta: ${response.body}');

        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Error procesando compra en SAP');
        } catch (e) {
          throw Exception('Error SAP ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      print('❌ Error procesando compra en SAP: $e');

      if (e is SocketException) {
        throw Exception('Error de conexión: SAP Business One no está disponible');
      } else if (e.toString().contains('TimeoutException')) {
        throw Exception('Timeout: El procesamiento en SAP tardó demasiado tiempo');
      } else {
        rethrow;
      }
    }
  }

  /// 🧪 MÉTODO: Validar disponibilidad de productos
  static Future<Map<String, dynamic>> validateProductAvailability(List<dynamic> cartItems) async {
    if (cartItems.isEmpty) {
      return {
        'success': false,
        'message': 'Lista de productos vacía'
      };
    }

    print('🧪 === VALIDANDO DISPONIBILIDAD DE PRODUCTOS ===');
    print('📦 Productos a validar: ${cartItems.length}');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      final productos = cartItems.map((item) {
        return {
          'codigo': item.codigoSap ?? item.id,
          'cantidad': item.quantity,
        };
      }).toList();

      final validationData = {
        'productos': productos,
      };

      print('📤 Validando en SAP...');

      final startTime = DateTime.now();
      final response = await http.post(
        Uri.parse('$workingUrl/purchase/validate'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(validationData),
      ).timeout(timeout);

      final responseTime = DateTime.now().difference(startTime).inMilliseconds;
      print('📡 Respuesta validación: ${response.statusCode} (${responseTime}ms)');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Validación completada:');
        print('   🎯 Todos disponibles: ${data['success']}');
        print('   📦 Productos validados: ${data['products']?.length ?? 0}');

        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Validación completada',
          'products': data['products'] ?? [],
          'validationTime': responseTime,
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else {
        print('❌ Error en validación: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Error validando productos en SAP'
        };
      }
    } catch (e) {
      print('❌ Error validando productos: $e');
      return {
        'success': false,
        'message': 'Error de conexión validando productos'
      };
    }
  }

  /// 🔍 MÉTODO DEBUG - Verificar por qué un CardCode no pasa los filtros
  static Future<Map<String, dynamic>?> debugClientData(String cardCode) async {
    if (cardCode.isEmpty) {
      throw Exception('CardCode no puede estar vacío');
    }

    print('🔍 === DEBUG SOCIO DE NEGOCIOS EN SAP ===');
    print('📋 CardCode: $cardCode');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      final response = await http.get(
        Uri.parse('$workingUrl/client/debug/$cardCode'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('🔍 DEBUG INFO de SAP:');
        print('   📋 Existe: ${data['exists']}');
        if (data['exists'] == true) {
          print('   👤 Nombre: ${data['client']?['CardName']}');
          print('   📊 Grupo: ${data['group']?['GroupName']}');
          print('   🏪 Canal: ${data['canal']?['Name']}');
          print('   ✅ Pasa filtro grupo: ${data['filters']?['passesGroupFilter']}');
          print('   ✅ Pasa filtro canal: ${data['filters']?['passesCanalFilter']}');
        }
        return data;
      } else {
        print('❌ Error en debug: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error en debug: $e');
      return null;
    }
  }

  /// Método de compatibilidad (mantener para no romper código existente)
  static Future<Map<String, dynamic>?> getClientDataWithFilters(String cardCode) async {
    return await getClientData(cardCode);
  }


  /// 💰 OBTENER FACTURAS PAGADAS - Usa el endpoint correcto de tu servidor
  static Future<Map<String, dynamic>> getPaidInvoicesByCardCode(String cardCode) async {
    if (cardCode.isEmpty) {
      throw Exception('CardCode no puede estar vacío');
    }

    print('💰 === CONSULTANDO FACTURAS PAGADAS EN SAP ===');
    print('📋 CardCode solicitado: $cardCode');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      print('🌐 URL: $workingUrl/invoices/paid/$cardCode');

      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse('$workingUrl/invoices/paid/$cardCode'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      final responseTime = DateTime.now().difference(startTime).inMilliseconds;
      print('📡 Respuesta SAP: ${response.statusCode} (${responseTime}ms)');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('📄 Respuesta cruda de SAP: ${responseBody.length > 200 ? "${responseBody.substring(0, 200)}..." : responseBody}');

        try {
          final data = json.decode(responseBody);

          // El servidor retorna directamente un array de facturas pagadas
          if (data is List) {
            print('✅ Facturas pagadas encontradas en SAP: ${data.length}');

            // Calcular estadísticas
            double totalPaidAmount = 0;
            int thisMonthPaid = 0;
            final currentMonth = DateTime.now().month;
            final currentYear = DateTime.now().year;

            for (var invoice in data) {
              // Sumar total pagado
              final amount = double.tryParse(invoice['DocTotal']?.toString().replaceAll(',', '') ?? '0') ?? 0.0;
              totalPaidAmount += amount;

              // Contar facturas del mes actual
              try {
                final docDate = DateTime.tryParse(invoice['DocDate'] ?? '');
                if (docDate != null && docDate.month == currentMonth && docDate.year == currentYear) {
                  thisMonthPaid++;
                }
              } catch (e) {
                // Ignorar errores de fecha
              }
            }

            return {
              'success': true,
              'count': data.length,
              'paidInvoices': data,
              'queryTime': responseTime,
              'timestamp': DateTime.now().toIso8601String(),
              'statistics': {
                'totalPaidAmount': totalPaidAmount,
                'thisMonthPaid': thisMonthPaid,
              },
              'message': data.isEmpty
                  ? 'No hay facturas pagadas en SAP'
                  : 'Facturas pagadas obtenidas exitosamente',
            };
          } else {
            print('⚠️ Respuesta inesperada de SAP - esperaba List, recibió: ${data.runtimeType}');
            return {
              'success': true,
              'count': 0,
              'paidInvoices': [],
              'message': 'No hay facturas pagadas en SAP',
            };
          }
        } catch (jsonError) {
          print('❌ Error decodificando respuesta de facturas pagadas: $jsonError');
          throw Exception('Error procesando respuesta de facturas pagadas: $jsonError');
        }
      } else if (response.statusCode == 404) {
        print('📭 No se encontraron facturas pagadas en SAP');
        return {
          'success': true,
          'count': 0,
          'paidInvoices': [],
          'message': 'No hay facturas pagadas en SAP',
        };
      } else {
        print('❌ Error obteniendo facturas pagadas: ${response.statusCode}');
        throw Exception('Error SAP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error obteniendo facturas pagadas de SAP: $e');
      rethrow;
    }
  }

  /// 📊 OBTENER TODAS LAS FACTURAS - Usa el endpoint correcto de tu servidor
  static Future<Map<String, dynamic>?> getAllInvoicesByCardCode(String cardCode) async {
    if (cardCode.isEmpty) {
      throw Exception('CardCode no puede estar vacío');
    }

    print('📊 === CONSULTANDO TODAS LAS FACTURAS EN SAP ===');
    print('📋 CardCode solicitado: $cardCode');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      print('🌐 URL: $workingUrl/invoices/all/$cardCode');

      final response = await http.get(
        Uri.parse('$workingUrl/invoices/all/$cardCode'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List) {
          print('✅ Todas las facturas encontradas en SAP: ${data.length}');

          // Separar facturas por estado
          final pendientes = data.where((invoice) => invoice['Estado'] == 'Pendiente').toList();
          final pagadas = data.where((invoice) => invoice['Estado'] == 'Pagada').toList();

          return {
            'success': true,
            'total': data.length,
            'pending': pendientes.length,
            'paid': pagadas.length,
            'allInvoices': data,
            'pendingInvoices': pendientes,
            'paidInvoices': pagadas,
            'timestamp': DateTime.now().toIso8601String(),
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo todas las facturas de SAP: $e');
      return null;
    }
  }

  /// 🔍 BÚSQUEDA AVANZADA DE CLIENTES
  static Future<List<Map<String, dynamic>>> searchClients(String searchTerm) async {
    if (searchTerm.isEmpty) {
      throw Exception('Término de búsqueda no puede estar vacío');
    }

    print('🔍 === BÚSQUEDA AVANZADA DE CLIENTES EN SAP ===');
    print('📋 Término: $searchTerm');

    final workingUrl = await findWorkingUrl();
    if (workingUrl == null) {
      throw Exception('No se pudo conectar con el servidor SAP');
    }

    try {
      final response = await http.get(
        Uri.parse('$workingUrl/search/clients?term=${Uri.encodeComponent(searchTerm)}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List) {
          print('✅ Clientes encontrados en SAP: ${data.length}');
          return List<Map<String, dynamic>>.from(data);
        }
      }

      return [];
    } catch (e) {
      print('❌ Error en búsqueda de clientes: $e');
      return [];
    }
  }


  /// Obtiene estadísticas de un CardCode
  static Future<Map<String, dynamic>?> getCardCodeStatistics(String cardCode) async {
    try {
      // Obtener todas las facturas para calcular estadísticas
      final allInvoices = await getAllInvoicesByCardCode(cardCode);

      if (allInvoices != null) {
        return {
          'count': allInvoices['pending'] ?? 0,
          'totalAmount': 0.0, // Se calculará desde las facturas
          'overdueCount': 0,
          'urgentCount': 0,
          'upcomingCount': 0,
          'normalCount': allInvoices['pending'] ?? 0,
          'cardCode': cardCode,
          'timestamp': DateTime.now().toIso8601String(),
          'queryTime': 0,
        };
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo estadísticas de SAP: $e');
      return null;
    }
  }

  /// Método de conveniencia para obtener datos completos del cliente
  static Future<Map<String, dynamic>?> getCompleteClientInfo(String cardCode) async {
    try {
      print('🔄 Obteniendo información completa del Socio de Negocios...');
      // Obtener datos del cliente y estadísticas en paralelo
      final futures = await Future.wait([
        getClientData(cardCode), // Usar el método principal
        getCardCodeStatistics(cardCode),
      ]);

      final clientData = futures[0];
      final statistics = futures[1];

      if (clientData != null) {
        // Combinar datos del cliente con estadísticas
        final completeInfo = Map<String, dynamic>.from(clientData);
        if (statistics != null) {
          completeInfo['statistics'] = statistics;
        }
        print('✅ Información completa obtenida de SAP');
        return completeInfo;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo información completa de SAP: $e');
      return null;
    }
  }

  /// Método para limpiar la URL en cache
  static void resetConnection() {
    _workingUrl = null;
    print('🔄 Cache de conexión SAP limpiado');
  }
}
