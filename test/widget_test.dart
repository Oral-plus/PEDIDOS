import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skypagos/screens/login_screen.dart';

// La pantalla real de entrada es LoginScreen (usuario y contraseña, sin
// registro). Se prueba directa, sin pasar por el splash que consulta la red.
void main() {
  Widget app({String? aviso}) => MaterialApp(home: LoginScreen(aviso: aviso));

  testWidgets('login: muestra usuario, contraseña y el botón de entrar',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Usuario y contraseña'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(ElevatedButton, 'Ingresar'), findsOneWidget);
  });

  testWidgets('login: con campos vacíos avisa que son requeridos',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 2));

    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Ingresar'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ingresar'));
    await tester.pump();

    expect(find.text('Usuario y contraseña son requeridos'), findsOneWidget);
  });

  testWidgets('login: el aviso de llegada se muestra como ventana emergente',
      (WidgetTester tester) async {
    await tester.pumpWidget(app(aviso: 'Tu sesión expiró. Inicia sesión de nuevo.'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Sesión finalizada'), findsOneWidget);
    // El aviso aparece en la ventana emergente (también queda como texto bajo
    // el formulario, por eso se busca dentro del diálogo)
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Tu sesión expiró. Inicia sesión de nuevo.'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Entendido'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
