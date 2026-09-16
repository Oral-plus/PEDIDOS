import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/models/cart_item.dart';
import 'package:skypagos/providers/cart_provider.dart';
import 'package:skypagos/utils/price_utils.dart';

Map<String, dynamic> _producto({
  String title = 'Crema dental',
  dynamic price = 1500,
  String codigoSap = 'ART001',
  String? textura,
}) {
  return {
    'title': title,
    'price': price,
    'originalPrice': price,
    'image': '',
    'description': '',
    'codigoSap': codigoSap,
    'textura': textura,
  };
}

void main() {
  group('CartItem.parsePrice', () {
    test('acepta numeros directos', () {
      expect(CartItem.parsePrice(1500), 1500.0);
      expect(CartItem.parsePrice(1500.50), 1500.50);
    });

    test('miles con punto colombiano se interpretan como entero', () {
      expect(CartItem.parsePrice('304.532'), 304532.0);
    });

    test('coma decimal se respeta', () {
      expect(CartItem.parsePrice('1500,50'), 1500.50);
    });

    test('formato mixto miles.punto y coma decimal', () {
      expect(CartItem.parsePrice('1.234.567,89'), 1234567.89);
    });

    test('nulo y vacio dan cero', () {
      expect(CartItem.parsePrice(null), 0.0);
      expect(CartItem.parsePrice(''), 0.0);
      expect(CartItem.parsePrice(r'$'), 0.0);
    });
  });

  group('CartItem totales', () {
    test('totalPrice multiplica precio por cantidad', () {
      final item = CartItem(
        id: 'a', title: 'x', price: 1500, originalPrice: 1500,
        image: '', description: '', codigoSap: 'ART001', quantity: 3,
      );
      expect(item.totalPrice, 4500.0);
    });

    test('isValid exige codigo, precio y cantidad', () {
      final valido = CartItem(id: 'a', title: 'x', price: 10, originalPrice: 10, image: '', description: '', codigoSap: 'C1');
      final sinPrecio = CartItem(id: 'b', title: 'x', price: 0, originalPrice: 0, image: '', description: '', codigoSap: 'C2');
      expect(valido.isValid, true);
      expect(sinPrecio.isValid, false);
    });
  });

  group('CartProvider', () {
    test('addItem agrega un producto nuevo', () {
      final cart = CartProvider();
      cart.addItem(_producto());
      expect(cart.items.length, 1);
      expect(cart.itemCount, 1);
      expect(cart.totalAmount, 1500.0);
    });

    test('addItem del mismo producto incrementa cantidad, no duplica', () {
      final cart = CartProvider();
      cart.addItem(_producto());
      cart.addItem(_producto());
      cart.addItem(_producto());
      expect(cart.items.length, 1);
      expect(cart.itemCount, 3);
      expect(cart.totalAmount, 4500.0);
    });

    test('misma referencia con distinta textura son lineas separadas', () {
      final cart = CartProvider();
      cart.addItem(_producto(textura: 'Suave'));
      cart.addItem(_producto(textura: 'Media'));
      expect(cart.items.length, 2);
      expect(cart.itemCount, 2);
    });

    test('dos referencias distintas con el mismo nombre son lineas separadas', () {
      final cart = CartProvider();
      cart.addItem(_producto(title: 'CEP ORIGINAL', codigoSap: '50360251'));
      cart.addItem(_producto(title: 'CEP ORIGINAL', codigoSap: '50360256'));
      expect(cart.items.length, 2);
      expect(cart.items.map((i) => i.codigoSap), containsAll(['50360251', '50360256']));
    });

    test('addItem devuelve el id de la linea y cantidadDe lo consulta', () {
      final cart = CartProvider();
      final id = cart.addItem(_producto());
      expect(cart.cantidadDe(id), 1);
      cart.addItem(_producto());
      expect(cart.cantidadDe(id), 2);
      cart.updateQuantity(id, 7);
      expect(cart.cantidadDe(id), 7);
      expect(cart.cantidadDe('inexistente'), 0);
    });

    test('updateQuantity a cero elimina la linea', () {
      final cart = CartProvider();
      cart.addItem(_producto());
      final id = cart.items.first.id;
      cart.updateQuantity(id, 0);
      expect(cart.items.isEmpty, true);
      expect(cart.totalAmount, 0.0);
    });

    test('updateQuantity ajusta el total', () {
      final cart = CartProvider();
      cart.addItem(_producto(price: 2000));
      final id = cart.items.first.id;
      cart.updateQuantity(id, 4);
      expect(cart.itemCount, 4);
      expect(cart.totalAmount, 8000.0);
    });

    test('removeItem quita la linea y clearCart vacia', () {
      final cart = CartProvider();
      cart.addItem(_producto(codigoSap: 'A', title: 'A'));
      cart.addItem(_producto(codigoSap: 'B', title: 'B'));
      cart.removeItem(cart.items.first.id);
      expect(cart.items.length, 1);
      cart.clearCart();
      expect(cart.items.isEmpty, true);
      expect(cart.totalAmount, 0.0);
    });

    test('total suma varias lineas con cantidades distintas', () {
      final cart = CartProvider();
      cart.addItem(_producto(codigoSap: 'A', title: 'A', price: 1500));
      cart.addItem(_producto(codigoSap: 'A', title: 'A', price: 1500));
      cart.addItem(_producto(codigoSap: 'B', title: 'B', price: 3000));
      expect(cart.totalAmount, 1500 * 2 + 3000);
      expect(cart.itemCount, 3);
    });
  });

  group('Descuentos del cliente', () {
    Map<String, dynamic> conDescuento(String codigo, double pct, {double precio = 10000}) => {
          ..._producto(codigoSap: codigo, title: codigo, price: precio),
          'precioLista': precio,
          'descuentoPct': pct,
        };

    test('la linea toma el descuento por referencia y el total queda neto', () {
      final cart = CartProvider();
      final id = cart.addItem(conDescuento('A', 15));
      cart.updateQuantity(id, 3);
      final item = cart.items.first;
      expect(item.price, 10000.0);
      expect(item.precioNeto, 8500.0);
      expect(item.totalBruto, 30000.0);
      expect(item.totalPrice, 25500.0);
      expect(cart.totalAmount, 25500.0);
    });

    test('el pie de pagina se aplica sobre el subtotal neto, igual que SAP', () {
      final cart = CartProvider();
      cart.aplicarDescuentos('C1', const {'A': 10}, 5);
      cart.addItem(conDescuento('A', 10));
      cart.addItem(conDescuento('B', 0, precio: 2000));
      final r = cart.resumen;
      expect(r.subtotalBruto, 12000.0);
      expect(r.descuentoLineas, 1000.0);
      expect(r.subtotalNeto, 11000.0);
      expect(r.descuentoPie, 550.0);
      expect(r.total, 10450.0);
      expect(cart.totalAmount, 10450.0);
    });

    test('aplicarDescuentos reprecia lo que ya estaba en el carrito', () {
      final cart = CartProvider();
      cart.addItem(_producto(codigoSap: 'A', title: 'A', price: 1000));
      expect(cart.totalAmount, 1000.0);
      cart.aplicarDescuentos('C1', const {'A': 20}, 10);
      expect(cart.items.first.descuentoPct, 20.0);
      expect(cart.totalAmount, 720.0);
    });

    test('sin descuentos el carrito se comporta igual que antes', () {
      final cart = CartProvider();
      cart.addItem(_producto(price: 1500));
      cart.addItem(_producto(price: 1500));
      expect(cart.resumen.descuentoLineas, 0.0);
      expect(cart.resumen.descuentoPie, 0.0);
      expect(cart.totalAmount, 3000.0);
    });
  });

  group('PriceUtils.formatPriceDisplay', () {
    test('formatea con separador de miles y dos decimales', () {
      expect(PriceUtils.formatPriceDisplay(304532), r'$304.532,00');
    });

    test('nulo da cero con signo', () {
      expect(PriceUtils.formatPriceDisplay(null), r'$0.00');
    });
  });
}
