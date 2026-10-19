import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/widgets/hoja_modal.dart';

const Size _pantalla = Size(800, 1200);
const Key _contenido = Key('contenido');

/// Monta una [HojaSegura] con un teclado de [teclado] píxeles y devuelve el
/// alto real que acabó ocupando su contenido.
///
/// La superficie de prueba tiene que medir lo mismo que el MediaQuery: si no,
/// el alto lo acaba decidiendo la ventana y la prueba mediría otra cosa.
Future<double> altoDelContenido(
  WidgetTester tester, {
  double teclado = 0,
  double alto = 2000,
  double? proporcion,
}) async {
  tester.view.physicalSize = _pantalla;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: _pantalla,
        viewInsets: EdgeInsets.only(bottom: teclado),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: HojaSegura(
            proporcionMaxima: proporcion ?? 0.85,
            child: SizedBox(key: _contenido, width: 800, height: alto),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(_contenido)).height;
}

void main() {
  group('Hojas modales y el teclado', () {
    testWidgets('sin teclado, la hoja llega hasta el 85 % de la pantalla', (tester) async {
      expect(await altoDelContenido(tester), closeTo(1200 * 0.85, 0.5));
    });

    testWidgets('con el teclado abierto la hoja encoge, no se sale de la pantalla', (tester) async {
      const teclado = 500.0;
      final alto = await altoDelContenido(tester, teclado: teclado);

      // El alto sale de lo que queda libre, no de la pantalla entera.
      expect(alto, closeTo((1200 - teclado) * 0.85, 0.5));
      // Y la hoja más el teclado siguen cabiendo: nada queda fuera.
      expect(alto + teclado, lessThanOrEqualTo(1200));
    });

    testWidgets('la hoja se separa del borde lo que mide el teclado', (tester) async {
      await altoDelContenido(tester, teclado: 500);
      final padding = tester.widget<Padding>(
        find.ancestor(of: find.byType(ConstrainedBox), matching: find.byType(Padding)).first,
      );
      expect(padding.padding, const EdgeInsets.only(bottom: 500));
    });

    testWidgets('una hoja puede pedir otra proporción y se respeta', (tester) async {
      expect(await altoDelContenido(tester, proporcion: 0.5), closeTo(600, 0.5));
    });

    testWidgets('una hoja pequeña no se estira: conserva su alto', (tester) async {
      expect(await altoDelContenido(tester, alto: 200), 200);
    });

    testWidgets('con teclado, una hoja pequeña tampoco se deforma', (tester) async {
      expect(await altoDelContenido(tester, alto: 200, teclado: 500), 200);
    });
  });
}
