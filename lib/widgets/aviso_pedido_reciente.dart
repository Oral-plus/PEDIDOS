import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/price_utils.dart';
import 'app_dialog.dart';

/// Código con el que el servidor rechaza un pedido repetido.
const String codigoPedidoReciente = 'PEDIDO_RECIENTE';

/// Cuenta atrás viva: el gestor ve bajar el tiempo en vez de un número muerto.
String tiempoRestante(int segundos) {
  if (segundos <= 0) return 'Ya puedes registrarlo';
  final min = segundos ~/ 60;
  final seg = segundos % 60;
  return '$min:${seg.toString().padLeft(2, '0')}';
}

/// Avisa que ya se le registró un pedido a ese cliente hace muy poco.
///
/// Se alimenta de lo que respondió el servidor —él es quien lleva la cuenta—,
/// y la ventana se cierra sola cuando el tiempo llega a cero.
Future<void> mostrarAvisoPedidoReciente(
  BuildContext context,
  Map<String, dynamic> respuesta,
) {
  final segundos = (respuesta['segundosRestantes'] as num?)?.toInt() ?? 0;
  final previo = respuesta['pedidoPrevio'] is Map
      ? Map<String, dynamic>.from(respuesta['pedidoPrevio'] as Map)
      : const <String, dynamic>{};

  HapticFeedback.heavyImpact();
  return showAppDialog<void>(
    context,
    barrierDismissible: false,
    child: _AvisoPedidoReciente(
      segundos: segundos,
      mensaje: (respuesta['message'] ?? '').toString(),
      numeroPedido: (previo['numeroPedido'] ?? '').toString(),
      fecha: (previo['fecha'] ?? '').toString(),
      total: (previo['total'] as num?)?.toDouble(),
    ),
  );
}

class _AvisoPedidoReciente extends StatefulWidget {
  final int segundos;
  final String mensaje;
  final String numeroPedido;
  final String fecha;
  final double? total;

  const _AvisoPedidoReciente({
    required this.segundos,
    required this.mensaje,
    required this.numeroPedido,
    required this.fecha,
    this.total,
  });

  @override
  State<_AvisoPedidoReciente> createState() => _AvisoPedidoRecienteState();
}

class _AvisoPedidoRecienteState extends State<_AvisoPedidoReciente> {
  static const Color _ink = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _ambar = Color(0xFFB45309);

  late final ValueNotifier<int> _restantes = ValueNotifier<int>(widget.segundos);
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      final quedan = _restantes.value - 1;
      _restantes.value = quedan;
      if (quedan > 0) return;
      t.cancel();
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _restantes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      icon: Icons.timer_outlined,
      accent: _ambar,
      title: 'Pedido repetido',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          widget.mensaje.isEmpty
              ? 'Ya le registraste un pedido a este cliente hace muy poco.'
              : widget.mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _gray, fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: _restantes,
          builder: (_, quedan, __) => Text(
            tiempoRestante(quedan),
            style: const TextStyle(color: _ambar, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ),
        if (widget.numeroPedido.isNotEmpty || widget.total != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _ambar.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              const Text('PEDIDO YA REGISTRADO',
                  style: TextStyle(color: _ambar, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(
                [
                  if (widget.numeroPedido.isNotEmpty) widget.numeroPedido,
                  if (widget.total != null) '\$${PriceUtils.formatPrice(widget.total)}',
                  if (widget.fecha.isNotEmpty) widget.fecha,
                ].join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ],
      ]),
      actions: [
        appDialogAction(
          context,
          text: 'Entendido',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
