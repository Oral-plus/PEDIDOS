import 'dart:ui';
import 'package:flutter/material.dart';

/// Overlay de carga premium: blur, gradiente, accesibilidad y feedback háptico.
class LoadingOverlay extends StatefulWidget {
  final bool isLoading;
  final Widget child;
  final String? message;
  final String? subtitle;
  final Color? backgroundColor;
  final Color? indicatorColor;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.subtitle,
    this.backgroundColor,
    this.indicatorColor,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.indicatorColor ?? theme.primaryColor;

    return Stack(
      children: [
        widget.child,
        if (widget.isLoading)
          Semantics(
            label: widget.message ?? 'Cargando',
            value: widget.subtitle,
            child: GestureDetector(
              onTap: () {}, // Bloquear toques
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (widget.backgroundColor ?? Colors.black).withOpacity(0.6),
                          (widget.backgroundColor ?? Colors.black87).withOpacity(0.75),
                        ],
                      ),
                    ),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: child,
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 28,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withOpacity(0.2),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                                ),
                              ),
                              if (widget.message != null) ...[
                                const SizedBox(height: 20),
                                Text(
                                  widget.message!,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1e293b),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Widget de overlay de carga simple
class SimpleLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const SimpleLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: isLoading,
      message: 'Cargando...',
      child: child,
    );
  }
}

// Widget de overlay para procesamiento de compras
class PurchaseLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const PurchaseLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: isLoading,
      message: 'Procesando compra...\nPor favor espera',
      backgroundColor: Colors.black.withOpacity(0.7),
      indicatorColor: Colors.blue,
      child: child,
    );
  }
}
