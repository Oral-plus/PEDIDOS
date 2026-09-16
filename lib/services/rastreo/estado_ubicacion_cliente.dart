enum TipoUbicacionCliente { evaluando, enCliente, fueraDeCliente, sinCoordenadas, sinUbicacion, simulada, sinConexion }

class EstadoUbicacionCliente {
  final TipoUbicacionCliente tipo;
  final int? distanciaM;
  final int? radioM;

  const EstadoUbicacionCliente(this.tipo, {this.distanciaM, this.radioM});

  static const evaluando = EstadoUbicacionCliente(TipoUbicacionCliente.evaluando);

  factory EstadoUbicacionCliente.desdeRespuesta(
    Map<String, dynamic>? data, {
    required bool hayUbicacion,
    bool simulada = false,
  }) {
    if (simulada) return const EstadoUbicacionCliente(TipoUbicacionCliente.simulada);
    if (!hayUbicacion) return const EstadoUbicacionCliente(TipoUbicacionCliente.sinUbicacion);
    if (data == null) return const EstadoUbicacionCliente(TipoUbicacionCliente.sinConexion);
    if (data['sinCoordenadas'] == true) return const EstadoUbicacionCliente(TipoUbicacionCliente.sinCoordenadas);
    final distancia = (data['distanciaM'] as num?)?.toInt();
    final radio = (data['radioM'] as num?)?.toInt();
    if (data['enCliente'] == true) {
      return EstadoUbicacionCliente(TipoUbicacionCliente.enCliente, distanciaM: distancia, radioM: radio);
    }
    if (data['enCliente'] == false) {
      return EstadoUbicacionCliente(TipoUbicacionCliente.fueraDeCliente, distanciaM: distancia, radioM: radio);
    }
    return const EstadoUbicacionCliente(TipoUbicacionCliente.sinConexion);
  }

  static String distanciaTexto(int metros) {
    if (metros < 1000) return '$metros m';
    final km = metros / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ',')} km';
  }

  String get titulo {
    switch (tipo) {
      case TipoUbicacionCliente.evaluando:
        return 'Validando ubicación…';
      case TipoUbicacionCliente.enCliente:
        return 'En el cliente';
      case TipoUbicacionCliente.fueraDeCliente:
        return 'Fuera del cliente';
      case TipoUbicacionCliente.sinCoordenadas:
        return 'Cliente sin coordenadas';
      case TipoUbicacionCliente.sinUbicacion:
        return 'Sin ubicación del dispositivo';
      case TipoUbicacionCliente.simulada:
        return 'Ubicación simulada';
      case TipoUbicacionCliente.sinConexion:
        return 'No se pudo validar';
    }
  }

  String get detalle {
    switch (tipo) {
      case TipoUbicacionCliente.evaluando:
        return 'Comparando tu ubicación con la dirección del cliente en SAP';
      case TipoUbicacionCliente.enCliente:
        return distanciaM == null ? 'Tu ubicación coincide con la del cliente' : 'A ${distanciaTexto(distanciaM!)} de la dirección registrada';
      case TipoUbicacionCliente.fueraDeCliente:
        final radio = radioM == null ? '' : ' (radio ${distanciaTexto(radioM!)})';
        return distanciaM == null ? 'Lejos de la dirección registrada$radio' : 'A ${distanciaTexto(distanciaM!)} de la dirección registrada$radio';
      case TipoUbicacionCliente.sinCoordenadas:
        return 'La dirección del cliente no tiene coordenadas registradas';
      case TipoUbicacionCliente.sinUbicacion:
        return 'Activa el GPS y el permiso de ubicación';
      case TipoUbicacionCliente.simulada:
        return 'Otra aplicación está modificando la ubicación';
      case TipoUbicacionCliente.sinConexion:
        return 'Toca para intentar de nuevo';
    }
  }
}
