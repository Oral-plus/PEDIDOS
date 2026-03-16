import 'package:intl/intl.dart';

class PriceUtils {
  /// Para formatear nmeros planos sin smbolo (usado en clculos internos)
  static String formatPrice(dynamic price) {
    if (price == null) return '0.00';
    final number = double.tryParse(price.toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    return NumberFormat('#,##0.##', 'es_CO').format(number);
  }

  /// Para mostrar precio con smbolo en UI (siempre con 2 decimales)
  static String formatPriceDisplay(dynamic price) {
    if (price == null) return '\$0.00';
    final number = double.tryParse(price.toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    return '\$${NumberFormat('#,##0.00', 'es_CO').format(number)}';
  }
}
