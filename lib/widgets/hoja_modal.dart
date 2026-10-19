import 'package:flutter/material.dart';

/// Hojas modales que no quedan debajo del teclado.
///
/// Una hoja modal no se mueve sola cuando se abre el teclado: hay que sumarle
/// el alto que este ocupa. Aquí vive esa cuenta, una sola vez, para que ninguna
/// hoja nazca tapando lo que el gestor está escribiendo.

/// Alto máximo de una hoja, sobre el espacio que queda libre.
const double _altoMaximo = 0.85;

/// Envuelve el contenido de una hoja para que respete el teclado.
///
/// Dos cosas, y las dos importan: se desplaza hacia arriba lo que mide el
/// teclado, y su alto máximo se calcula sobre el espacio **que queda**, de modo
/// que la hoja encoge en vez de empujarse fuera de la pantalla.
class HojaSegura extends StatelessWidget {
  final Widget child;
  final double proporcionMaxima;

  const HojaSegura({
    super.key,
    required this.child,
    this.proporcionMaxima = _altoMaximo,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final teclado = media.viewInsets.bottom;
    final disponible = media.size.height - teclado - media.padding.top;

    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: disponible * proporcionMaxima),
        child: child,
      ),
    );
  }
}

/// Abre una hoja modal ya preparada para el teclado.
///
/// Es la única puerta: así ninguna pantalla tiene que acordarse de
/// `isScrollControlled` ni de los márgenes del teclado.
Future<T?> mostrarHoja<T>(
  BuildContext context, {
  required Widget Function(BuildContext) constructor,
  double proporcionMaxima = _altoMaximo,
  Color fondo = Colors.transparent,
  bool descartable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: fondo,
    isDismissible: descartable,
    enableDrag: descartable,
    builder: (ctx) => HojaSegura(
      proporcionMaxima: proporcionMaxima,
      child: constructor(ctx),
    ),
  );
}
