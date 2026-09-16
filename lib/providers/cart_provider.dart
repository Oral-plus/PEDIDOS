import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/cart_item.dart';

import '../utils/price_utils.dart';

class ResumenCarrito {
  final double subtotalBruto;
  final double descuentoLineas;
  final double subtotalNeto;
  final double descuentoPiePct;
  final double descuentoPie;
  final double total;

  const ResumenCarrito({
    required this.subtotalBruto,
    required this.descuentoLineas,
    required this.subtotalNeto,
    required this.descuentoPiePct,
    required this.descuentoPie,
    required this.total,
  });

  double get descuentoTotal => CartItem.redondear(descuentoLineas + descuentoPie);

  bool get tieneDescuento => descuentoTotal > 0;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  late final UnmodifiableListView<CartItem> _vista = UnmodifiableListView(_items);
  int _itemCount = 0;
  String _clienteDescuentos = '';
  Map<String, double> _descuentosPorArticulo = const {};
  double _descuentoPiePct = 0;
  ResumenCarrito _resumen = const ResumenCarrito(
    subtotalBruto: 0,
    descuentoLineas: 0,
    subtotalNeto: 0,
    descuentoPiePct: 0,
    descuentoPie: 0,
    total: 0,
  );

  List<CartItem> get items => _vista;

  int get itemCount => _itemCount;

  String get clienteDescuentos => _clienteDescuentos;

  double get descuentoPiePct => _descuentoPiePct;

  ResumenCarrito get resumen => _resumen;

  double get totalAmount => _resumen.total;

  String get formattedTotal => PriceUtils.formatPriceDisplay(totalAmount);

  ResumenCarrito resumenDe(Iterable<CartItem> lineas) {
    var bruto = 0.0;
    var neto = 0.0;
    for (final item in lineas) {
      bruto += item.totalBruto;
      neto += item.totalPrice;
    }
    bruto = CartItem.redondear(bruto);
    neto = CartItem.redondear(neto);
    final pie = _descuentoPiePct.clamp(0, 100).toDouble();
    final descuentoPie = CartItem.redondear(neto * pie / 100);
    return ResumenCarrito(
      subtotalBruto: bruto,
      descuentoLineas: CartItem.redondear(bruto - neto),
      subtotalNeto: neto,
      descuentoPiePct: pie,
      descuentoPie: descuentoPie,
      total: CartItem.redondear(neto - descuentoPie),
    );
  }

  void _actualizar() {
    var cantidad = 0;
    for (final item in _items) {
      cantidad += item.quantity;
    }
    _itemCount = cantidad;
    _resumen = resumenDe(_items);
    notifyListeners();
  }

  void aplicarDescuentos(String cliente, Map<String, double> porArticulo, double piePct) {
    _clienteDescuentos = cliente;
    _descuentosPorArticulo = Map.unmodifiable(porArticulo);
    _descuentoPiePct = piePct.clamp(0, 100).toDouble();
    for (final item in _items) {
      item.descuentoPct = _descuentosPorArticulo[item.codigoSap] ?? 0;
    }
    _actualizar();
  }

  int cantidadDe(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    return index >= 0 ? _items[index].quantity : 0;
  }

  String addItem(Map<String, dynamic> product) {
    final codigo = (product['codigoSap'] ?? product['title'] ?? '').toString();
    final String itemId = '${codigo}_${product['textura'] ?? 'default'}';
    final existingIndex = _items.indexWhere((item) => item.id == itemId);

    if (existingIndex >= 0) {
      _items[existingIndex].quantity++;
    } else {
      final pct = (product['descuentoPct'] as num?)?.toDouble() ?? _descuentosPorArticulo[codigo] ?? 0;
      _items.add(CartItem(
        id: itemId,
        title: product['title']!,
        price: product['precioLista'] is num
            ? (product['precioLista'] as num).toDouble()
            : CartItem.parsePrice(product['price']),
        originalPrice: CartItem.parsePrice(product['originalPrice']),
        image: product['image']!,
        description: product['description']!,
        codigoSap: product['codigoSap'] ?? product['title']!,
        textura: product['textura'],
        descuentoPct: pct,
      ));
    }
    _actualizar();
    return itemId;
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    _actualizar();
  }

  void updateQuantity(String id, int quantity) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      _actualizar();
    }
  }

  void clearCart() {
    _items.clear();
    _actualizar();
  }
}
