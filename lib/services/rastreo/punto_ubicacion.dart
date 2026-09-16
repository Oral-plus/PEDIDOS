import 'dart:math';

class PuntoUbicacion {
  final String idLocal;
  final double latitud;
  final double longitud;
  final double? precision;
  final double? altitud;
  final double? velocidad;
  final double? rumbo;
  final bool simulada;
  final String origen;
  final int capturadoEnMs;
  final String? clienteCodigo;
  final int? visitaId;
  final String usuario;

  const PuntoUbicacion({
    required this.idLocal,
    required this.latitud,
    required this.longitud,
    this.precision,
    this.altitud,
    this.velocidad,
    this.rumbo,
    this.simulada = false,
    required this.origen,
    required this.capturadoEnMs,
    this.clienteCodigo,
    this.visitaId,
    required this.usuario,
  });

  static final Random _azar = Random();

  static String nuevoIdLocal(int capturadoEnMs) =>
      '$capturadoEnMs-${_azar.nextInt(1 << 32).toRadixString(36)}${_azar.nextInt(1 << 32).toRadixString(36)}';

  static bool coordenadaValida(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat == 0 && lng == 0);

  Map<String, dynamic> toJson() => {
        ...paraServidor(),
        'usuario': usuario,
      };

  Map<String, dynamic> paraServidor() => {
        'idLocal': idLocal,
        'latitud': latitud,
        'longitud': longitud,
        if (precision != null) 'precision': precision,
        if (altitud != null) 'altitud': altitud,
        if (velocidad != null) 'velocidad': velocidad,
        if (rumbo != null) 'rumbo': rumbo,
        'simulada': simulada,
        'origen': origen,
        'capturadoEnMs': capturadoEnMs,
        if (clienteCodigo != null && clienteCodigo!.isNotEmpty) 'clienteCodigo': clienteCodigo,
        if (visitaId != null) 'visitaId': visitaId,
      };

  static PuntoUbicacion? desdeJson(Map<String, dynamic> j) {
    double? decimal(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final lat = decimal(j['latitud']);
    final lng = decimal(j['longitud']);
    final ms = j['capturadoEnMs'];
    final id = (j['idLocal'] ?? '').toString();
    if (lat == null || lng == null || !coordenadaValida(lat, lng) || ms is! num || id.isEmpty) return null;
    return PuntoUbicacion(
      idLocal: id,
      latitud: lat,
      longitud: lng,
      precision: decimal(j['precision']),
      altitud: decimal(j['altitud']),
      velocidad: decimal(j['velocidad']),
      rumbo: decimal(j['rumbo']),
      simulada: j['simulada'] == true,
      origen: (j['origen'] ?? 'periodico').toString(),
      capturadoEnMs: ms.toInt(),
      clienteCodigo: j['clienteCodigo']?.toString(),
      visitaId: (j['visitaId'] as num?)?.toInt(),
      usuario: (j['usuario'] ?? '').toString(),
    );
  }
}
