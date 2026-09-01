import 'package:intl/intl.dart';

class CartItem {
  final String id;
  final String title;
  final double price;
  final double originalPrice;
  final String image;
  final String description;
  final String codigoSap;
  final String? textura;
  int quantity;

  CartItem({
    required this.id,
    required this.title,
    required this.price,
    required this.originalPrice,
    required this.image,
    required this.description,
    required this.codigoSap,
    this.textura,
    this.quantity = 1,
  });

  static double parsePrice(dynamic val) {
    if (val is num) return val.toDouble();
    if (val == null) return 0.0;
    
    String s = val.toString().replaceAll(RegExp(r'[^\d.,]'), '').trim();
    if (s.isEmpty) return 0.0;
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    } else if (s.contains('.')) {
      String after = s.substring(s.lastIndexOf('.') + 1);
      if (after.length > 2) s = s.replaceAll('.', '');
    }
    return double.tryParse(s) ?? 0.0;
  }

  double get totalPrice => price * quantity;

  double get totalOriginalPrice => originalPrice * quantity;

  double get discount {
    if (originalPrice <= 0) return 0.0;
    return originalPrice - price;
  }

  double get discountPercentage {
    if (originalPrice <= 0) return 0.0;
    return (discount / originalPrice) * 100;
  }

  double get totalDiscount => discount * quantity;

  bool get hasDiscount => discount > 0;

  static final NumberFormat _fmt = NumberFormat('#,##0.00', 'es_CO');

  String get formattedPrice {
    return '\$${_fmt.format(price)}';
  }

  String get formattedOriginalPrice {
    if (originalPrice <= 0) return '';
    return '\$${_fmt.format(originalPrice)}';
  }

  String get formattedTotalPrice {
    return '\$${_fmt.format(totalPrice)}';
  }

  String get formattedDiscount {
    if (!hasDiscount) return '';
    return '\$${discount.toStringAsFixed(2)}';
  }

  String get formattedDiscountPercentage {
    if (!hasDiscount) return '';
    return '${discountPercentage.toStringAsFixed(0)}% OFF';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'originalPrice': originalPrice,
      'image': image,
      'description': description,
      'codigoSap': codigoSap,
      'textura': textura,
      'quantity': quantity,
      'totalPrice': totalPrice,
      'discount': discount,
      'hasDiscount': hasDiscount,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: parsePrice(json['price']),
      originalPrice: parsePrice(json['originalPrice']),
      image: json['image']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      codigoSap: json['codigoSap']?.toString() ?? '',
      textura: json['textura']?.toString(),
      quantity: json['quantity'] is int ? json['quantity'] : int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
    );
  }

  CartItem copyWith({
    String? id,
    String? title,
    double? price,
    double? originalPrice,
    String? image,
    String? description,
    String? codigoSap,
    String? textura,
    int? quantity,
  }) {
    return CartItem(
      id: id ?? this.id,
      title: title ?? this.title,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      image: image ?? this.image,
      description: description ?? this.description,
      codigoSap: codigoSap ?? this.codigoSap,
      textura: textura ?? this.textura,
      quantity: quantity ?? this.quantity,
    );
  }

  CartItem incrementQuantity() {
    return copyWith(quantity: quantity + 1);
  }

  CartItem decrementQuantity() {
    if (quantity <= 1) return this;
    return copyWith(quantity: quantity - 1);
  }

  CartItem setQuantity(int newQuantity) {
    if (newQuantity < 1) return this;
    return copyWith(quantity: newQuantity);
  }

  bool get isValid {
    return id.isNotEmpty && 
           title.isNotEmpty && 
           codigoSap.isNotEmpty && 
           price > 0 && 
           quantity > 0;
  }

  String get summary {
    final discountInfo = hasDiscount ? ' ($formattedDiscountPercentage)' : '';
    return '$title - $formattedPrice x$quantity$discountInfo';
  }

  @override
  String toString() {
    return 'CartItem('
        'id: $id, '
        'title: $title, '
        'price: $price, '
        'quantity: $quantity, '
        'codigoSap: $codigoSap, '
        'totalPrice: $formattedTotalPrice'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CartItem && 
           other.id == id && 
           other.codigoSap == codigoSap;
  }

  @override
  int get hashCode => Object.hash(id, codigoSap);

  String toDebugString() {
    return '''
CartItem Debug Info:
  ID: $id
  Title: $title
  CodigoSAP: $codigoSap
  Price: $price
  Original Price: $originalPrice
  Quantity: $quantity
  Total Price: $formattedTotalPrice
  Discount: $formattedDiscount ($formattedDiscountPercentage)
  Has Discount: $hasDiscount
  Is Valid: $isValid
  Textura: ${textura ?? 'N/A'}
  Image: $image
  Description: ${description.length > 50 ? '${description.substring(0, 50)}...' : description}
''';
  }
}
