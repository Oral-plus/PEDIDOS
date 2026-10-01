import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/models/cart_item.dart';
import 'package:skypagos/models/lista_precios.dart';
import 'package:skypagos/utils/descuento.dart';

void main() {
  group('La regla de descuento', () {
    test('aplica el porcentaje y redondea a pesos con dos decimales', () {
      expect(Descuento.aplicar(10000, 10), 9000);
      expect(Descuento.aplicar(3333.33, 15), 2833.33);
      expect(Descuento.aplicar(1, 33), 0.67);
    });

    test('sin descuento el precio no se toca', () {
      expect(Descuento.aplicar(12345.67, 0), 12345.67);
      expect(Descuento.ahorro(12345.67, 0), 0);
    });

    test('un descuento del 100 % deja el precio en cero', () {
      expect(Descuento.aplicar(8000, 100), 0);
      expect(Descuento.ahorro(8000, 100), 8000);
    });

    test('porcentajes imposibles no producen precios imposibles', () {
      expect(Descuento.aplicar(5000, 150), 0, reason: 'más de 100 se recorta');
      expect(Descuento.aplicar(5000, -20), 5000, reason: 'negativo no sube el precio');
      expect(Descuento.aplicar(5000, double.nan), 5000);
    });

    test('lo que se escribe en el campo se entiende con coma o punto', () {
      expect(Descuento.desdeTexto('12'), 12);
      expect(Descuento.desdeTexto('12,5'), 12.5);
      expect(Descuento.desdeTexto('12.5'), 12.5);
      expect(Descuento.desdeTexto(' 7 % '), 7);
      expect(Descuento.desdeTexto(''), 0);
      expect(Descuento.desdeTexto('abc'), 0);
      expect(Descuento.desdeTexto('999'), 100);
    });

    test('el carrito usa esta misma regla, no una copia', () {
      final item = CartItem(
        id: '1',
        title: 'Cepillo',
        price: 10000,
        originalPrice: 10000,
        image: '',
        description: '',
        codigoSap: 'A1',
        quantity: 2,
        descuentoPct: 10,
      );
      expect(item.precioNeto, Descuento.aplicar(10000, 10));
      expect(item.descuentoUnitario, Descuento.ahorro(10000, 10));
      expect(CartItem.redondear(2.005), Descuento.redondear(2.005));
    });
  });

  group('Listas de precios del gestor', () {
    final json = {
      'success': true,
      'actualizado': '2026-10-01T15:00:00.000Z',
      'listas': [
        {'id': 1, 'nombre': 'General', 'clientes': 30, 'productos': 2},
        {'id': 2, 'nombre': 'Mayorista', 'clientes': 1, 'productos': 1},
      ],
      'productos': [
        {
          'codigo': 'A1',
          'nombre': 'Cepillo Medio',
          'categoria': 'Cepillos',
          'precios': {'1': 5000, '2': 4200},
        },
        {
          'codigo': 'B2',
          'nombre': 'Crema Dental',
          'categoria': 'Cremas',
          'precios': {'1': 9000, '3': 0},
        },
      ],
    };

    test('lee listas, productos y los precios por lista', () {
      final c = CatalogoListas.fromJson(json);
      expect(c.exito, true);
      expect(c.vacio, false);
      expect(c.listas.first.nombre, 'General');
      expect(c.listas.first.detalle, '30 clientes · 2 productos');
      expect(c.productos.first.precioEn(1), 5000);
      expect(c.productos.first.precioEn(2), 4200);
    });

    test('un precio en cero no se toma como precio', () {
      final crema = CatalogoListas.fromJson(json).productos[1];
      expect(crema.precioEn(3), isNull);
      expect(crema.precioEn(1), 9000);
    });

    test('el precio simulado sale de la regla única', () {
      final cepillo = CatalogoListas.fromJson(json).productos.first;
      expect(cepillo.precioEnCon(1, 20), Descuento.aplicar(5000, 20));
      expect(cepillo.precioEnCon(2, 20), 3360);
      expect(cepillo.precioEnCon(9, 20), isNull, reason: 'lista donde no tiene precio');
    });

    test('la búsqueda encuentra por nombre, código o categoría', () {
      final c = CatalogoListas.fromJson(json);
      expect(c.filtrar(busqueda: 'crema').length, 1);
      expect(c.filtrar(busqueda: 'A1').length, 1);
      expect(c.filtrar(busqueda: 'cepillos').length, 1);
      expect(c.filtrar(busqueda: 'ZZZ'), isEmpty);
      expect(c.filtrar().length, 2, reason: 'sin búsqueda salen todos');
    });

    test('el selector arranca en el primer producto y tolera un código que ya no existe', () {
      final c = CatalogoListas.fromJson(json);
      expect(c.productoPorCodigo('B2')!.nombre, 'Crema Dental');
      expect(c.productoPorCodigo('NO-EXISTE')!.codigo, 'A1', reason: 'cae en el primero');
      expect(c.productoPorCodigo(null)!.codigo, 'A1');
      expect(const CatalogoListas.fallo().productoPorCodigo('A1'), isNull);
    });

    test('un producto muestra en qué listas tiene precio y en cuáles no', () {
      final crema = CatalogoListas.fromJson(json).productoPorCodigo('B2')!;
      expect(crema.precioEn(1), 9000);
      expect(crema.precioEn(2), isNull, reason: 'la crema no está en mayorista');
    });

    test('una respuesta vacía o mal formada no rompe la pantalla', () {
      final c = CatalogoListas.fromJson({'listas': null, 'productos': null});
      expect(c.vacio, true);
      expect(c.productos, isEmpty);
      expect(const CatalogoListas.fallo().exito, false);
    });

    test('una lista sin nombre se muestra con su número', () {
      final l = ListaPrecios.fromJson({'id': 7, 'nombre': '  '});
      expect(l.nombre, 'Lista 7');
      expect(l.detalle, '0 clientes · 0 productos');
    });
  });
}
