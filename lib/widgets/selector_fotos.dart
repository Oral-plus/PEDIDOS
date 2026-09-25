import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Campo para adjuntar fotos: miniaturas, botón para agregar y tope de imágenes.
///
/// Lo usan las pantallas que piden evidencia fotográfica, para que adjuntar una
/// foto se vea y se comporte igual en toda la app.
class SelectorFotos extends StatelessWidget {
  final List<XFile> fotos;
  final int maximo;
  final bool habilitado;
  final ValueChanged<List<XFile>> onCambio;
  final String textoVacio;
  final String textoAgregar;

  const SelectorFotos({
    super.key,
    required this.fotos,
    required this.onCambio,
    this.maximo = 3,
    this.habilitado = true,
    this.textoVacio = 'Adjuntar foto',
    this.textoAgregar = 'Agregar otra foto',
  });

  static const Color _ink = Color(0xFF111827);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _rojo = Color(0xFFDC2626);

  static final ImagePicker _picker = ImagePicker();

  /// Pregunta cámara o galería y devuelve las imágenes elegidas (máximo [restantes]).
  static Future<List<XFile>> elegir(BuildContext context, {required int restantes}) async {
    if (restantes <= 0) return const [];
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: _ink),
            title: const Text('Tomar foto', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: _ink),
            title: const Text('Elegir de galería', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(restantes == 1 ? 'Puedes elegir 1 imagen más' : 'Hasta $restantes imágenes',
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (fuente == null) return const [];
    try {
      if (fuente == ImageSource.camera || restantes == 1) {
        final foto = await _picker.pickImage(source: fuente, imageQuality: 70, maxWidth: 1600);
        return foto == null ? const [] : [foto];
      }
      final nuevas = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600, limit: restantes);
      return nuevas.take(restantes).toList();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _rojo,
          content: Text('No se pudo abrir ${fuente == ImageSource.camera ? 'la cámara' : 'la galería'}'),
        ));
      }
      return const [];
    }
  }

  Future<void> _agregar(BuildContext context) async {
    final nuevas = await elegir(context, restantes: maximo - fotos.length);
    if (nuevas.isEmpty) return;
    onCambio([...fotos, ...nuevas]);
  }

  @override
  Widget build(BuildContext context) {
    final puedeAgregar = habilitado && fotos.length < maximo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (fotos.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < fotos.length; i++) _miniatura(i),
        ]),
        const SizedBox(height: 6),
        Text('${fotos.length} de $maximo imágenes adjuntas',
            style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
      ],
      if (puedeAgregar)
        OutlinedButton.icon(
          onPressed: () => _agregar(context),
          icon: const Icon(Icons.add_a_photo_rounded, size: 18),
          label: Text(fotos.isEmpty ? textoVacio : textoAgregar,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ink,
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
    ]);
  }

  Widget _miniatura(int i) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(fotos[i].path),
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                    width: 76,
                    height: 76,
                    color: _line,
                    child: const Icon(Icons.broken_image_rounded, color: _gray),
                  )),
        ),
        if (habilitado)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => onCambio([...fotos]..removeAt(i)),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
      ]);
}
