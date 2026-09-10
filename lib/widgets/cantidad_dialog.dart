import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_dialog.dart';

const Color _ink = Color(0xFF0F172A);
const Color _inkSoft = Color(0xFF1E293B);
const Color _gray = Color(0xFF64748B);
const Color _grayLight = Color(0xFF94A3B8);
const Color _line = Color(0xFFE2E8F0);

const int cantidadMaxima = 9999;

Future<int?> showCantidadDialog(
  BuildContext context, {
  required String producto,
  int cantidadInicial = 1,
}) {
  return showAppDialog<int>(
    context,
    barrierDismissible: false,
    child: _CantidadDialog(producto: producto, cantidadInicial: cantidadInicial),
  );
}

class _CantidadDialog extends StatefulWidget {
  final String producto;
  final int cantidadInicial;

  const _CantidadDialog({required this.producto, required this.cantidadInicial});

  @override
  State<_CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends State<_CantidadDialog> {
  late final TextEditingController _ctrl;
  late int _cantidad;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.cantidadInicial < 1 ? 1 : widget.cantidadInicial;
    _ctrl = TextEditingController(text: '$_cantidad');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _fijar(int valor) {
    final nuevo = valor.clamp(1, cantidadMaxima);
    setState(() => _cantidad = nuevo);
    _ctrl.value = TextEditingValue(
      text: '$nuevo',
      selection: TextSelection.collapsed(offset: '$nuevo'.length),
    );
  }

  void _paso(int delta) {
    HapticFeedback.selectionClick();
    _fijar(_cantidad + delta);
  }

  void _confirmar() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_cantidad);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      icon: Icons.numbers_rounded,
      title: '¿Cuántas unidades?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.producto,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gray, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _boton(Icons.remove_rounded, _cantidad > 1 ? () => _paso(-1) : null),
              const SizedBox(width: 14),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1) {
                      setState(() => _cantidad = n.clamp(1, cantidadMaxima));
                    }
                  },
                  onSubmitted: (_) => _confirmar(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.7),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _ink, width: 1.6)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _boton(Icons.add_rounded, _cantidad < cantidadMaxima ? () => _paso(1) : null),
            ],
          ),
        ],
      ),
      actions: [
        appDialogCancel(context),
        const SizedBox(width: 12),
        appDialogAction(context, text: 'Agregar', onPressed: _confirmar),
      ],
    );
  }

  Widget _boton(IconData icono, VoidCallback? onTap) {
    final habilitado = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: habilitado ? const LinearGradient(colors: [_inkSoft, _ink]) : null,
            color: habilitado ? null : _line,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icono, color: habilitado ? Colors.white : _grayLight, size: 24),
        ),
      ),
    );
  }
}
