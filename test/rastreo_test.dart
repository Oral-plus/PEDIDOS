import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skypagos/config/app_config.dart';
import 'package:skypagos/models/cart_item.dart';
import 'package:skypagos/screens/recorrido_screen.dart';
import 'package:skypagos/services/order_db_service.dart';
import 'package:skypagos/services/rastreo/claves_rastreo.dart';
import 'package:skypagos/services/rastreo/cola_ubicaciones.dart';
import 'package:skypagos/services/rastreo/envio_ubicaciones.dart';
import 'package:skypagos/services/rastreo/estado_ubicacion_cliente.dart';
import 'package:skypagos/services/rastreo/punto_ubicacion.dart';

class AlmacenMemoria implements AlmacenCola {
  String? contenido;
  AlmacenMemoria([this.contenido]);

  @override
  Future<String?> leer() async => contenido;

  @override
  Future<void> escribir(String c) async => contenido = c;
}

PuntoUbicacion punto(String id, {String usuario = 'SKV18', bool simulada = false, int ms = 1758031200000}) => PuntoUbicacion(
      idLocal: id,
      latitud: 4.6097,
      longitud: -74.0817,
      precision: 8.5,
      simulada: simulada,
      origen: 'periodico',
      capturadoEnMs: ms,
      usuario: usuario,
    );

