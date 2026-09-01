import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skypagos/main.dart';

void main() {
  testWidgets('SkyPagos app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SkyPagosApp());

    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Inicia sesión para continuar'), findsOneWidget);
    
    expect(find.byType(TextFormField), findsAtLeast(2));
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('¿No tienes cuenta? Regístrate'), findsOneWidget);
  });

  testWidgets('Login form validation test', (WidgetTester tester) async {
    await tester.pumpWidget(const SkyPagosApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pump();

    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('Navigation to register screen test', (WidgetTester tester) async {
    await tester.pumpWidget(const SkyPagosApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();

    expect(find.text('Crear Cuenta'), findsOneWidget);
  });
}