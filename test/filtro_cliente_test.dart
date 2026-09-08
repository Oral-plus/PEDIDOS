import 'package:flutter_test/flutter_test.dart';

import 'package:skypagos/utils/filtro_cliente.dart';

void main() {
  final clientes = <Map<String, dynamic>>[
    {'id': 'C900123', 'nombre': 'DROGUERÍA LA ECONOMÍA', 'nombreComercial': 'Farmacia Central'},
    {'id': 'C900456', 'nombre': 'SUPERMERCADO EL ÑAME', 'nombreComercial': 'Mercapunto'},
    {'id': 'C777888', 'nombre': 'Tienda Don Jose', 'nombreComercial': ''},
  ];

  List<Map<String, dynamic>> filtrar(String q) =>
      FiltroCliente.aplicar(q, clientes, FiltroCliente.camposCliente);

  group('filtro de clientes', () {
    test('consulta vacia devuelve todos', () {
      expect(filtrar('').length, 3);
      expect(filtrar('   ').length, 3);
    });

    test('busca por codigo', () {
      final res = filtrar('900456');
      expect(res.length, 1);
      expect(res.first['id'], 'C900456');
    });

    test('busca por nombre del cliente ignorando tildes', () {
      final res = filtrar('drogueria');
      expect(res.length, 1);
      expect(res.first['id'], 'C900123');
    });

    test('busca por nombre comercial del negocio', () {
      final res = filtrar('mercapunto');
      expect(res.length, 1);
      expect(res.first['id'], 'C900456');
    });

    test('la enie se normaliza', () {
      expect(filtrar('name').length, 1);
      expect(filtrar('ñame').length, 1);
    });

    test('acepta varios terminos en cualquier orden', () {
      expect(filtrar('central farmacia').length, 1);
      expect(filtrar('jose tienda').length, 1);
    });

    test('sin coincidencias devuelve vacio', () {
      expect(filtrar('ferreteria'), isEmpty);
    });

    test('no revienta con campos nulos', () {
      final sucios = [
        <String, dynamic>{'id': null, 'nombre': null, 'nombreComercial': null},
      ];
      expect(FiltroCliente.aplicar('algo', sucios, FiltroCliente.camposCliente), isEmpty);
      expect(FiltroCliente.aplicar('', sucios, FiltroCliente.camposCliente).length, 1);
    });
  });

  group('filtro de documentos en pagos', () {
    final cliente = clientes.first;
    final docs = <Map<String, dynamic>>[
      {'docEntry': 1, 'docNum': 5001, 'numFactura': 'FE-1001'},
      {'docEntry': 2, 'docNum': 5002, 'numFactura': 'FE-1002'},
    ];

    List<Map<String, dynamic>> filtrarDocs(String q) => FiltroCliente.aplicar(
          q,
          docs,
          (d) => FiltroCliente.camposDocumento(d, cliente: cliente),
        );

    test('busca por numero de factura', () {
      final res = filtrarDocs('1002');
      expect(res.length, 1);
      expect(res.first['numFactura'], 'FE-1002');
    });

    test('el nombre comercial del cliente conserva sus documentos', () {
      expect(filtrarDocs('farmacia central').length, 2);
    });

    test('un termino ajeno no deja documentos', () {
      expect(filtrarDocs('mercapunto'), isEmpty);
    });
  });

  group('nombre comercial', () {
    test('lee los alias del backend', () {
      expect(FiltroCliente.nombreComercial({'nombreComercial': 'Uno'}), 'Uno');
      expect(FiltroCliente.nombreComercial({'cardFName': 'Dos'}), 'Dos');
      expect(FiltroCliente.nombreComercial({'nombre1': 'Tres'}), 'Tres');
      expect(FiltroCliente.nombreComercial(null), '');
      expect(FiltroCliente.nombreComercial({}), '');
    });

    test('para mostrar prefiere el comercial y cae al legal si falta', () {
      expect(
        FiltroCliente.nombreParaMostrar(
            {'nombre': 'GIRALDO GOEZ ERIKA PAOLA', 'nombreComercial': 'DROGUERIA FARMAMOLINOS'}),
        'DROGUERIA FARMAMOLINOS',
      );
      expect(
        FiltroCliente.nombreParaMostrar({'nombre': 'Tienda Don Jose', 'nombreComercial': ''}),
        'Tienda Don Jose',
      );
      expect(FiltroCliente.nombreParaMostrar({'nombre': 'Solo Legal'}), 'Solo Legal');
      expect(FiltroCliente.nombreParaMostrar(null), '');
      expect(FiltroCliente.nombreParaMostrar({}), '');
    });
  });
}
