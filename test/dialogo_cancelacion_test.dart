import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pantalla extends StatefulWidget {
  const _Pantalla();

  @override
  State<_Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<_Pantalla> {
  final TextEditingController _obsCancelacion = TextEditingController();
  String ultimaObservacion = '';

  @override
  void dispose() {
    _obsCancelacion.dispose();
    super.dispose();
  }

  Future<void> _cancelar() async {
    _obsCancelacion.clear();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar recibo N° 1'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _obsCancelacion,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(counterText: ''),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancelar recibo')),
        ],
      ),
    );
    final observaciones = _obsCancelacion.text;
    if (confirmado == true && mounted) {
      setState(() => ultimaObservacion = observaciones);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(onPressed: _cancelar, child: const Text('Cancelar recibo N° 1')),
            Text(ultimaObservacion),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('cancelar un recibo con observaciones no rompe el cierre del dialogo',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Pantalla()));

    await tester.tap(find.text('Cancelar recibo N° 1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'se mojo el formato en la ruta');
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancelar recibo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('se mojo el formato en la ruta'), findsOneWidget);
  });

  testWidgets('el dialogo se puede abrir de nuevo con el campo vacio', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Pantalla()));

    await tester.tap(find.text('Cancelar recibo N° 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'primera novedad');
    await tester.tap(find.text('Cancelar recibo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar recibo N° 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextField, 'primera novedad'), findsNothing);
  });
}
