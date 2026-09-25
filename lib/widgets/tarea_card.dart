import 'package:flutter/material.dart';

/// Tarjeta de una tarea. La usan el módulo de Tareas y la pantalla de visita,
/// para que una tarea se vea igual en los dos sitios.
class TareaCard extends StatelessWidget {
  final Map<String, dynamic> tarea;
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

  static String textoPlazo(Map<String, dynamic> tarea) {
    if (tarea['indefinido'] == true) return 'Sin fecha límite';
    final dias = (tarea['diasRestantes'] as num?)?.toInt();
    final fecha = (tarea['fechaLimite'] ?? '').toString();
    if (dias == null) return fecha.isEmpty ? 'Sin fecha límite' : 'Vence $fecha';
    if (dias < 0) return 'Vencida hace ${dias.abs()} día(s)';
    if (dias == 0) return 'Vence hoy';
    if (dias == 1) return 'Vence mañana';
    return 'Vence en $dias días';
  }

  static bool respondida(Map<String, dynamic> tarea) => tarea['respondida'] == true;

  Color get _colorPlazo {
    if (tarea['vencida'] == true) return _rojo;
    if (tarea['indefinido'] == true) return _gray;
    final dias = (tarea['diasRestantes'] as num?)?.toInt();
    if (dias != null && dias <= 3) return _ambar;
    return _gray;
  }

  @override
  Widget build(BuildContext context) {
    final pendiente = tarea['pendiente'] == true;
    final vencida = tarea['vencida'] == true;
    final respuesta = tarea['respuesta'] is Map ? Map<String, dynamic>.from(tarea['respuesta'] as Map) : null;
    final clientes = (tarea['clientes'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final descripcion = (tarea['descripcion'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vencida ? _rojo.withOpacity(0.4) : _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (pendiente ? _azul : _verde).withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(pendiente ? Icons.assignment_rounded : Icons.task_alt_rounded,
                color: pendiente ? _azul : _verde, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((tarea['nombre'] ?? '').toString(),
                  style: const TextStyle(color: _inkDeep, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(textoPlazo(tarea),
                  style: TextStyle(color: _colorPlazo, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (respondida(tarea))
            const Icon(Icons.check_circle_rounded, color: _verde, size: 20)
          else if (onResponder != null)
            const Icon(Icons.edit_note_rounded, color: _azul, size: 22),
        ]),
        if (descripcion.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(descripcion, style: const TextStyle(color: _ink, fontSize: 13, height: 1.35)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if ((tarea['area'] ?? '').toString().isNotEmpty) _chip((tarea['area']).toString(), _azul),
          _chip((tarea['estado'] ?? '').toString(), pendiente ? _ambar : _verde),
          if ((tarea['usuario'] ?? '').toString().isNotEmpty) _chip('Asignó ${tarea['usuario']}', _gray),
        ]),
        if (mostrarClientes && clientes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.storefront_rounded, size: 14, color: _gray),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                clientes.map((c) => c['nombre']?.toString().trim().isNotEmpty == true ? c['nombre'] : c['codigo']).join(' · '),
                style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
        if (respuesta != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _verde.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(respuesta['cumplida'] == true ? Icons.check_rounded : Icons.close_rounded,
                  size: 15, color: respuesta['cumplida'] == true ? _verde : _rojo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${respuesta['cumplida'] == true ? 'Cumplida' : 'No cumplida'}'
                  '${(respuesta['observacion'] ?? '').toString().trim().isEmpty ? '' : ' · ${respuesta['observacion']}'}',
                  style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
        if (onResponder != null && !respondida(tarea)) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onResponder,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Registrar información'),
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
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
