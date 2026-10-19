double _aDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

/// Lectura única de la cartera del cliente.
///
/// El servidor entrega el saldo de SAP y, aparte, lo que el gestor ya cobró
/// pero SAP todavía no aplica. La app siempre debe mostrar el neto: si el
/// backend es viejo y no trae esos campos, cae al saldo de SAP.
class CarteraCliente {
  const CarteraCliente._();

  static double sap(Map<String, dynamic>? cartera) => _aDouble(cartera?['balance']);

  static double pendientePorAplicar(Map<String, dynamic>? cartera) =>
      _aDouble(cartera?['pendientePorAplicar']);

  static double neta(Map<String, dynamic>? cartera) {
    if (cartera == null) return 0;
    final neto = cartera['balanceNeto'];
    if (neto != null) return _aDouble(neto);
    final pendiente = pendientePorAplicar(cartera);
    final valor = sap(cartera) - pendiente;
    return valor > 0 ? valor : 0;
  }

  static bool tienePendientes(Map<String, dynamic>? cartera) => pendientePorAplicar(cartera) > 0;

  static List<Map<String, dynamic>> recaudosPendientes(Map<String, dynamic>? cartera) {
    final lista = cartera?['recaudosPendientes'];
    if (lista is! List) return const [];
    return lista.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Saldo neto de una factura del listado de documentos.
  static double saldoNetoDocumento(Map<String, dynamic>? documento) {
    if (documento == null) return 0;
    final neto = documento['saldoNeto'];
    return neto != null ? _aDouble(neto) : _aDouble(documento['saldo']);
  }

  /// Saldo de la factura en SAP, sin descontar lo que el gestor ya abonó.
  static double saldoSapDocumento(Map<String, dynamic>? documento) =>
      _aDouble(documento?['saldo']);

  /// Lo ya abonado a esa factura que SAP todavía no aplica.
  static double abonadoSinAplicar(Map<String, dynamic>? documento) =>
      _aDouble(documento?['pendientePorAplicar']);

  /// Lo que el gestor lleva recaudado de esa factura, según dbo.recaudos.
  ///
  /// No tiene ventana de tiempo: un abono de hace meses sigue contando, porque
  /// esa plata ya la recibió el gestor.
  static double recaudadoDocumento(Map<String, dynamic>? documento) =>
      _aDouble(documento?['totalRecaudado']);

  /// Lo que falta por recaudarle a esa factura.
  ///
  /// Lo calcula el servidor contra la tabla de recaudos. Si el backend es viejo
  /// y no lo manda, se cae al neto, que nunca ofrece de más.
  static double porCobrarDocumento(Map<String, dynamic>? documento) {
    final v = documento?['porCobrar'];
    return v != null ? _aDouble(v) : saldoNetoDocumento(documento);
  }

  /// Lo que todavía se le puede cobrar a esa factura.
  ///
  /// Es el neto, nunca negativo: un abono parcial deja disponible el resto, y
  /// una factura ya cubierta en la app queda en cero aunque SAP no se haya
  /// enterado. Es el tope de un abono nuevo.
  static double disponibleDocumento(Map<String, dynamic>? documento) {
    final neto = saldoNetoDocumento(documento);
    return neto > 0 ? neto : 0;
  }

  /// La factura ya tiene abonos que SAP no ha aplicado.
  static bool conAbonoPendiente(Map<String, dynamic>? documento) =>
      abonadoSinAplicar(documento) > 0;

  /// Ya se recaudó completa y solo falta que SAP la aplique.
  ///
  /// La factura deja de estar cobrable únicamente cuando lo recaudado la cubre.
  /// No se oculta: el gestor tiene que verla para saber que ya la cobró.
  static bool cubiertaEnApp(Map<String, dynamic>? documento) {
    if (recaudadoDocumento(documento) > 0) return porCobrarDocumento(documento) <= 0;
    // Backend viejo, sin lo recaudado: se decide con lo que SAP no ha aplicado.
    return conAbonoPendiente(documento) && disponibleDocumento(documento) <= 0;
  }
}
