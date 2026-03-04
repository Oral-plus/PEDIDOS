import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skypagos/main.dart';

void main() {
  testWidgets('SkyPagos app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SkyPagosApp());

    // Wait for the splash screen to complete
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Verify that we're on the login screen
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Inicia sesión para continuar'), findsOneWidget);
    
    // Verify login form elements exist
    expect(find.byType(TextFormField), findsAtLeast(2)); // Email and password fields
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('¿No tienes cuenta? Regístrate'), findsOneWidget);
  });

  testWidgets('Login form validation test', (WidgetTester tester) async {
    await tester.pumpWidget(const SkyPagosApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Try to submit empty form
    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pump();

    // Should show validation errors
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('Navigation to register screen test', (WidgetTester tester) async {
    await tester.pumpWidget(const SkyPagosApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Tap on register link
    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();

    // Should navigate to register screen
    expect(find.text('Crear Cuenta'), findsOneWidget);
  });
}