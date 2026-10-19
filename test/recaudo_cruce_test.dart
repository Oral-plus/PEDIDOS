import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/utils/recaudo_cruce.dart';

void main() {
  group('RecaudoCruce: no se aplica más plata de la que entró', () {
    // El caso real que destapó el problema: una factura de 498.828 a la que el
    // cliente le abonó 200.000. Al cruzarla, la app tomaba el saldo completo.
    const recibido = 200000.0;
    const factura = 498828.0;

    test('al cruzar, el abono entra topado por lo que queda del recaudo', () {
      final porRepartir = RecaudoCruce.porRepartir(recaudo: recibido, aplicado: 0);
      expect(
        RecaudoCruce.abonoSugerido(disponible: factura, porRepartir: porRepartir),
        recibido,
        reason: 'antes entraba por los 498.828 completos',
      );
    });

    test('si la factura es menor que el recaudo, se cobra la factura', () {
      final porRepartir = RecaudoCruce.porRepartir(recaudo: 500000, aplicado: 0);
      expect(RecaudoCruce.abonoSugerido(disponible: 120000, porRepartir: porRepartir), 120000);
    });

    test('la segunda factura solo recibe lo que sobró de la primera', () {
      final tras = RecaudoCruce.porRepartir(recaudo: 500000, aplicado: 400000);
      expect(tras, 100000);
      expect(RecaudoCruce.abonoSugerido(disponible: 900000, porRepartir: tras), 100000);
    });

    test('sin plata disponible, la siguiente factura entra en cero', () {
      final tras = RecaudoCruce.porRepartir(recaudo: 500000, aplicado: 500000);
      expect(RecaudoCruce.abonoSugerido(disponible: 900000, porRepartir: tras), 0);
    });

    test('mientras no declare cuánto recibió, el tope es el saldo', () {
      final sinDeclarar = RecaudoCruce.porRepartir(recaudo: 0, aplicado: 0);
      expect(sinDeclarar, double.infinity);
      expect(RecaudoCruce.abonoSugerido(disponible: factura, porRepartir: sinDeclarar), factura);
    });

    test('editar el abono devuelve al bolsillo el que ya tenía', () {
      // Cruzó la factura por los 200.000 y ahora quiere cambiarlos: el tope
      // sigue siendo 200.000, no 0 por tenerlos ya contados.
      final porRepartir = RecaudoCruce.porRepartir(recaudo: recibido, aplicado: recibido);
      expect(porRepartir, 0);
      expect(
        RecaudoCruce.topeAbono(disponible: factura, porRepartir: porRepartir, abonoActual: recibido),
        recibido,
      );
    });

    test('al editar tampoco se puede pasar del saldo de la factura', () {
      final porRepartir = RecaudoCruce.porRepartir(recaudo: 900000, aplicado: 100000);
      expect(
        RecaudoCruce.topeAbono(disponible: 150000, porRepartir: porRepartir, abonoActual: 100000),
        150000,
      );
    });
  });

  group('RecaudoCruce: el aviso de exceso', () {
    test('señala el cruce que se pasa, con la cifra', () {
      expect(RecaudoCruce.excedido(recaudo: 200000, aplicado: 498828), true);
      expect(RecaudoCruce.exceso(recaudo: 200000, aplicado: 498828), 298828);
    });

    test('un cruce exacto no molesta', () {
      expect(RecaudoCruce.excedido(recaudo: 200000, aplicado: 200000), false);
      expect(RecaudoCruce.exceso(recaudo: 200000, aplicado: 200000), 0);
    });

    test('que sobre plata del recaudo es legítimo', () {
      expect(RecaudoCruce.excedido(recaudo: 200000, aplicado: 150000), false);
    });

    test('centavos de redondeo no bloquean el guardado', () {
      expect(RecaudoCruce.excedido(recaudo: 383008, aplicado: 383008.40), false);
    });

    test('aplicar sin declarar lo recibido también es exceso', () {
      expect(RecaudoCruce.excedido(recaudo: 0, aplicado: 500000), true);
    });
  });
}
