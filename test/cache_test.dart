import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/services/cache_service.dart';

void main() {
  // CacheService es singleton; se limpia antes de cada prueba.
  final cache = CacheService();

  setUp(() => cache.limpiar());

  group('CacheService TTL y guardado', () {
    test('devuelve el valor cacheado sin volver a cargar', () async {
      var llamadas = 0;
      Future<int> loader() async {
        llamadas++;
        return 42;
      }

      final a = await cache.obtener('k', const Duration(minutes: 5), loader);
      final b = await cache.obtener('k', const Duration(minutes: 5), loader);
      expect(a, 42);
      expect(b, 42);
      expect(llamadas, 1);
    });

    test('recarga cuando el TTL vencio', () async {
      var llamadas = 0;
      Future<int> loader() async {
        llamadas++;
        return llamadas;
      }

      await cache.obtener('k', Duration.zero, loader);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final segundo = await cache.obtener('k', Duration.zero, loader);
      expect(segundo, 2);
      expect(llamadas, 2);
    });

    test('no cachea null', () async {
      var llamadas = 0;
      Future<int?> loader() async {
        llamadas++;
        return null;
      }

      await cache.obtener<int?>('k', const Duration(minutes: 5), loader);
      await cache.obtener<int?>('k', const Duration(minutes: 5), loader);
      expect(llamadas, 2);
    });

    test('guardarSi bloquea el guardado cuando devuelve false', () async {
      var llamadas = 0;
      Future<int> loader() async {
        llamadas++;
        return 7;
      }

      await cache.obtener('k', const Duration(minutes: 5), loader, guardarSi: (_) => false);
      await cache.obtener('k', const Duration(minutes: 5), loader, guardarSi: (_) => false);
      expect(llamadas, 2);
    });
  });

  group('CacheService invalidacion', () {
    test('invalidar quita una clave', () async {
      cache.guardar('cliente:1', 'x', const Duration(minutes: 5));
      expect(cache.leer<String>('cliente:1'), 'x');
      cache.invalidar('cliente:1');
      expect(cache.leer<String>('cliente:1'), null);
    });

    test('invalidarPrefijo quita todas las del prefijo', () async {
      cache.guardar('pedidos:1:total', 1, const Duration(minutes: 5));
      cache.guardar('pedidos:1:ultimo', 2, const Duration(minutes: 5));
      cache.guardar('cartera:1', 3, const Duration(minutes: 5));
      cache.invalidarPrefijo('pedidos:');
      expect(cache.leer<int>('pedidos:1:total'), null);
      expect(cache.leer<int>('pedidos:1:ultimo'), null);
      expect(cache.leer<int>('cartera:1'), 3);
    });
  });

  group('CacheService tope y expulsion', () {
    test('el tope es generoso y acotado segun recursos', () {
      expect(cache.capacidad, greaterThanOrEqualTo(600));
      expect(cache.capacidad, lessThanOrEqualTo(6000));
    });

    test('no supera el tope y expulsa las mas antiguas', () async {
      final cap = cache.capacidad;
      const ttl = Duration(minutes: 5);
      for (var i = 0; i < cap + 500; i++) {
        cache.guardar('k$i', i, ttl);
      }
      expect(cache.longitud, lessThanOrEqualTo(cap));
      // La primera insertada fue expulsada por antiguedad.
      expect(cache.leer<int>('k0'), null);
      // Una reciente sigue viva.
      expect(cache.leer<int>('k${cap + 499}'), cap + 499);
    });

    test('un hit renueva la posicion (LRU) y sobrevive a la expulsion', () async {
      final cap = cache.capacidad;
      const ttl = Duration(minutes: 5);
      cache.guardar('viejo', 1, ttl);
      // Llenar justo hasta el tope (sin disparar expulsion todavia).
      for (var i = 0; i < cap - 1; i++) {
        cache.guardar('r$i', i, ttl);
      }
      // Tocar 'viejo' lo vuelve el mas reciente; quedan antes las 'r0..r(cap-2)'.
      expect(cache.leer<int>('viejo'), 1);
      // Insertar cap-1 nuevas: expulsa exactamente las cap-1 'r', no a 'viejo'.
      for (var i = 0; i < cap - 1; i++) {
        cache.guardar('n$i', i, ttl);
      }
      expect(cache.longitud, lessThanOrEqualTo(cap));
      // 'viejo' sobrevive por haber sido tocado; una 'r' antigua ya no esta.
      expect(cache.leer<int>('viejo'), 1);
      expect(cache.leer<int>('r0'), null);
    });
  });
}
