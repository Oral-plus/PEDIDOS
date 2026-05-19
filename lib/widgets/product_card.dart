import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/price_utils.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Color themeColor;
  final Map<String, dynamic> preciosSAP;
  final Map<String, dynamic> estadosSAP;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const ProductCard({
    super.key,
    required this.product,
    required this.themeColor,
    this.preciosSAP = const {},
    this.estadosSAP = const {},
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final codigo = product['codigoSap']?.toString() ?? '';

    final precioSAP = preciosSAP[codigo];
    final estadoSAP = estadosSAP[codigo];

    String? estadoString;
    if (estadoSAP is Map) {
      estadoString = (estadoSAP['estado'] ?? estadoSAP['status'])?.toString();
    } else if (estadoSAP != null) {
      estadoString = estadoSAP.toString();
    }
    final bool disponible = (estadoString != null)
        ? (estadoString.toUpperCase() == 'DISPONIBLE')
        : (product['disponible'] ?? true);

    num? precioNum;
    if (precioSAP is num) {
      precioNum = precioSAP;
    } else if (precioSAP is Map) {
      final raw = precioSAP['precio'] ?? precioSAP['price'] ?? precioSAP['value'];
      if (raw is num) {
        precioNum = raw;
      } else if (raw != null) {
        precioNum = num.tryParse(raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), ''));
      }
    } else if (precioSAP is String) {
      precioNum = num.tryParse(precioSAP.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    }

    final String precioMostrar = (precioNum != null)
        ? PriceUtils.formatPriceDisplay(precioNum.toDouble())
        : (product['price']?.toString() ?? '\$0');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.responsive(16)),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 5,
              child: _buildProductImage(context, disponible),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.responsive(10),
                context.responsive(8),
                context.responsive(10),
                context.responsive(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product['title'] ?? 'Producto',
                    style: TextStyle(
                      color: disponible ? AppTheme.darkBlue : AppTheme.textSecondary,
                      fontSize: context.clampFont(10, 14, 11),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: context.responsive(6)),
                  Text(
                    precioMostrar,
                    style: TextStyle(
                      color: disponible ? themeColor : AppTheme.textSecondary,
                      fontSize: context.clampFont(13, 17, 14),
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: context.responsive(8)),
                  _buildAddButton(context, disponible),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(BuildContext context, bool disponible) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.lightBlue,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.responsive(16)),
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Hero(
              tag: 'product_${product['codigoSap'] ?? product['title']}',
              child: Opacity(
                opacity: disponible ? 1.0 : 0.5,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset(
                    product['image'] ?? '',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.image_not_supported_outlined,
                      color: AppTheme.textSecondary,
                      size: context.responsive(40),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (product['rating'] != null)
            Positioned(
              top: context.responsive(8),
              right: context.responsive(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      product['rating'],
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!disponible)
            Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(context.responsive(16)),
                ),
              ),
              child: const Center(
                child: Icon(Icons.block_rounded, color: Colors.white, size: 40),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, bool disponible) {
    return SizedBox(
      width: double.infinity,
      height: context.responsive(34).clamp(32.0, 38.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.responsive(10)),
          onTap: disponible ? onAddToCart : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: disponible
                  ? LinearGradient(colors: [themeColor, themeColor.withOpacity(0.85)])
                  : LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade300]),
              borderRadius: BorderRadius.circular(context.responsive(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  disponible ? Icons.add_shopping_cart_rounded : Icons.block_rounded,
                  color: Colors.white,
                  size: context.responsive(15),
                ),
                SizedBox(width: context.responsive(5)),
                Text(
                  disponible ? 'Agregar' : 'No Disponible',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.clampFont(10, 13, 11),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
