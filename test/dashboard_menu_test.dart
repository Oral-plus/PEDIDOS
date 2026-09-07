import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skypagos/screens/client_menu_screen.dart';

void main() {
  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ClientMenuScreen()));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('dashboard: muestra las cuatro opciones del menú',
      (WidgetTester tester) async {
    await abrir(tester);

    expect(find.text('Socio de Negocio'), findsOneWidget);
    expect(find.text('Rutero'), findsOneWidget);
    expect(find.text('Mis Rutas'), findsOneWidget);
    expect(find.text('Cuadre de Caja'), findsOneWidget);
  });

  testWidgets('dashboard: cada opción tiene su icono',
      (WidgetTester tester) async {
    await abrir(tester);

    expect(find.byIcon(Icons.storefront_rounded), findsWidgets);
    expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget);
    expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
  });

  testWidgets('dashboard: sin cliente el Rutero queda bloqueado y avisa',
      (WidgetTester tester) async {
    await abrir(tester);

    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Requiere cliente'), findsOneWidget);

    final tarjeta = find
        .ancestor(of: find.text('Rutero'), matching: find.byType(AnimatedScale))
        .first;
    await tester.tap(find.descendant(of: tarjeta, matching: find.byType(InkWell)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Elige primero un cliente en Socio de Negocio'), findsOneWidget);
  });

  testWidgets('dashboard: las opciones responden al toque con animación',
      (WidgetTester tester) async {
    await abrir(tester);

    final escala = find
        .ancestor(of: find.text('Mis Rutas'), matching: find.byType(AnimatedScale))
        .first;
    expect(tester.widget<AnimatedScale>(escala).scale, 1.0);

    final gesto = await tester.startGesture(tester.getCenter(find.text('Mis Rutas')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(escala).scale, lessThan(1.0));

    await gesto.cancel();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedScale>(escala).scale, 1.0);
  });

  testWidgets('dashboard: el cuadre de caja no muestra contador sin pendientes',
      (WidgetTester tester) async {
    await abrir(tester);

    expect(find.text('Recaudos en efectivo'), findsOneWidget);
    expect(find.text('Por cuadrar'), findsNothing);
  });
}