void main() {
  group('PuntoUbicacion', () {
    test('ida y vuelta por JSON conserva los datos', () {
      final p = PuntoUbicacion(
        idLocal: 'x1',
        latitud: 6.2442,
        longitud: -75.5812,
        precision: 12,
        velocidad: 1.5,
        simulada: true,
        origen: 'visita_inicio',
        capturadoEnMs: 1758031200000,
        clienteCodigo: 'C1017224547',
        visitaId: 77,
        usuario: 'SKV18',
      );
      final copia = PuntoUbicacion.desdeJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>)!;
      expect(copia.idLocal, 'x1');
      expect(copia.latitud, 6.2442);
      expect(copia.simulada, true);
      expect(copia.clienteCodigo, 'C1017224547');
      expect(copia.visitaId, 77);
      expect(copia.usuario, 'SKV18');
    });

    test('al servidor no se envia el usuario local (lo decide el token)', () {
      final cuerpo = punto('a').paraServidor();
      expect(cuerpo.containsKey('usuario'), false);
      expect(cuerpo['capturadoEnMs'], 1758031200000);
      expect(cuerpo.containsKey('clienteCodigo'), false);
    });

    test('descarta coordenadas invalidas o registros incompletos', () {
      expect(PuntoUbicacion.desdeJson({'idLocal': 'a', 'latitud': 0, 'longitud': 0, 'capturadoEnMs': 1}), isNull);
      expect(PuntoUbicacion.desdeJson({'idLocal': 'a', 'latitud': 95, 'longitud': 10, 'capturadoEnMs': 1}), isNull);
      expect(PuntoUbicacion.desdeJson({'latitud': 4.6, 'longitud': -74, 'capturadoEnMs': 1}), isNull);
    });

    test('el id local no se repite aunque se capture en el mismo milisegundo', () {
      final ids = List.generate(500, (_) => PuntoUbicacion.nuevoIdLocal(1758031200000)).toSet();
      expect(ids.length, 500);
    });
  });

  group('ColaUbicaciones', () {
    test('no duplica el mismo punto y conserva el orden', () async {
      final cola = ColaUbicaciones(AlmacenMemoria());
      await cola.agregar(punto('a'));
      await cola.agregar(punto('b'));
      await cola.agregar(punto('a'));
      expect((await cola.todos()).map((p) => p.idLocal), ['a', 'b']);
    });

    test('al superar el maximo descarta los mas antiguos', () async {
      final cola = ColaUbicaciones(AlmacenMemoria(), maximo: 3);
      for (final id in ['1', '2', '3', '4', '5']) {
        await cola.agregar(punto(id));
      }
      expect((await cola.todos()).map((p) => p.idLocal), ['3', '4', '5']);
    });

    test('solo entrega los pendientes del usuario y respeta el limite', () async {
      final cola = ColaUbicaciones(AlmacenMemoria());
      await cola.agregar(punto('a', usuario: 'SKV18'));
      await cola.agregar(punto('b', usuario: 'SKV20'));
      await cola.agregar(punto('c', usuario: 'SKV18'));
      await cola.agregar(punto('d', usuario: 'SKV18'));
      final lote = await cola.pendientesDe('SKV18', limite: 2);
      expect(lote.map((p) => p.idLocal), ['a', 'c']);
    });

    test('confirmar quita solo lo enviado', () async {
      final cola = ColaUbicaciones(AlmacenMemoria());
      for (final id in ['a', 'b', 'c']) {
        await cola.agregar(punto(id));
      }
      await cola.confirmar(['a', 'c']);
      expect((await cola.todos()).map((p) => p.idLocal), ['b']);
    });

    test('descarta los puntos de otro usuario que ya no se pueden enviar', () async {
      final cola = ColaUbicaciones(AlmacenMemoria());
      await cola.agregar(punto('a', usuario: 'SKV18'));
      await cola.agregar(punto('b', usuario: 'SKV20'));
      expect(await cola.descartarAjenos('SKV20'), 1);
      expect((await cola.todos()).map((p) => p.idLocal), ['b']);
    });

    test('un almacenamiento corrupto no rompe la cola', () async {
      final cola = ColaUbicaciones(AlmacenMemoria('{no es json'));
      expect(await cola.todos(), isEmpty);
      await cola.agregar(punto('a'));
      expect((await cola.todos()).length, 1);
    });
  });

  group('SesionRastreo', () {
    final ahora = DateTime(2026, 9, 16, 10);

    Future<SharedPreferences> prefs(Map<String, Object> valores) async {
      SharedPreferences.setMockInitialValues(valores);
      return SharedPreferences.getInstance();
    }

    test('sin usuario de rastreo no hay sesion (el servicio se detiene)', () async {
      final p = await prefs({ClavesRastreo.token: 't', ClavesRastreo.expira: ahora.add(const Duration(hours: 1)).millisecondsSinceEpoch});
      expect(SesionRastreo.desdePreferencias(p, ahora: ahora), isNull);
    });

    test('con token vigente del mismo usuario puede enviar', () async {
      final p = await prefs({
        ClavesRastreo.usuario: 'SKV18',
        ClavesRastreo.loginUsuario: 'skv18',
        ClavesRastreo.token: 't',
        ClavesRastreo.expira: ahora.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        ClavesRastreo.baseUrl: 'https://api.ejemplo',
      });
      final s = SesionRastreo.desdePreferencias(p, ahora: ahora)!;
      expect(s.puedeEnviar, true);
      expect(s.baseUrl, 'https://api.ejemplo');
      expect(s.encabezados['Authorization'], 'Bearer t');
    });

    test('con la sesion vencida sigue capturando pero no envia', () async {
      final p = await prefs({
        ClavesRastreo.usuario: 'SKV18',
        ClavesRastreo.token: 't',
        ClavesRastreo.expira: ahora.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      });
      final s = SesionRastreo.desdePreferencias(p, ahora: ahora)!;
      expect(s.vencida, true);
      expect(s.puedeEnviar, false);
      expect(s.baseUrl, AppConfig.apiUrls.first);
    });

    test('si inicio sesion otro usuario no envia con su token', () async {
      final p = await prefs({
        ClavesRastreo.usuario: 'SKV18',
        ClavesRastreo.loginUsuario: 'SKV20',
        ClavesRastreo.token: 't',
        ClavesRastreo.expira: ahora.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      expect(SesionRastreo.desdePreferencias(p, ahora: ahora)!.puedeEnviar, false);
    });
  });

  group('EnvioUbicaciones', () {
    const sesion = SesionRastreo(usuario: 'SKV18', token: 't', vencida: false, baseUrl: 'https://api.ejemplo', idServicio: 'SVC-1');

    test('envia el lote al endpoint con el token y sin el usuario local', () async {
      late http.Request recibida;
      final cliente = MockClient((req) async {
        recibida = req;
        return http.Response(jsonEncode({'success': true, 'data': {'guardados': 2}}), 200, headers: {'content-type': 'application/json'});
      });
      final r = await EnvioUbicaciones.enviar(sesion, [punto('a'), punto('b', simulada: true)], cliente: cliente);
      expect(r, ResultadoEnvio.enviado);
      expect(recibida.url.toString(), 'https://api.ejemplo/api/ubicaciones');
      expect(recibida.headers['Authorization'], 'Bearer t');
      final cuerpo = jsonDecode(recibida.body) as Map<String, dynamic>;
      expect(cuerpo['idServicio'], 'SVC-1');
      final puntos = cuerpo['puntos'] as List;
      expect(puntos.length, 2);
      expect((puntos[1] as Map)['simulada'], true);
      expect((puntos[0] as Map).containsKey('usuario'), false);
    });

    test('401 se reporta como sesion invalida para conservar la cola', () async {
      final cliente = MockClient((_) async => http.Response('{}', 401));
      expect(await EnvioUbicaciones.enviar(sesion, [punto('a')], cliente: cliente), ResultadoEnvio.sesionInvalida);
    });

    test('un error de red no se confunde con un envio exitoso', () async {
      final cliente = MockClient((_) async => throw Exception('sin red'));
      expect(await EnvioUbicaciones.enviar(sesion, [punto('a')], cliente: cliente), ResultadoEnvio.fallo);
    });

    test('sin token no intenta enviar', () async {
      const sinToken = SesionRastreo(usuario: 'SKV18', token: null, vencida: true, baseUrl: 'https://api.ejemplo');
      var llamadas = 0;
      final cliente = MockClient((_) async {
        llamadas++;
        return http.Response('{}', 200);
      });
      expect(await EnvioUbicaciones.enviar(sinToken, [punto('a')], cliente: cliente), ResultadoEnvio.sesionInvalida);
      expect(llamadas, 0);
    });
  });

  group('EstadoUbicacionCliente', () {
    test('en cliente con la distancia', () {
      final e = EstadoUbicacionCliente.desdeRespuesta({'enCliente': true, 'distanciaM': 35, 'radioM': 150}, hayUbicacion: true);
      expect(e.tipo, TipoUbicacionCliente.enCliente);
      expect(e.detalle, 'A 35 m de la dirección registrada');
    });

    test('fuera de cliente informa distancia y radio', () {
      final e = EstadoUbicacionCliente.desdeRespuesta({'enCliente': false, 'distanciaM': 1240, 'radioM': 150}, hayUbicacion: true);
      expect(e.tipo, TipoUbicacionCliente.fueraDeCliente);
      expect(e.detalle, 'A 1,2 km de la dirección registrada (radio 150 m)');
    });

    test('la ubicacion simulada tiene prioridad sobre cualquier resultado', () {
      final e = EstadoUbicacionCliente.desdeRespuesta({'enCliente': true, 'distanciaM': 0}, hayUbicacion: true, simulada: true);
      expect(e.tipo, TipoUbicacionCliente.simulada);
    });

    test('sin GPS, sin coordenadas del cliente o sin respuesta', () {
      expect(EstadoUbicacionCliente.desdeRespuesta(null, hayUbicacion: false).tipo, TipoUbicacionCliente.sinUbicacion);
      expect(EstadoUbicacionCliente.desdeRespuesta({'sinCoordenadas': true}, hayUbicacion: true).tipo, TipoUbicacionCliente.sinCoordenadas);
      expect(EstadoUbicacionCliente.desdeRespuesta(null, hayUbicacion: true).tipo, TipoUbicacionCliente.sinConexion);
    });

    test('formato de distancias', () {
      expect(EstadoUbicacionCliente.distanciaTexto(0), '0 m');
      expect(EstadoUbicacionCliente.distanciaTexto(999), '999 m');
      expect(EstadoUbicacionCliente.distanciaTexto(1000), '1,0 km');
      expect(EstadoUbicacionCliente.distanciaTexto(23456), '23 km');
    });
  });

  group('Recorrido', () {
    test('hora legible desde la fecha del servidor', () {
      expect(RecorridoScreen.horaDe('2026-09-16 09:05:12'), '9:05 a. m.');
      expect(RecorridoScreen.horaDe('2026-09-16 00:30:00'), '12:30 a. m.');
      expect(RecorridoScreen.horaDe('2026-09-16 13:45:00'), '1:45 p. m.');
      expect(RecorridoScreen.horaDe(null), '—');
    });

    test('origen y fecha', () {
      expect(RecorridoScreen.origenTexto('visita_inicio'), 'Inicio de visita');
      expect(RecorridoScreen.origenTexto('periodico'), 'Registro automático');
      expect(RecorridoScreen.fechaTexto(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('Pedido con comentarios', () {
    final items = [
      CartItem(id: 'a', title: 'Crema', price: 1500, originalPrice: 1500, image: '', description: '', codigoSap: 'ART001', quantity: 2),
    ];

    test('envia comentario de despachos y comentario comercial por separado', () {
      final cuerpo = OrderDbService.construirCuerpo(
        cartItems: items,
        cedula: 'C1',
        nombre: 'Cliente',
        correo: 'c@x.com',
        telefono: '1',
        comentarioDespacho: '  Entregar en bodega  ',
        comentarioComercial: 'Precio especial',
      )!;
      expect(cuerpo['comentarioDespacho'], 'Entregar en bodega');
      expect(cuerpo['comentarioComercial'], 'Precio especial');
      expect(cuerpo['observaciones'], isNull);
    });

    test('comentarios vacios viajan como null', () {
      final cuerpo = OrderDbService.construirCuerpo(
        cartItems: items,
        cedula: 'C1',
        nombre: 'Cliente',
        correo: 'c@x.com',
        telefono: '1',
        comentarioDespacho: '   ',
      )!;
      expect(cuerpo['comentarioDespacho'], isNull);
      expect(cuerpo['comentarioComercial'], isNull);
    });

    test('sin productos validos no arma pedido', () {
      expect(
        OrderDbService.construirCuerpo(cartItems: const [], cedula: 'C1', nombre: 'x', correo: 'x@x.com', telefono: '1'),
        isNull,
      );
    });
  });
}
