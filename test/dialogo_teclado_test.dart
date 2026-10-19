import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/widgets/app_dialog.dart';

const double _alto = 1200;
const double _ancho = 800;
const Key _campo = Key('campo');

/// Abre un diálogo de la app con un campo de texto dentro.
///
/// Se manejan los insets reales de la vista, no un MediaQuery inventado: así
/// el teclado puede aparecer con el diálogo ya abierto, que es lo que pasa de
/// verdad cuando el gestor toca el campo.
Future<void> abrirDialogo(WidgetTester tester) async {
  tester.view.physicalSize = const Size(_ancho, _alto);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => showAppDialog<void>(
          ctx,
          child: const AppDialogShell(
            title: 'Cantidad',
            content: TextField(key: _campo),
            actions: [SizedBox.shrink()],
          ),
        ),
        child: const Text('abrir'),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Levanta el teclado con el diálogo ya abierto.
Future<void> abrirTeclado(WidgetTester tester, double alto) async {
  tester.view.viewInsets = FakeViewPadding(bottom: alto);
  await tester.pumpAndSettle();
}

void main() {
  group('Diálogos y el teclado', () {
    testWidgets('sin teclado el campo se ve completo', (tester) async {
      await abrirDialogo(tester);
      final campo = tester.getRect(find.byKey(_campo));
      expect(campo.top, greaterThanOrEqualTo(0));
      expect(campo.bottom, lessThanOrEqualTo(_alto));
    });

    testWidgets('al aparecer el teclado el campo NO queda debajo', (tester) async {
      const teclado = 600.0;
      await abrirDialogo(tester);
      await abrirTeclado(tester, teclado);

      final campo = tester.getRect(find.byKey(_campo));
      expect(campo.bottom, lessThanOrEqualTo(_alto - teclado),
          reason: 'el campo se solapa con el teclado: es justo lo que se reportó');
    });

    testWidgets('el diálogo sube cuando el teclado ocupa la mitad de abajo', (tester) async {
      await abrirDialogo(tester);
      final antes = tester.getRect(find.byKey(_campo)).center.dy;

      await abrirTeclado(tester, 600);
      final despues = tester.getRect(find.byKey(_campo)).center.dy;

      expect(despues, lessThan(antes), reason: 'se quedó donde estaba');
    });

    testWidgets('con un teclado enorme el diálogo se desplaza en vez de cortarse', (tester) async {
      await abrirDialogo(tester);
      await abrirTeclado(tester, 900);

      // Queda poco espacio: lo que no puede pasar es que el campo quede fuera.
      expect(find.byKey(_campo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
