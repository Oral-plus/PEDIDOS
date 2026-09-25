import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/tarea.dart';
import '../services/api_easy_service.dart';
import 'selector_fotos.dart';

/// Responder una tarea: comentario, fotos y el aviso de que quedó registrada.
///
/// Es el único camino para responder una tarea, lo mismo desde el módulo de
/// Tareas que desde la visita del cliente.
class ResponderTarea {
  const ResponderTarea._();

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _rojo = Color(0xFFDC2626);
  static const int maxFotos = 3;

  /// Abre el formulario y devuelve lo que quedó guardado, o null si no se guardó.
  ///
  /// [clienteCodigo] se pasa desde la visita, donde ya se sabe en qué cliente
  /// está el gestor. Desde el módulo de Tareas se deduce o se pregunta.
  static Future<RespuestaTarea?> mostrar(
    BuildContext context, {
    required ApiEasyService api,
    required Tarea tarea,
    String? clienteCodigo,
    int? visitaId,
  }) async {
    HapticFeedback.selectionClick();
    final cliente = await _resolverCliente(context, tarea, clienteCodigo);
    if (cliente == null || !context.mounted) return null;

    final respuesta = await showModalBottomSheet<RespuestaTarea>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _HojaRespuesta(api: api, tarea: tarea, clienteCodigo: cliente, visitaId: visitaId),
    );
    if (respuesta == null || !context.mounted) return respuesta;

    await _avisoExito(context);
    return respuesta;
  }

  /// El código del cliente al que se le responde la tarea.
  static Future<String?> _resolverCliente(BuildContext context, Tarea tarea, String? dado) async {
    if (dado != null && dado.trim().isNotEmpty) return dado.trim();
    final unico = tarea.clienteUnico;
    if (unico != null) return unico.codigo;
    if (tarea.clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esta tarea no está asociada a un cliente'),
      ));
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('¿Para cuál cliente?',
            style: TextStyle(color: _inkDeep, fontSize: 16, fontWeight: FontWeight.w800)),
        children: [
          for (final c in tarea.clientes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(c.codigo),
              child: Row(children: [
                const Icon(Icons.storefront_rounded, size: 18, color: _gray),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.etiqueta,
                      style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  static Future<void> _avisoExito(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: _verde.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: _verde, size: 34),
          ),
          const SizedBox(height: 14),
          const Text('Tarea realizada exitosamente',
              textAlign: TextAlign.center,
              style: TextStyle(color: _inkDeep, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _HojaRespuesta extends StatefulWidget {
  final ApiEasyService api;
  final Tarea tarea;
  final String clienteCodigo;
  final int? visitaId;

  const _HojaRespuesta({
    required this.api,
    required this.tarea,
    required this.clienteCodigo,
    this.visitaId,
  });

  @override
  State<_HojaRespuesta> createState() => _HojaRespuestaState();
}

class _HojaRespuestaState extends State<_HojaRespuesta> {
  final TextEditingController _observacion = TextEditingController();
  final List<XFile> _fotos = [];
  bool _cumplida = true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _observacion.dispose();
    super.dispose();
  }

  BorradorRespuestaTarea get _borrador => BorradorRespuestaTarea(
        cumplida: _cumplida,
        observacion: _observacion.text,
        fotos: _fotos.map((f) => f.path).toList(),
      );

  Future<void> _guardar() async {
    if (_guardando || !_borrador.completo) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final respuesta = await widget.api.responderTarea(
      widget.tarea.id,
      clienteCodigo: widget.clienteCodigo,
      visitaId: widget.visitaId,
      borrador: _borrador,
    );
    if (!mounted) return;
    if (respuesta == null) {
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar la información de la tarea. Intenta de nuevo.';
      });
      return;
    }
    Navigator.of(context).pop(respuesta);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tarea;
    final completo = _borrador.completo;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: ResponderTarea._line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 14),
            Text(t.nombre,
                style: const TextStyle(color: ResponderTarea._inkDeep, fontSize: 17, fontWeight: FontWeight.w800)),
            if (t.descripcion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(t.descripcion,
                  style: const TextStyle(color: ResponderTarea._gray, fontSize: 13, height: 1.35)),
            ],
            const SizedBox(height: 4),
            Text(t.textoPlazo,
                style: TextStyle(
                    color: t.vencida ? ResponderTarea._rojo : ResponderTarea._gray,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('¿Se cumplió en este cliente?',
                style: TextStyle(color: ResponderTarea._ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(child: _opcion('Sí', true)),
              Expanded(child: _opcion('No', false)),
            ]),
            const SizedBox(height: 4),
            TextField(
              controller: _observacion,
              enabled: !_guardando,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14, color: ResponderTarea._ink),
              decoration: InputDecoration(
                labelText: _cumplida ? 'Comentario (opcional)' : 'Comentario (obligatorio)',
                hintText: _cumplida ? 'Qué se hizo en el cliente…' : 'Por qué no se pudo cumplir…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Text('Fotos de la tarea',
                style: TextStyle(color: ResponderTarea._ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectorFotos(
              fotos: _fotos,
              maximo: ResponderTarea.maxFotos,
              habilitado: !_guardando,
              textoVacio: 'Adjuntar foto',
              onCambio: (nuevas) => setState(() {
                _fotos
                  ..clear()
                  ..addAll(nuevas);
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: ResponderTarea._rojo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(color: ResponderTarea._rojo, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: _guardando ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: completo && !_guardando ? _guardar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ResponderTarea._inkDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _opcion(String texto, bool valor) => RadioListTile<bool>(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: valor,
        groupValue: _cumplida,
        title: Text(texto, style: const TextStyle(fontSize: 13.5)),
        onChanged: _guardando ? null : (v) => setState(() => _cumplida = v ?? valor),
      );
}
