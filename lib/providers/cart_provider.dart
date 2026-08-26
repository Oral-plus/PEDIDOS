import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/cart_item.dart';

import '../utils/price_utils.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  late final UnmodifiableListView<CartItem> _vista = UnmodifiableListView(_items);
  int _itemCount = 0;
  double _totalAmount = 0.0;

  /// Vista de solo lectura sobre la lista real; no copia en cada acceso.
  List<CartItem> get items => _vista;

  int get itemCount => _itemCount;

  double get totalAmount => _totalAmount;

  String get formattedTotal => PriceUtils.formatPriceDisplay(totalAmount);
  String get formattedTotalSinIva => PriceUtils.formatPriceDisplay(totalAmount / 1.19);
  String get formattedIVA => PriceUtils.formatPriceDisplay(totalAmount - (totalAmount / 1.19));

  // Los totales se recalculan una vez por cambio, no en cada lectura.
  void _actualizar() {
    var cantidad = 0;
    var total = 0.0;
    for (final item in _items) {
      cantidad += item.quantity;
      total += item.totalPrice;
    }
    _itemCount = cantidad;
    _totalAmount = total;
    notifyListeners();
  }

  void addItem(Map<String, dynamic> product) {
    final String itemId = '${product['title']}_${product['textura'] ?? 'default'}';
    final existingIndex = _items.indexWhere((item) => item.id == itemId);

    if (existingIndex >= 0) {
      _items[existingIndex].quantity++;
    } else {
      _items.add(CartItem(
        id: itemId,
        title: product['title']!,
        price: CartItem.parsePrice(product['price']),
        originalPrice: CartItem.parsePrice(product['originalPrice']),
        image: product['image']!,
        description: product['description']!,
        codigoSap: product['codigoSap'] ?? product['title']!,
        textura: product['textura'],
      ));
    }
    _actualizar();
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
