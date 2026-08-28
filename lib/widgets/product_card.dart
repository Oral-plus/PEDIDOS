import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/price_utils.dart';
import 'producto_imagen.dart';

class ProductCard extends StatefulWidget {
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
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _pressed = false;

  Map<String, dynamic> get product => widget.product;

  @override
  Widget build(BuildContext context) {
    final codigo = product['codigoSap']?.toString() ?? '';

    final precioSAP = widget.preciosSAP[codigo];
    final estadoSAP = widget.estadosSAP[codigo];

    String? estadoString;
    if (estadoSAP is Map) {
      estadoString = (estadoSAP['estado'] ?? estadoSAP['status'])?.toString();
    } else if (estadoSAP != null) {
      estadoString = estadoSAP.toString();
    }
    final bool disponible = (estadoString != null)
        ? (estadoString.toUpperCase() == 'DISPONIBLE')
        : (product['disponible'] ?? true);
    // Sin stock en bodega: se informa, pero el producto se puede pedir igual
    final stockSap = estadoSAP is Map ? estadoSAP['stock'] : null;
    final bool sinStock = disponible &&
        (stockSap is num ? stockSap <= 0 : product['sinStock'] == true);

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

    final String precioMostrar = !disponible
        ? 'Sin precio'
        : (precioNum != null)
            ? PriceUtils.formatPriceDisplay(precioNum.toDouble())
            : (product['price']?.toString() ?? '\$0');

    final radius = context.responsive(18);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white,
            border: Border.all(color: const Color(0xFFECECEE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_pressed ? 0.03 : 0.06),
                blurRadius: _pressed ? 10 : 18,
                offset: Offset(0, _pressed ? 4 : 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                flex: 5,
                child: _buildProductImage(context, disponible, sinStock),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.responsive(11),
                  context.responsive(9),
                  context.responsive(11),
                  context.responsive(11),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            precioMostrar,
                            style: TextStyle(
                              color: disponible ? AppTheme.darkBlue : AppTheme.textSecondary,
                              fontSize: context.clampFont(13, 17, 14),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: context.responsive(9)),
                    _buildAddButton(context, disponible),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(BuildContext context, bool disponible, bool sinStock) {
    final topRadius = BorderRadius.vertical(top: Radius.circular(context.responsive(18)));
    Widget img = Padding(
      padding: const EdgeInsets.all(10.0),
      child: ProductoImagen(
        url: product['image']?.toString(),
        // La tarjeta mide ~170 px: con 500 px de decodificación sobra
        cacheWidth: 500,
        icon: Icons.image_not_supported_outlined,
        iconColor: AppTheme.textSecondary,
        iconSize: context.responsive(40),
      ),
    );

    // Producto agotado -> imagen en escala de grises y atenuada.
    if (!disponible) {
      img = Opacity(
        opacity: 0.55,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: img,
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9FAFB), Color(0xFFEEF0F3)],
        ),
        borderRadius: topRadius,
      ),
      child: Stack(
        children: [
          Center(
            child: Hero(
              tag: 'product_${product['codigoSap'] ?? product['title']}',
              child: img,
            ),
          ),
          // Rating (arriba derecha)
          if (product['rating'] != null)
            Positioned(
              top: context.responsive(8),
              right: context.responsive(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFACC15), size: 13),
                    const SizedBox(width: 3),
                    Text(
                      product['rating'],
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Distintivo arriba a la izquierda: no se le vende a este cliente,
          // o se vende pero no hay stock en bodega
          if (!disponible || sinStock)
            Positioned(
              top: context.responsive(8),
              left: context.responsive(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: disponible ? const Color(0xFFB45309) : const Color(0xFF6B7280),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      disponible ? Icons.inventory_2_outlined : Icons.block_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      disponible ? 'SIN STOCK' : 'NO DISPONIBLE',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
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
          onTap: disponible ? widget.onAddToCart : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: disponible
                  ? LinearGradient(
                      colors: [widget.themeColor, widget.themeColor.withOpacity(0.82)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: disponible ? null : const Color(0xFFF1F2F4),
              borderRadius: BorderRadius.circular(context.responsive(10)),
              border: disponible ? null : Border.all(color: const Color(0xFFE1E3E7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  disponible ? Icons.add_shopping_cart_rounded : Icons.block_rounded,
                  color: disponible ? Colors.white : AppTheme.textSecondary,
                  size: context.responsive(15),
                ),
                SizedBox(width: context.responsive(5)),
                Text(
                  disponible ? 'Agregar' : 'No disponible',
                  style: TextStyle(
                    color: disponible ? Colors.white : AppTheme.textSecondary,
                    fontSize: context.clampFont(10, 13, 11),
                    fontWeight: FontWeight.w800,
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
