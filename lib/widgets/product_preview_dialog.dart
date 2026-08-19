import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/price_utils.dart';
import '../services/Sap_service.dart' as sap;

class ProductPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, Map<String, dynamic>> preciosSAP;
  final Map<String, Map<String, dynamic>> estadosSAP;
  final Function(Map<String, dynamic>) onAddToCart;
  final Function(Map<String, dynamic>) onShowTextureSelection;

  const ProductPreviewDialog({
    super.key,
    required this.product,
    required this.preciosSAP,
    required this.estadosSAP,
    required this.onAddToCart,
    required this.onShowTextureSelection,
  });

  @override
  Widget build(BuildContext context) {
    final codigoSap = product['codigoSap'] ?? '';
    final precioSAP = codigoSap.isNotEmpty ? _obtenerPrecioSAP(codigoSap) : null;
    final precioMostrar = (precioSAP != null && precioSAP != 'Precio no disponible')
        ? PriceUtils.formatPriceDisplay(precioSAP)
        : product['price']!;
    final disponible = _productoDisponible(codigoSap);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: context.responsive(16),
        vertical: context.responsive(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(context.responsive(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageHeader(context, disponible),
                    Padding(
                      padding: EdgeInsets.all(context.responsive(24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProductInfo(context, precioMostrar, disponible),
                          SizedBox(height: context.responsive(24)),
                          _buildFeatures(context),
                          SizedBox(height: context.responsive(24)),
                          _buildSpecifications(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(context, disponible),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeader(BuildContext context, bool disponible) {
    return Stack(
      children: [
        Container(
          height: context.responsive(300),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(context.responsive(28)),
            ),
          ),
          child: Hero(
            tag: 'product_${product['codigoSap'] ?? product['title']}',
            child: Padding(
              padding: EdgeInsets.all(context.responsive(32)),
              child: Image.asset(
                product['image'] ?? '',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 80, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: AppTheme.textPrimary, size: 20),
            ),
          ),
        ),
        if (!disponible)
          Container(
            height: context.responsive(300),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(context.responsive(28)),
              ),
            ),
            child: const Center(
              child: Icon(Icons.block_rounded, color: Colors.white, size: 60),
            ),
          ),
      ],
    );
  }

  Widget _buildProductInfo(BuildContext context, String precioMostrar, bool disponible) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                product['codigoSap'] ?? 'N/A',
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
            const SizedBox(width: 4),
            Text(
              product['rating'] ?? '5.0',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        SizedBox(height: context.responsive(16)),
        Text(
          product['title'] ?? '',
          style: TextStyle(
            fontSize: context.clampFont(20, 28, 24),
            fontWeight: FontWeight.w900,
            color: disponible ? AppTheme.textPrimary : AppTheme.textSecondary,
            height: 1.2,
          ),
        ),
        SizedBox(height: context.responsive(12)),
        Text(
          product['description'] ?? '',
          style: TextStyle(
            fontSize: context.clampFont(14, 18, 16),
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.responsive(24)),
        _buildPriceBreakdown(context, precioMostrar, disponible),
      ],
    );
  }

  Widget _buildPriceBreakdown(BuildContext context, String precioMostrar, bool disponible) {
    final conIVA = _parsePrecioNumerico(precioMostrar);
    final sinIVA = conIVA / 1.19;
    final iva = conIVA - sinIVA;

    return Container(
      padding: EdgeInsets.all(context.responsive(16)),
      decoration: BoxDecoration(
        color: AppTheme.lightBlue.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          _priceRow('Precio sin IVA', PriceUtils.formatPriceDisplay(sinIVA), false),
          const SizedBox(height: 8),
          _priceRow('IVA (19%)', PriceUtils.formatPriceDisplay(iva), false),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total con IVA',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                precioMostrar,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: disponible ? AppTheme.primaryBlue : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, bool bold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatures(BuildContext context) {
    final features = product['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Caractersticas Principales',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: context.responsive(12)),
        ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature.toString(),
                      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildSpecifications(BuildContext context) {
    final specs = product['specifications'] as Map<dynamic, dynamic>? ?? {};
    if (specs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Especificaciones Tcnicas',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: context.responsive(12)),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: Column(
            children: specs.entries
                .map((entry) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              entry.key.toString(),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              entry.value.toString(),
                              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool disponible) {
    return Container(
      padding: EdgeInsets.all(context.responsive(20)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(context.responsive(28))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppTheme.primaryBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: disponible
                  ? () {
                      if (product['hasTextureOptions'] == true) {
                        onShowTextureSelection(product);
                      } else {
                        onAddToCart(product);
                        Navigator.of(context).pop();
                      }
                    }
                  : null,
              icon: Icon(disponible ? Icons.add_shopping_cart_rounded : Icons.block_rounded),
              label: Text(disponible ? 'Agregar' : 'No Disponible'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _obtenerPrecioSAP(String codigoSap) {
    if (preciosSAP.containsKey(codigoSap)) {
      final precio = preciosSAP[codigoSap]!['precio'];
      return sap.InvoiceService1.formatearPrecioSAP(precio);
    }
    return null;
  }

  bool _productoDisponible(String codigoSap) {
    if (estadosSAP.containsKey(codigoSap)) {
      final estado = estadosSAP[codigoSap]!;
      final disponible = estado['disponible'] ?? true;
      final stock = estado['stock'] ?? 0;
      return disponible == true && (stock is num ? stock > 0 : true);
    }
    return true;
  }

  double _parsePrecioNumerico(String precioStr) {
    try {
      String s = precioStr.replaceAll(RegExp(r'[^\d.]'), '').trim();
      return double.tryParse(s) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
