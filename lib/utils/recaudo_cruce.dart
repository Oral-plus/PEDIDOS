/// Reparto del dinero recibido entre las facturas que el cliente está pagando.
///
/// Regla única: no se puede aplicar a la cartera más plata de la que el cliente
/// entregó. Aplicar de más deja la factura marcada como cobrada por un dinero
/// que nunca entró, y entonces desaparece del listado para el siguiente cobro:
/// el gestor recibe el abono parcial y la factura ya no vuelve a salir.
class RecaudoCruce {
  const RecaudoCruce._();

  /// Diferencias por debajo de un peso son redondeo, no un cobro de más.
  static const double tolerancia = 1;

  /// Lo que queda del dinero recibido por repartir entre documentos.
  ///
  /// Mientras el gestor no declare cuánto recibió no hay con qué topar, y el
  /// único límite es el saldo del documento.
  static double porRepartir({required double recaudo, required double aplicado}) {
    if (recaudo <= 0) return double.infinity;
    final resto = recaudo - aplicado;
    return resto > 0 ? resto : 0;
  }

  /// Abono con el que entra un documento al cruzarlo: lo que falta por cobrarle,
  /// topado con lo que quede del recaudo.
  static double abonoSugerido({required double disponible, required double porRepartir}) {
    final tope = disponible < porRepartir ? disponible : porRepartir;
    return tope > 0 ? tope : 0;
  }

  /// Tope de un abono escrito a mano. El abono que ese documento ya tiene
  /// vuelve al bolsillo antes de repartir, porque se va a reemplazar.
  static double topeAbono({
    required double disponible,
    required double porRepartir,
    required double abonoActual,
  }) =>
      abonoSugerido(disponible: disponible, porRepartir: porRepartir + abonoActual);

  /// Se está aplicando más plata de la que se recibió.
  static bool excedido({required double recaudo, required double aplicado}) =>
      aplicado - recaudo > tolerancia;

  /// Lo aplicado de más, para poder decírselo al gestor con cifras.
  static double exceso({required double recaudo, required double aplicado}) {
    final v = aplicado - recaudo;
    return v > 0 ? v : 0;
  }
}
