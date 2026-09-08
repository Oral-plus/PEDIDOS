const Map<String, String> _equivalencias = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

class FiltroCliente {
  const FiltroCliente._();

  static String normalizar(Object? valor) {
    if (valor == null) return '';
    final buffer = StringBuffer();
    var espaciando = false;
    for (final char in valor.toString().toLowerCase().split('')) {
      final letra = _equivalencias[char] ?? char;
      if (letra.trim().isEmpty) {
        espaciando = buffer.isNotEmpty;
        continue;
      }
      if (espaciando) {
        buffer.write(' ');
        espaciando = false;
      }
      buffer.write(letra);
    }
    return buffer.toString();
  }

  static List<String> terminos(String consulta) =>
      normalizar(consulta).split(' ').where((t) => t.isNotEmpty).toList();

  static bool coincide(String consulta, List<Object?> campos) {
    final tokens = terminos(consulta);
    if (tokens.isEmpty) return true;
    final texto = campos
        .map(normalizar)
        .where((c) => c.isNotEmpty)
        .join(' ');
    if (texto.isEmpty) return false;
    return tokens.every(texto.contains);
  }

  static List<T> aplicar<T>(
    String consulta,
    List<T> items,
    List<Object?> Function(T) campos,
  ) {
    if (terminos(consulta).isEmpty) return List<T>.from(items);
    return items.where((item) => coincide(consulta, campos(item))).toList();
  }

  static List<Object?> camposCliente(Map<String, dynamic> cliente) => [
        cliente['id'] ?? cliente['codigo'] ?? cliente['cardCode'],
        cliente['nombre'] ?? cliente['cardName'],
        cliente['nombreComercial'] ?? cliente['cardFName'] ?? cliente['nombre1'],
      ];

  static List<Object?> camposDocumento(
    Map<String, dynamic> documento, {
    Map<String, dynamic>? cliente,
  }) =>
      [
        documento['numFactura'],
        documento['docNum'],
        documento['docEntry'],
        if (cliente != null) ...camposCliente(cliente),
      ];

  static String nombreParaMostrar(Map<String, dynamic>? cliente) {
    final comercial = nombreComercial(cliente);
    if (comercial.isNotEmpty) return comercial;
    return (cliente?['nombre'] ?? cliente?['cardName'] ?? '').toString().trim();
  }

  static String nombreComercial(Map<String, dynamic>? cliente) {
    if (cliente == null) return '';
    final valor = (cliente['nombreComercial'] ??
            cliente['cardFName'] ??
            cliente['nombre1'] ??
            '')
        .toString()
        .trim();
    return valor;
  }
}
