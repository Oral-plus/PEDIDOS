import 'package:flutter/material.dart';
import '../models/cart_item.dart';

import '../utils/price_utils.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount => _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  String get formattedTotal => PriceUtils.formatPriceDisplay(totalAmount);
  String get formattedTotalSinIva => PriceUtils.formatPriceDisplay(totalAmount / 1.19);
  String get formattedIVA => PriceUtils.formatPriceDisplay(totalAmount - (totalAmount / 1.19));

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
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void updateQuantity(String id, int quantity) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
