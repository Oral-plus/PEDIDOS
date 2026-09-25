import 'package:flutter/material.dart';

import '../models/tarea.dart';

/// Tarjeta de una tarea. La usan el módulo de Tareas y la pantalla de visita,
/// para que una tarea se vea igual en los dos sitios.
///
/// Con [onResponder], tocar la tarjeta abre el formulario para responderla.
class TareaCard extends StatelessWidget {
  final Tarea tarea;
  final VoidCallback? onResponder;
  final bool mostrarClientes;

  const TareaCard({
    super.key,
    required this.tarea,
    this.onResponder,
    this.mostrarClientes = true,
  });

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _ambar = Color(0xFFD97706);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _azul = Color(0xFF1A56DB);

  bool get _sePuedeResponder => onResponder != null && !tarea.respondida;

  Color get _colorPlazo {
    if (tarea.vencida) return _rojo;
    if (tarea.indefinido) return _gray;
    final dias = tarea.diasRestantes;
    if (dias != null && dias <= 3) return _ambar;
    return _gray;
  }

  @override
  Widget build(BuildContext context) {
    final tarjeta = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tarea.vencida ? _rojo.withOpacity(0.4) : _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (tarea.pendiente ? _azul : _verde).withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(tarea.pendiente ? Icons.assignment_rounded : Icons.task_alt_rounded,
                color: tarea.pendiente ? _azul : _verde, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tarea.nombre,
                  style: const TextStyle(color: _inkDeep, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(tarea.textoPlazo,
                  style: TextStyle(color: _colorPlazo, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (tarea.respondida)
            const Icon(Icons.check_circle_rounded, color: _verde, size: 20)
          else if (onResponder != null)
            const Icon(Icons.edit_note_rounded, color: _azul, size: 22),
        ]),
        if (tarea.descripcion.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tarea.descripcion, style: const TextStyle(color: _ink, fontSize: 13, height: 1.35)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (tarea.area.isNotEmpty) _chip(tarea.area, _azul),
          _chip(tarea.estado, tarea.pendiente ? _ambar : _verde),
          if (tarea.usuario.isNotEmpty) _chip('Asignó ${tarea.usuario}', _gray),
        ]),
        if (mostrarClientes && tarea.clientes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.storefront_rounded, size: 14, color: _gray),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tarea.clientes.map((c) => c.etiqueta).join(' · '),
                style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
        if (tarea.respuesta != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _verde.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(tarea.respuesta!.cumplida ? Icons.check_rounded : Icons.close_rounded,
                  size: 15, color: tarea.respuesta!.cumplida ? _verde : _rojo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tarea.respuesta!.resumen,
                    style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ],
        if (_sePuedeResponder) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onResponder,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Responder tarea'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _azul,
                side: const BorderSide(color: _azul),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ]),
    );

    if (!_sePuedeResponder) return tarjeta;
    return InkWell(
      onTap: onResponder,
      borderRadius: BorderRadius.circular(16),
      child: tarjeta,
    );
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
