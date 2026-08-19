import 'package:flutter/material.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';

/// Título de AppBar con el logo de Oral-Plus al lado del enunciado.
/// Úsalo como `title:` en el AppBar de todas las pantallas para mantener
/// la identidad de la empresa siempre visible.
class AppBarTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double logoHeight;

  const AppBarTitle(this.title, {super.key, this.subtitle, this.logoHeight = 30});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          AppAssets.logo,
          height: logoHeight,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.medical_services_rounded, size: logoHeight, color: AppTheme.primaryBlue),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.darkBlue, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
