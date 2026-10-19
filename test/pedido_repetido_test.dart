import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/widgets/aviso_pedido_reciente.dart';

void main() {
  group('Aviso de pedido repetido', () {
    test('la cuenta atrás se lee como un reloj', () {
      expect(tiempoRestante(300), '5:00');
      expect(tiempoRestante(245), '4:05');
      expect(tiempoRestante(61), '1:01');
      expect(tiempoRestante(9), '0:09');
    });

    test('al llegar a cero avisa que ya se puede, no muestra 0:00', () {
      expect(tiempoRestante(0), 'Ya puedes registrarlo');
      expect(tiempoRestante(-5), 'Ya puedes registrarlo');
    });

    test('el código que manda el servidor es el que la pantalla reconoce', () {
      expect(codigoPedidoReciente, 'PEDIDO_RECIENTE');
    });
  });
}
