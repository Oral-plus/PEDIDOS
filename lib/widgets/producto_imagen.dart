import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProductoImagen extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final int cacheWidth;
  final double iconSize;
  final Color iconColor;
  final IconData icon;

  const ProductoImagen({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.cacheWidth = 400,
    this.iconSize = 32,
    this.iconColor = const Color(0xFF9CA3AF),
    this.icon = Icons.shopping_bag_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final u = url ?? '';
    if (u.isEmpty) return _icono();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, __, ___) => _icono());
    }
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => Center(
        child: SizedBox(
          width: iconSize * 0.5,
          height: iconSize * 0.5,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: iconColor),
        ),
      ),
      errorWidget: (_, __, ___) => _icono(),
    );
  }

  Widget _icono() => Center(child: Icon(icon, color: iconColor, size: iconSize));
}
