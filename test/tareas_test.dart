import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/utils/tareas_visita.dart';
import 'package:skypagos/widgets/tarea_card.dart';

Map<String, dynamic> tarea({
  String nombre = 'Exhibir material',
  bool pendiente = true,
  bool respondida = false,
}) =>
    {'id': 1, 'nombre': nombre, 'pendiente': pendiente, 'respondida': respondida};

void main() {
  group('Tareas en la visita', () {
    test('una tarea pendiente sin registrar impide cerrar la visita', () {
      final tareas = [tarea()];
      expect(TareasVisita.puedeCerrar(tareas), false);
      expect(TareasVisita.porResponder(tareas).length, 1);
      expect(TareasVisita.mensajeBloqueo(tareas), contains('Exhibir material'));
    });

    test('al registrar la información, la visita se puede cerrar', () {
      final tareas = [tarea(respondida: true)];
      expect(TareasVisita.puedeCerrar(tareas), true);
      expect(TareasVisita.mensajeBloqueo(tareas), isNull);
    });

    test('una tarea ya terminada no bloquea aunque no se haya respondido', () {
      final tareas = [tarea(pendiente: false)];
      expect(TareasVisita.puedeCerrar(tareas), true);
    });

    test('un cliente sin tareas nunca bloquea', () {
      expect(TareasVisita.puedeCerrar(const []), true);
      expect(TareasVisita.mensajeBloqueo(const []), isNull);
    });

    test('con varias pendientes, el aviso dice cuántas faltan', () {
      final tareas = [tarea(nombre: 'A'), tarea(nombre: 'B'), tarea(nombre: 'C', respondida: true)];
      expect(TareasVisita.porResponder(tareas).length, 2);
      expect(TareasVisita.mensajeBloqueo(tareas), contains('2 tareas'));
    });

    test('una tarea sin nombre igual bloquea, con un aviso genérico', () {
      final tareas = [tarea(nombre: '')];
      expect(TareasVisita.puedeCerrar(tareas), false);
      expect(TareasVisita.mensajeBloqueo(tareas), 'Registra la información de la tarea del cliente para finalizar la visita.');
    });
  });

  group('Texto del plazo de la tarea', () {
    test('describe el vencimiento en palabras del día a día', () {
      expect(TareaCard.textoPlazo({'indefinido': true}), 'Sin fecha límite');
      expect(TareaCard.textoPlazo({'diasRestantes': 0}), 'Vence hoy');
      expect(TareaCard.textoPlazo({'diasRestantes': 1}), 'Vence mañana');
      expect(TareaCard.textoPlazo({'diasRestantes': 5}), 'Vence en 5 días');
      expect(TareaCard.textoPlazo({'diasRestantes': -3}), 'Vencida hace 3 día(s)');
      expect(TareaCard.textoPlazo({'fechaLimite': '2026-09-30'}), 'Vence 2026-09-30');
    });
  });
}
