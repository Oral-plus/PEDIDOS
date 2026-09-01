import 'package:intl/intl.dart';

class PriceUtils {
  static final RegExp _noNumerico = RegExp(r'[^\d.]');
  static final NumberFormat _fmtCorto = NumberFormat('#,##0.##', 'es_CO');
  static final NumberFormat _fmtDisplay = NumberFormat('#,##0.00', 'es_CO');

  static double _aDouble(dynamic price) {
    if (price is num) return price.toDouble();
    return double.tryParse(price.toString().replaceAll(_noNumerico, '')) ?? 0.0;
  }

  static String formatPrice(dynamic price) {
    if (price == null) return '0.00';
    return _fmtCorto.format(_aDouble(price));
  }

  static String formatPriceDisplay(dynamic price) {
    if (price == null) return '\$0.00';
    return '\$${_fmtDisplay.format(_aDouble(price))}';
  }
}
