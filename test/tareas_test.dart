import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/models/tarea.dart';
import 'package:skypagos/utils/tareas_visita.dart';

Tarea tarea({
  String nombre = 'Exhibir material',
  bool pendiente = true,
  bool respondida = false,
}) =>
    Tarea(
      id: 1,
      nombre: nombre,
      pendiente: pendiente,
      respuesta: respondida
          ? const RespuestaTarea(
              id: 7,
              clienteCodigo: 'C1',
              cumplida: true,
              observacion: '',
              evidencias: 0,
              fecha: '2026-09-25 10:00:00',
            )
          : null,
    );

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

    test('la barra fija muestra la tarea que falta, no otra', () {
      final tareas = [tarea(nombre: 'Ya hecha', respondida: true), tarea(nombre: 'Falta esta'), tarea(nombre: 'Y esta')];
      expect(TareasVisita.primeraPorResponder(tareas)!.nombre, 'Falta esta');
      expect(TareasVisita.destacada(tareas)!.nombre, 'Falta esta');
    });

    test('cuando ya no falta ninguna, la barra deja a la vista lo registrado', () {
      final tareas = [tarea(nombre: 'Exhibición', respondida: true)];
      expect(TareasVisita.primeraPorResponder(tareas), isNull);
      expect(TareasVisita.destacada(tareas)!.nombre, 'Exhibición');
    });

    test('sin tareas del cliente no hay barra que mostrar', () {
      expect(TareasVisita.destacada(const []), isNull);
      expect(TareasVisita.primeraPorResponder(const []), isNull);
    });

    test('una tarea sin nombre igual bloquea, con un aviso genérico', () {
      final tareas = [tarea(nombre: '')];
      expect(TareasVisita.puedeCerrar(tareas), false);
      expect(TareasVisita.mensajeBloqueo(tareas),
          'Registra la información de la tarea del cliente para finalizar la visita.');
    });
  });

  group('Texto del plazo de la tarea', () {
    test('describe el vencimiento en palabras del día a día', () {
      expect(const Tarea(id: 1, nombre: 'T', indefinido: true).textoPlazo, 'Sin fecha límite');
      expect(const Tarea(id: 1, nombre: 'T', diasRestantes: 0).textoPlazo, 'Vence hoy');
      expect(const Tarea(id: 1, nombre: 'T', diasRestantes: 1).textoPlazo, 'Vence mañana');
      expect(const Tarea(id: 1, nombre: 'T', diasRestantes: 5).textoPlazo, 'Vence en 5 días');
      expect(const Tarea(id: 1, nombre: 'T', diasRestantes: -3).textoPlazo, 'Vencida hace 3 día(s)');
      expect(const Tarea(id: 1, nombre: 'T', fechaLimite: '2026-09-30').textoPlazo, 'Vence 2026-09-30');
    });
  });

  group('Lectura de lo que responde el servidor', () {
    final json = {
      'success': true,
      'data': [
        {
          'id': 12,
          'nombre': 'Montar exhibición',
          'descripcion': 'En la góndola principal',
          'area': 'VENTAS',
          'estado': 'PENDIENTE',
          'usuario': 'MERCADEO',
          'fechaLimite': '2026-10-02',
          'indefinido': false,
          'pendiente': true,
          'vencida': false,
          'diasRestantes': 7,
          'clientes': [
            {'codigo': 'C1', 'nombre': 'TIENDA UNO'},
            {'codigo': 'C2', 'nombre': ''},
          ],
          'respondida': false,
        },
        {
          'id': 13,
          'nombre': 'Tomar inventario',
          'pendiente': true,
          'respondida': true,
          'respuesta': {
            'id': 44,
            'clienteCodigo': 'C1',
            'cumplida': true,
            'observacion': 'Listo',
            'evidencias': 2,
            'fecha': '2026-09-25 09:30:00',
          },
        },
      ],
      'resumen': {'total': 2, 'pendientes': 2, 'vencidas': 0, 'porVencer': 1, 'terminadas': 0},
      'pendientesPorResponder': 1,
    };

    test('arma las tareas con sus clientes y su respuesta', () {
      final listado = ListadoTareas.fromJson(json);
      expect(listado.exito, true);
      expect(listado.tareas.length, 2);
      expect(listado.resumen.porVencer, 1);
      expect(listado.pendientesPorResponder, 1);

      final primera = listado.tareas.first;
      expect(primera.clientes.length, 2);
      expect(primera.clienteUnico, isNull);
      expect(primera.clientes[1].etiqueta, 'C2', reason: 'sin nombre se muestra el código');
      expect(primera.respondida, false);
      expect(primera.porResponder, true);
    });

    test('la tarea respondida deja de pedir respuesta y resume lo registrado', () {
      final segunda = ListadoTareas.fromJson(json).tareas[1];
      expect(segunda.respondida, true);
      expect(segunda.porResponder, false);
      expect(segunda.respuesta!.evidencias, 2);
      expect(segunda.respuesta!.resumen, 'Cumplida · Listo · 2 fotos');
    });

    test('una respuesta sin comentario ni fotos se resume sola', () {
      const r = RespuestaTarea(
          id: 1, clienteCodigo: 'C1', cumplida: false, observacion: '', evidencias: 0, fecha: '');
      expect(r.resumen, 'No cumplida');
    });

    test('una sola foto se nombra en singular', () {
      const r = RespuestaTarea(
          id: 1, clienteCodigo: 'C1', cumplida: true, observacion: '', evidencias: 1, fecha: '');
      expect(r.resumen, 'Cumplida · 1 foto');
    });

    test('si el servidor no manda el conteo, se cuenta lo que falta por responder', () {
      final listado = ListadoTareas.fromJson({
        'data': [
          {'id': 1, 'nombre': 'A', 'pendiente': true},
          {'id': 2, 'nombre': 'B', 'pendiente': false},
        ],
      });
      expect(listado.pendientesPorResponder, 1);
    });

    test('un listado vacío o mal formado no rompe la pantalla', () {
      final listado = ListadoTareas.fromJson({'data': null, 'resumen': null});
      expect(listado.tareas, isEmpty);
      expect(listado.resumen.total, 0);
      expect(const ListadoTareas.fallo().exito, false);
    });
  });

  group('Lo que se diligencia antes de enviar', () {
    test('si se cumplió, el comentario es opcional', () {
      expect(const BorradorRespuestaTarea(cumplida: true).completo, true);
    });

    test('si no se cumplió, hay que explicar por qué', () {
      expect(const BorradorRespuestaTarea(cumplida: false).completo, false);
      expect(const BorradorRespuestaTarea(cumplida: false, observacion: 'no ').completo, false);
      expect(const BorradorRespuestaTarea(cumplida: false, observacion: 'Sin espacio').completo, true);
    });

    test('la clave del envío identifica tarea y cliente, para que un reintento no duplique', () {
      final clave = BorradorRespuestaTarea.nuevaClave(12, 'C901');
      expect(clave, startsWith('tar-12-C901-'));
      expect(const BorradorRespuestaTarea(cumplida: true).claveLocal, '',
          reason: 'sin clave el servidor sigue aceptando el envío');
      expect(BorradorRespuestaTarea(cumplida: true, claveLocal: clave).claveLocal, clave);
    });

    test('las fotos son opcionales en los dos casos', () {
      const b = BorradorRespuestaTarea(cumplida: true, fotos: ['/tmp/a.jpg']);
      expect(b.completo, true);
      expect(b.fotos.length, 1);
    });
  });
}
