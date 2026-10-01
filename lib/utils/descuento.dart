/// La regla de descuento del negocio, en un solo sitio.
///
/// La usan el carrito (descuentos que SAP aplica al cliente) y el simulador de
/// listas de precios. Si cambia la forma de redondear, cambia aquí y en ningún
/// otro lado.
class Descuento {
  const Descuento._();

  /// Pesos con dos decimales: lo mismo que guarda y factura SAP.
  static double redondear(double v) => (v * 100).roundToDouble() / 100;

  /// Un porcentaje siempre entre 0 y 100, nunca NaN.
  static double normalizar(double pct) => pct.isNaN ? 0 : pct.clamp(0, 100).toDouble();

  /// El precio ya con el descuento aplicado.
  static double aplicar(double precio, double pct) =>
      redondear(precio * (1 - normalizar(pct) / 100));

  /// Lo que se ahorra el cliente por unidad.
  static double ahorro(double precio, double pct) => redondear(precio - aplicar(precio, pct));

  /// Lee lo que el gestor escribe: admite coma o punto, y vacío es cero.
  static double desdeTexto(String texto) {
    final limpio = texto.trim().replaceAll('%', '').replaceAll(',', '.');
    if (limpio.isEmpty) return 0;
    return normalizar(double.tryParse(limpio) ?? 0);
  }
}
