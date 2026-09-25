import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/utils/cartera_cliente.dart';

void main() {
  group('CarteraCliente', () {
    test('muestra el saldo ya descontado cuando el servidor lo envía', () {
      final cartera = {'balance': 4000000, 'balanceNeto': 3000000, 'pendientePorAplicar': 1000000};
      expect(CarteraCliente.neta(cartera), 3000000);
      expect(CarteraCliente.sap(cartera), 4000000);
      expect(CarteraCliente.pendientePorAplicar(cartera), 1000000);
      expect(CarteraCliente.tienePendientes(cartera), true);
    });

    test('con un backend viejo, sin campos nuevos, usa el saldo de SAP', () {
      final cartera = {'balance': 4000000};
      expect(CarteraCliente.neta(cartera), 4000000);
      expect(CarteraCliente.pendientePorAplicar(cartera), 0);
      expect(CarteraCliente.tienePendientes(cartera), false);
    });

    test('si solo llega el pendiente, lo resta sin bajar de cero', () {
      expect(CarteraCliente.neta({'balance': 500000, 'pendientePorAplicar': 200000}), 300000);
      expect(CarteraCliente.neta({'balance': 100000, 'pendientePorAplicar': 900000}), 0);
    });

    test('acepta números en texto y cartera nula', () {
      expect(CarteraCliente.neta({'balance': '250000.50'}), 250000.5);
      expect(CarteraCliente.neta(null), 0);
      expect(CarteraCliente.sap({'balance': null}), 0);
    });

    test('saldo de la factura: usa el neto y cae al de SAP si no viene', () {
      expect(CarteraCliente.saldoNetoDocumento({'saldo': 900000, 'saldoNeto': 400000}), 400000);
      expect(CarteraCliente.saldoNetoDocumento({'saldo': 900000}), 900000);
      expect(CarteraCliente.saldoNetoDocumento(null), 0);
    });

    test('lista los recaudos pendientes y tolera una respuesta sin ellos', () {
      final cartera = {
        'recaudosPendientes': [
          {'numeroRecaudo': 'REC-1', 'pendiente': 1000000, 'demorado': false},
        ],
      };
      expect(CarteraCliente.recaudosPendientes(cartera).length, 1);
      expect(CarteraCliente.recaudosPendientes(cartera).first['numeroRecaudo'], 'REC-1');
      expect(CarteraCliente.recaudosPendientes({'recaudosPendientes': null}), isEmpty);
      expect(CarteraCliente.recaudosPendientes(null), isEmpty);
    });
  });
}
