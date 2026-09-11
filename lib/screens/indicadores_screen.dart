import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'historial_pagos_screen.dart';
import 'historial_pedidos_screen.dart';

class IndicadoresScreen extends StatelessWidget {
  const IndicadoresScreen({super.key});

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _azul = Color(0xFF1A56DB);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const Text('Indicadores',
            style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text('Seguimiento de tu gestión',
              style: TextStyle(color: _gray, fontSize: 13.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          _tarjeta(
            context,
            icono: Icons.receipt_long_rounded,
            titulo: 'Historial de pagos',
            detalle: 'Todos los recaudos que has registrado',
            color: _azul,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistorialPagosScreen()),
              );
            },
          ),
          _tarjeta(
            context,
            icono: Icons.fact_check_rounded,
            titulo: 'Historial de pedidos',
            detalle: 'Estado de cada pedido: enviado, bloqueado o nuevo',
            color: _inkDeep,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistorialPedidosScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String detalle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icono, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo,
                      style: const TextStyle(color: _inkDeep, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 3),
                  Text(detalle,
                      style: const TextStyle(color: _gray, fontSize: 12.5, fontWeight: FontWeight.w500)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: _gray),
            ]),
          ),
        ),
      ),
    );
  }
}
