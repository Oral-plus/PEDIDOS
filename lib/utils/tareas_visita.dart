import '../models/tarea.dart';

/// Reglas de las tareas dentro de una visita.
///
/// Una visita no se puede cerrar mientras queden tareas del cliente sin
/// diligenciar: son compromisos que el gestor debe responder estando allí.
class TareasVisita {
  const TareasVisita._();

  static List<Tarea> porResponder(List<Tarea> tareas) =>
      tareas.where((t) => t.porResponder).toList();

  static bool puedeCerrar(List<Tarea> tareas) => porResponder(tareas).isEmpty;

  /// La tarea que el gestor tiene que diligenciar ahora, o null si no falta ninguna.
  static Tarea? primeraPorResponder(List<Tarea> tareas) {
    final faltan = porResponder(tareas);
    return faltan.isEmpty ? null : faltan.first;
  }

  /// La tarea que se muestra en la barra fija de la visita: la que falta y,
  /// si ya no falta ninguna, la primera para que quede a la vista lo registrado.
  static Tarea? destacada(List<Tarea> tareas) =>
      primeraPorResponder(tareas) ?? (tareas.isEmpty ? null : tareas.first);

  /// Mensaje para el gestor, o null si no hay nada que le impida cerrar.
  static String? mensajeBloqueo(List<Tarea> tareas) {
    final faltan = porResponder(tareas);
    if (faltan.isEmpty) return null;
    if (faltan.length == 1) {
      final nombre = faltan.first.nombre;
      return nombre.isEmpty
          ? 'Registra la información de la tarea del cliente para finalizar la visita.'
          : 'Registra la información de la tarea "$nombre" para finalizar la visita.';
    }
    return 'Te faltan ${faltan.length} tareas del cliente por registrar para finalizar la visita.';
  }
}
