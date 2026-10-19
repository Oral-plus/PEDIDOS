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

    group('Abonos parciales: la factura sigue cobrable por lo que falta', () {
      // Factura de 4M en SAP, el gestor ya le abonó 1M que SAP no ha aplicado.
      final parcial = {'saldo': 4000000, 'pendientePorAplicar': 1000000, 'saldoNeto': 3000000};

      test('lo que se le puede cobrar es lo que falta, no el saldo de SAP', () {
        expect(CarteraCliente.disponibleDocumento(parcial), 3000000);
        expect(CarteraCliente.saldoSapDocumento(parcial), 4000000);
        expect(CarteraCliente.abonadoSinAplicar(parcial), 1000000);
      });

      test('el abono del gestor no se pierde de vista', () {
        expect(CarteraCliente.conAbonoPendiente(parcial), true);
        expect(CarteraCliente.cubiertaEnApp(parcial), false,
            reason: 'todavía queda por cobrar: la factura sigue disponible');
      });

      test('una factura ya cubierta en la app queda en cero, pero se sigue viendo', () {
        final cubierta = {'saldo': 4000000, 'pendientePorAplicar': 4000000, 'saldoNeto': 0};
        expect(CarteraCliente.disponibleDocumento(cubierta), 0);
        expect(CarteraCliente.cubiertaEnApp(cubierta), true);
        expect(CarteraCliente.saldoSapDocumento(cubierta), 4000000,
            reason: 'SAP sigue mostrando la deuda hasta que aplique el pago');
      });

      test('nunca se ofrece un disponible negativo', () {
        final pasada = {'saldo': 1000000, 'pendientePorAplicar': 1500000, 'saldoNeto': -500000};
        expect(CarteraCliente.disponibleDocumento(pasada), 0);
      });

      test('sin abonos, lo disponible es el saldo de SAP tal cual', () {
        final limpia = {'saldo': 2500000};
        expect(CarteraCliente.disponibleDocumento(limpia), 2500000);
        expect(CarteraCliente.conAbonoPendiente(limpia), false);
        expect(CarteraCliente.cubiertaEnApp(limpia), false);
      });
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
