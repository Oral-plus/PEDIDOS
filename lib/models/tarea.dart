/// Tareas que el área comercial asigna a los gestores.
///
/// El gestor las ve en el módulo de Tareas y, cuando la tarea está asociada a
/// un cliente, también al abrir la visita de ese cliente. Responder una tarea
/// no modifica la tarea original (la comparten varios gestores): se guarda una
/// respuesta propia por gestor y cliente.
library;

String _texto(Object? v) => (v ?? '').toString().trim();
int _entero(Object? v) => (v as num?)?.toInt() ?? 0;

/// Cliente al que está asociada una tarea.
class ClienteTarea {
  final String codigo;
  final String nombre;

  const ClienteTarea({required this.codigo, required this.nombre});

  factory ClienteTarea.fromJson(Map<String, dynamic> j) => ClienteTarea(
        codigo: _texto(j['codigo']),
        nombre: _texto(j['nombre']),
      );

  /// Lo que se le muestra al gestor: el nombre, y si no hay, el código.
  String get etiqueta => nombre.isEmpty ? codigo : nombre;
}

/// Lo que el gestor registró para una tarea en un cliente.
class RespuestaTarea {
  final int id;
  final String clienteCodigo;
  final bool cumplida;
  final String observacion;
  final int evidencias;
  final String fecha;

  const RespuestaTarea({
    required this.id,
    required this.clienteCodigo,
    required this.cumplida,
    required this.observacion,
    required this.evidencias,
    required this.fecha,
  });

  factory RespuestaTarea.fromJson(Map<String, dynamic> j) => RespuestaTarea(
        id: _entero(j['id']),
        clienteCodigo: _texto(j['clienteCodigo']),
        cumplida: j['cumplida'] == true,
        observacion: _texto(j['observacion']),
        evidencias: _entero(j['evidencias']),
        fecha: _texto(j['fecha']),
      );

  String get resumen {
    final estado = cumplida ? 'Cumplida' : 'No cumplida';
    final partes = <String>[
      if (observacion.isNotEmpty) observacion,
      if (evidencias == 1) '1 foto' else if (evidencias > 1) '$evidencias fotos',
    ];
    return partes.isEmpty ? estado : '$estado · ${partes.join(' · ')}';
  }
}

/// Lo que el gestor diligencia antes de enviar la respuesta.
///
/// [claveLocal] identifica este intento y no cambia entre reenvíos: si la red
/// se cae después de que el servidor guardó, volver a enviar devuelve la misma
/// respuesta en vez de duplicarla.
class BorradorRespuestaTarea {
  final bool cumplida;
  final String observacion;
  final List<String> fotos;
  final String claveLocal;

  const BorradorRespuestaTarea({
    required this.cumplida,
    this.observacion = '',
    this.fotos = const [],
    this.claveLocal = '',
  });

  /// Una clave estable por intento: tarea, cliente y el momento en que se abrió.
  static String nuevaClave(int tareaId, String clienteCodigo) =>
      'tar-$tareaId-$clienteCodigo-${DateTime.now().millisecondsSinceEpoch}';

  /// Si no se cumplió, hay que explicar por qué.
  bool get completo => cumplida || observacion.trim().length >= 4;
}

class Tarea {
  final int id;
  final String nombre;
  final String descripcion;
  final String area;
  final String estado;
  final String usuario;
  final String fechaLimite;
  final bool indefinido;
  final bool pendiente;
  final bool vencida;
  final int? diasRestantes;
  final List<ClienteTarea> clientes;
  final RespuestaTarea? respuesta;

  const Tarea({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    this.area = '',
    this.estado = 'PENDIENTE',
    this.usuario = '',
    this.fechaLimite = '',
    this.indefinido = false,
    this.pendiente = true,
    this.vencida = false,
    this.diasRestantes,
    this.clientes = const [],
    this.respuesta,
  });

  factory Tarea.fromJson(Map<String, dynamic> j) => Tarea(
        id: _entero(j['id']),
        nombre: _texto(j['nombre']),
        descripcion: _texto(j['descripcion']),
        area: _texto(j['area']),
        estado: _texto(j['estado']).isEmpty ? 'PENDIENTE' : _texto(j['estado']),
        usuario: _texto(j['usuario']),
        fechaLimite: _texto(j['fechaLimite']),
        indefinido: j['indefinido'] == true,
        pendiente: j['pendiente'] == true,
        vencida: j['vencida'] == true,
        diasRestantes: (j['diasRestantes'] as num?)?.toInt(),
        clientes: (j['clientes'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => ClienteTarea.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        respuesta: j['respuesta'] is Map
            ? RespuestaTarea.fromJson(Map<String, dynamic>.from(j['respuesta'] as Map))
            : null,
      );

  static List<Tarea> listaFromJson(Object? data) => (data as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((e) => Tarea.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  bool get respondida => respuesta != null;

  /// Queda por diligenciar en la visita.
  bool get porResponder => pendiente && !respondida;

  /// El plazo contado como lo diría un gestor.
  String get textoPlazo {
    if (indefinido) return 'Sin fecha límite';
    final dias = diasRestantes;
    if (dias == null) return fechaLimite.isEmpty ? 'Sin fecha límite' : 'Vence $fechaLimite';
    if (dias < 0) return 'Vencida hace ${dias.abs()} día(s)';
    if (dias == 0) return 'Vence hoy';
    if (dias == 1) return 'Vence mañana';
    return 'Vence en $dias días';
  }

  /// El cliente al que aplica, cuando no hay duda de cuál es.
  ClienteTarea? get clienteUnico => clientes.length == 1 ? clientes.first : null;
}

class ResumenTareas {
  final int total;
  final int pendientes;
  final int vencidas;
  final int porVencer;
  final int terminadas;

  const ResumenTareas({
    this.total = 0,
    this.pendientes = 0,
    this.vencidas = 0,
    this.porVencer = 0,
    this.terminadas = 0,
  });

  factory ResumenTareas.fromJson(Map<String, dynamic> j) => ResumenTareas(
        total: _entero(j['total']),
        pendientes: _entero(j['pendientes']),
        vencidas: _entero(j['vencidas']),
        porVencer: _entero(j['porVencer']),
        terminadas: _entero(j['terminadas']),
      );
}

/// Respuesta completa de `GET /api/tareas`.
class ListadoTareas {
  final bool exito;
  final List<Tarea> tareas;
  final ResumenTareas resumen;
  final int pendientesPorResponder;

  const ListadoTareas({
    required this.exito,
    this.tareas = const [],
    this.resumen = const ResumenTareas(),
    this.pendientesPorResponder = 0,
  });

  const ListadoTareas.fallo() : this(exito: false);

  factory ListadoTareas.fromJson(Map<String, dynamic> j) {
    final tareas = Tarea.listaFromJson(j['data']);
    return ListadoTareas(
      exito: true,
      tareas: tareas,
      resumen: ResumenTareas.fromJson(Map<String, dynamic>.from((j['resumen'] as Map?) ?? const {})),
      pendientesPorResponder:
          (j['pendientesPorResponder'] as num?)?.toInt() ?? tareas.where((t) => t.porResponder).length,
    );
  }
}
