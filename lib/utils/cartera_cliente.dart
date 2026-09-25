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
}
