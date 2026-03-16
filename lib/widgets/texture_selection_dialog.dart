import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/product_utils.dart';

class TextureSelectionDialog extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, Map<String, dynamic>> preciosSAP;
  final Map<String, Map<String, dynamic>> estadosSAP;
  final Function(Map<String, dynamic>) onAddToCart;

  const TextureSelectionDialog({
    super.key,
    required this.product,
    required this.preciosSAP,
    required this.estadosSAP,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildOption(
                context,
                texture: product['category'] == 'Cepillos' ? 'Media' : product['textura']!,
                codigoSap: product['codigoSap']!,
                isPrimary: true,
              ),
              const SizedBox(height: 16),
              _buildOption(
                context,
                texture: product['category'] == 'Cepillos' ? 'Suave' : product['texturaAlternativa']!,
                codigoSap: product['category'] == 'Cepillos'
                    ? product['codigoSapSuave']!
                    : product['codigoSapAlternativo']!,
                isPrimary: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15), width: 2),
          ),
          child: const Icon(Icons.design_services_rounded, color: AppTheme.primaryBlue, size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          'Selecciona tu opción',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          product['title']!,
          style: const TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String texture,
    required String codigoSap,
    required bool isPrimary,
  }) {
    final disponible = _productoDisponible(codigoSap);
    final accentColor = isPrimary ? AppTheme.primaryBlue : AppTheme.secondaryBlue;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: disponible
            ? (isPrimary ? AppTheme.lightBlue.withOpacity(0.6) : Colors.white)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(context.responsive(18)),
        border: Border.all(
          color: disponible
              ? accentColor.withOpacity(isPrimary ? 0.25 : 0.15)
              : Colors.grey.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: disponible
            ? [
                BoxShadow(
                  color: accentColor.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.responsive(18)),
          onTap: disponible
              ? () {
                  final productWithTexture = Map<String, dynamic>.from(product);
                  productWithTexture['textura'] = texture;
                  productWithTexture['codigoSap'] = codigoSap;
                  Navigator.pop(context);
                  onAddToCart(productWithTexture);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: disponible ? accentColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPrimary ? Icons.star_rounded : Icons.label_rounded,
                    color: disponible ? accentColor : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texture,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: disponible ? AppTheme.textPrimary : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ProductUtils.getTextureDescription(texture, product['category']),
                        style: TextStyle(
                          fontSize: 12,
                          color: disponible ? AppTheme.textSecondary : Colors.grey,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!disponible)
                  const Icon(Icons.block_rounded, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
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
}
