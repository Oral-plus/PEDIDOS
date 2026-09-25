/// Reglas de las tareas dentro de una visita.
///
/// Una visita no se puede cerrar mientras queden tareas del cliente sin
/// diligenciar: son compromisos que el gestor debe responder estando allí.
class TareasVisita {
  const TareasVisita._();

  static List<Map<String, dynamic>> porResponder(List<Map<String, dynamic>> tareas) =>
      tareas.where((t) => t['pendiente'] == true && t['respondida'] != true).toList();

  static bool puedeCerrar(List<Map<String, dynamic>> tareas) => porResponder(tareas).isEmpty;

  /// Mensaje para el gestor, o null si no hay nada que le impida cerrar.
  static String? mensajeBloqueo(List<Map<String, dynamic>> tareas) {
    final faltan = porResponder(tareas);
    if (faltan.isEmpty) return null;
    if (faltan.length == 1) {
      final nombre = (faltan.first['nombre'] ?? '').toString().trim();
      return nombre.isEmpty
          ? 'Registra la información de la tarea del cliente para finalizar la visita.'
          : 'Registra la información de la tarea "$nombre" para finalizar la visita.';
    }
    return 'Te faltan ${faltan.length} tareas del cliente por registrar para finalizar la visita.';
  }
}
