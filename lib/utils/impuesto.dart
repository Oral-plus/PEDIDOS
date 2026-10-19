import 'descuento.dart';

/// El IVA del pedido, en un solo sitio.
///
/// Los precios de las listas de SAP son base gravable: no traen el impuesto
/// dentro. Por eso el IVA se suma al subtotal, no se descompone de él.
class Impuesto {
  const Impuesto._();

  /// Tasa general. Si algún día hay excluidos, este es el punto por donde
  /// entra el dato por producto, sin tocar quien lo usa.
  static const double ivaPct = 19;

  /// El IVA que le corresponde a una base. Redondea con la misma regla de
  /// pesos que usa el resto del dinero de la app.
  static double de(double base, {double pct = ivaPct}) {
    if (base <= 0 || pct <= 0) return 0;
    return Descuento.redondear(base * pct / 100);
  }

  /// La base más su IVA.
  static double sobre(double base, {double pct = ivaPct}) =>
      Descuento.redondear(base + de(base, pct: pct));

  /// Cómo se rotula la línea: "IVA (19 %)", sin decimales de más.
  static String etiqueta([double pct = ivaPct]) {
    final texto = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : '$pct';
    return 'IVA ($texto %)';
  }
}
