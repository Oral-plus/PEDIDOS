import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/price_utils.dart';

/// Pantalla de gestión del pedido, que sigue a la forma de pago en la visita.
/// Opciones: Liquidación (subtotal/descuento/impuesto/flete/total),
/// Condiciones (forma de pago, plazo, fecha de entrega, observaciones),
/// Evidencias (fotos) y Guardar pedido.
/// Devuelve `true` por Navigator.pop si el pedido se guardó.
class GestionPedidoScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic> ruta;
  final Map<String, dynamic>? ultimoPedido;
  final Map<String, dynamic>? pago; // {metodo, banco, referencia, valor}
  final Map<String, dynamic>? cartera; // {limiteCredito, balance, ...}

  const GestionPedidoScreen({
    super.key,
    required this.cliente,
    required this.ruta,
    this.ultimoPedido,
    this.pago,
    this.cartera,
  });

  @override
  State<GestionPedidoScreen> createState() => _GestionPedidoScreenState();
}

class _GestionPedidoScreenState extends State<GestionPedidoScreen> {
  final ApiEasyService _api = ApiEasyService();
  final ImagePicker _picker = ImagePicker();

  // Paleta (igual que la forma de pago)
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);

  double _descuentoPct = 0; // porcentaje (0-100)
  double _flete = 0;

  // Monto del descuento calculado sobre el sub-total.
  double get _descuentoMonto => _subtotal * (_descuentoPct.clamp(0, 100)) / 100;
  int? _plazoDias;
  DateTime? _fechaEntrega;
  String _observaciones = '';
  final List<XFile> _evidencias = [];
  bool _guardando = false;

  String get _codigo => (widget.cliente['id'] ?? '').toString();

  String get _nombre =>
      (widget.cliente['nombre'] ?? widget.cliente['cardName'] ?? 'Cliente').toString();

  String get _numeroPedido =>
      (widget.ultimoPedido?['numeroPedido'] ?? widget.ultimoPedido?['numero_pedido'] ?? '').toString();

  double _n(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  double get _subtotal {
    final s = _n(widget.ultimoPedido?['subtotal']);
    if (s > 0) return s;
    final t = _n(widget.ultimoPedido?['total']);
    return t > 0 ? t / 1.19 : 0;
  }

  double get _impuesto {
    final i = _n(widget.ultimoPedido?['iva']);
    if (i > 0) return i;
    return _subtotal * 0.19;
  }

  double get _total => (_subtotal + _impuesto - _descuentoMonto + _flete).clamp(0, double.infinity);

  // ── Cupo (límite de crédito) del cliente ──────────────────────────────
  double get _cupoAsignado => _n(widget.cartera?['limiteCredito']);
  double get _saldoUsado => _n(widget.cartera?['balance']);
  double get _cupoDisponible => _cupoAsignado - _saldoUsado;
  bool get _excedeCupo => _cupoAsignado > 0 && _total > _cupoDisponible;

  String _pesos(num v) => PriceUtils.formatPriceDisplay(v.toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(children: [
        _header(),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            children: [
              _resumenLiquidacion(),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Gestión del pedido',
                    style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              _opcion(
                icon: Icons.calculate_rounded,
                titulo: 'Liquidación de pedido',
                sub: 'Descuento ${_descuentoPct.toStringAsFixed(0)}% · Flete ${_pesos(_flete)}',
                onTap: _abrirLiquidacion,
              ),
              _opcion(
                icon: Icons.assignment_rounded,
                titulo: 'Condiciones de pedido',
                sub: _condicionesResumen(),
                onTap: _abrirCondiciones,
              ),
              _opcion(
                icon: Icons.photo_camera_rounded,
                titulo: 'Evidencias',
                sub: _evidencias.isEmpty ? 'Sin evidencias' : '${_evidencias.length} foto(s)',
                onTap: _abrirEvidencias,
                trailingWidget: _evidencias.isEmpty
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(20)),
                        child: Text('${_evidencias.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
              ),
              if (_evidencias.isNotEmpty) _tiraEvidencias(),
            ],
          ),
        ),
        _footer(),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_ink, _inkDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 16),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Image.asset(AppAssets.logo, height: 22, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long_rounded, color: _ink, size: 20)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pedido', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Gestión y liquidación', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_nombre,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('N° ${_numeroPedido.isEmpty ? 'Borrador' : _numeroPedido}  ·  $_codigo',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
                  child: const Text('BORRADOR',
                      style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Resumen de liquidación ────────────────────────────────────────────
  Widget _resumenLiquidacion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        _fila('Sub-total', _pesos(_subtotal)),
        const SizedBox(height: 7),
        _fila('Descuento (${_descuentoPct.toStringAsFixed(0)}%)', '- ${_pesos(_descuentoMonto)}',
            valor: _descuentoPct > 0 ? const Color(0xFFDC2626) : _gray),
        const SizedBox(height: 7),
        _fila('Impuesto (IVA 19%)', _pesos(_impuesto)),
        const SizedBox(height: 7),
        _fila('Total flete', _pesos(_flete)),
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: _line)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total a pagar', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: Text(_pesos(_total),
                key: ValueKey<double>(_total),
                style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
        ]),
        if (_cupoAsignado > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _excedeCupo ? const Color(0xFFB45309).withOpacity(0.08) : const Color(0xFF16A34A).withOpacity(0.07),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _excedeCupo ? const Color(0xFFB45309).withOpacity(0.3) : const Color(0xFF16A34A).withOpacity(0.25)),
            ),
            child: Row(children: [
              Icon(_excedeCupo ? Icons.warning_amber_rounded : Icons.verified_rounded,
                  size: 16, color: _excedeCupo ? const Color(0xFFB45309) : const Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _excedeCupo
                      ? 'Excede el cupo · disponible ${_pesos(_cupoDisponible)} (quedará BLOQUEADO)'
                      : 'Dentro del cupo · disponible ${_pesos(_cupoDisponible)}',
                  style: TextStyle(
                    color: _excedeCupo ? const Color(0xFF92400E) : const Color(0xFF15803D),
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _fila(String label, String value, {Color? valor}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: _gray, fontSize: 13, fontWeight: FontWeight.w500)),
      Text(value, style: TextStyle(color: valor ?? _ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
    ]);
  }

  String _condicionesResumen() {
    final partes = <String>[];
    final metodo = (widget.pago?['metodo'] ?? '').toString();
    if (metodo.isNotEmpty) partes.add(metodo);
    if (_plazoDias != null) partes.add('Plazo ${_plazoDias}d');
    if (_fechaEntrega != null) partes.add('Entrega ${DateFormat('dd/MM').format(_fechaEntrega!)}');
    return partes.isEmpty ? 'Definir condiciones' : partes.join(' · ');
  }

  // ── Fila de opción ────────────────────────────────────────────────────
  Widget _opcion({
    required IconData icon,
    required String titulo,
    required String sub,
    required VoidCallback onTap,
    Widget? trailingWidget,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () { HapticFeedback.selectionClick(); onTap(); },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: _ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              trailingWidget ?? const Icon(Icons.chevron_right_rounded, color: _gray),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tiraEvidencias() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _evidencias.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(File(_evidencias[i].path), width: 76, height: 76, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 76, height: 76, color: _surface, child: const Icon(Icons.image_rounded, color: _gray))),
            ),
            Positioned(
              top: 2, right: 2,
              child: GestureDetector(
                onTap: () => setState(() => _evidencias.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 13),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Footer: guardar ───────────────────────────────────────────────────
  Widget _footer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: SizedBox(
            height: 52, width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _guardando ? null : _guardar,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_ink, _inkDeep]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _guardando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.save_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Guardar pedido', style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                          ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Liquidación (editar descuento + flete) ────────────────────────────
  Future<void> _abrirLiquidacion() async {
    final desc = TextEditingController(text: _descuentoPct > 0 ? _descuentoPct.toStringAsFixed(0) : '');
    final flete = TextEditingController(text: _flete > 0 ? _flete.toStringAsFixed(0) : '');
    await _sheet(
      titulo: 'Liquidación de pedido',
      icon: Icons.calculate_rounded,
      contenido: (setSheet) {
        final pct = (double.tryParse(desc.text.trim()) ?? 0).clamp(0, 100);
        final monto = _subtotal * pct / 100;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _campoNumero('Descuento (%)', desc, Icons.percent_rounded,
              esPorcentaje: true, onChanged: (_) => setSheet(() {})),
          const SizedBox(height: 8),
          // Vista previa en vivo: el descuento se aplica automáticamente.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: pct > 0 ? const Color(0xFFDC2626).withOpacity(0.06) : _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: pct > 0 ? const Color(0xFFDC2626).withOpacity(0.25) : _line),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 15, color: pct > 0 ? const Color(0xFFDC2626) : _gray),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pct <= 0
                      ? 'Escribe el % de descuento (ej: 10 o 50)'
                      : '${pct.toStringAsFixed(0)}% sobre ${_pesos(_subtotal)}  =  - ${_pesos(monto)}',
                  style: TextStyle(color: pct > 0 ? const Color(0xFFB91C1C) : _gray, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _campoNumero('Total flete', flete, Icons.local_shipping_rounded),
        ]);
      },
      onGuardar: () {
        setState(() {
          _descuentoPct = (double.tryParse(desc.text.trim()) ?? 0).clamp(0, 100).toDouble();
          _flete = double.tryParse(flete.text.replaceAll('.', '')) ?? 0;
        });
      },
    );
    desc.dispose();
    flete.dispose();
  }

  // ── Condiciones (plazo, fecha, observaciones) ─────────────────────────
  Future<void> _abrirCondiciones() async {
    final plazo = TextEditingController(text: _plazoDias?.toString() ?? '');
    final obs = TextEditingController(text: _observaciones);
    DateTime? fecha = _fechaEntrega;
    await _sheet(
      titulo: 'Condiciones de pedido',
      icon: Icons.assignment_rounded,
      contenido: (setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((widget.pago?['metodo'] ?? '').toString().isNotEmpty) ...[
          _infoChip('Forma de pago: ${widget.pago!['metodo']}'),
          const SizedBox(height: 12),
        ],
        _campoNumero('Plazo (días)', plazo, Icons.schedule_rounded),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: fecha ?? DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) setSheet(() => fecha = d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
            child: Row(children: [
              const Icon(Icons.event_rounded, color: _gray, size: 19),
              const SizedBox(width: 10),
              Text(fecha == null ? 'Fecha de entrega' : DateFormat('dd/MM/yyyy').format(fecha!),
                  style: TextStyle(color: fecha == null ? _gray : _ink, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.edit_calendar_rounded, color: _gray, size: 18),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: obs,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Observaciones del pedido…',
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            filled: true, fillColor: _surface,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.4)),
          ),
        ),
      ]),
      onGuardar: () {
        setState(() {
          _plazoDias = int.tryParse(plazo.text.trim());
          _fechaEntrega = fecha;
          _observaciones = obs.text.trim();
        });
      },
    );
    plazo.dispose();
    obs.dispose();
  }

  Widget _infoChip(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _ink.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_rounded, size: 15, color: _ink),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _campoNumero(String label, TextEditingController c, IconData icon,
      {bool esPorcentaje = false, ValueChanged<String>? onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        inputFormatters: esPorcentaje
            ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]
            : [_MilesFormatter()],
        style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _gray, size: 19),
          hintText: esPorcentaje ? 'Ej: 10' : '0',
          suffixText: esPorcentaje ? '%' : null,
          suffixStyle: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900),
          filled: true, fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.4)),
        ),
      ),
    ]);
  }

  // Bottom sheet genérico con guardar/cancelar y estado interno.
  Future<void> _sheet({
    required String titulo,
    required IconData icon,
    required Widget Function(StateSetter) contenido,
    required VoidCallback onGuardar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(11)),
                    child: Icon(icon, color: _ink, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(titulo, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800))),
                  IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded, color: _gray)),
                ]),
                const SizedBox(height: 12),
                contenido(setSheet),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50, width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () { HapticFeedback.selectionClick(); onGuardar(); Navigator.of(ctx).pop(); },
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_ink, _inkDeep]),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Center(child: Text('Aplicar', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Evidencias ────────────────────────────────────────────────────────
  Future<void> _abrirEvidencias() async {
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          const Text('Adicionar evidencia', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: _ink),
            title: const Text('Tomar foto', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: _ink),
            title: const Text('Elegir de galería', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (fuente == null) return;
    try {
      final foto = await _picker.pickImage(source: fuente, imageQuality: 70, maxWidth: 1600);
      if (foto != null) setState(() => _evidencias.add(foto));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo abrir ${fuente == ImageSource.camera ? 'la cámara' : 'la galería'}'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Guardar (con validación de cupo) ──────────────────────────────────
  Future<void> _guardar() async {
    String estado = 'GUARDADO';

    // Validación de cupo: si el pedido supera el cupo disponible, se advierte
    // que quedará BLOQUEADO y se pide confirmación.
    if (_excedeCupo) {
      final si = await _dialogCupo();
      if (si != true) return; // NO → no se graba
      estado = 'BLOQUEADO';
    }

    setState(() => _guardando = true);
    HapticFeedback.mediumImpact();
    final res = await _api.guardarGestionPedido(
      numeroPedido: _numeroPedido,
      clienteId: _codigo,
      clienteNombre: _nombre,
      subtotal: _subtotal,
      descuento: _descuentoMonto,
      impuesto: _impuesto,
      flete: _flete,
      total: _total,
      formaPago: (widget.pago?['metodo'] ?? '').toString(),
      bancoPago: (widget.pago?['banco'] ?? '').toString(),
      referenciaPago: (widget.pago?['referencia'] ?? '').toString(),
      plazoDias: _plazoDias,
      fechaEntrega: _fechaEntrega == null ? '' : DateFormat('yyyy-MM-dd').format(_fechaEntrega!),
      observaciones: _observaciones,
      evidencias: _evidencias.length,
      estado: estado,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res['success'] == true) {
      HapticFeedback.heavyImpact();
      if (estado == 'BLOQUEADO') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido guardado en estado BLOQUEADO (excede el cupo)'),
          backgroundColor: Color(0xFFB45309),
          behavior: SnackBarBehavior.floating,
        ));
      }
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res['message'] ?? 'No se pudo guardar el pedido').toString()),
        backgroundColor: const Color(0xFFB91C1C),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Diálogo de advertencia de cupo. Devuelve true si el vendedor confirma
  /// grabar el pedido a pesar de que quedará BLOQUEADO.
  Future<bool?> _dialogCupo() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 30),
            ),
            const SizedBox(height: 14),
            const Text('Cupo del cliente', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _lineaCupo('Cupo asignado', _pesos(_cupoAsignado)),
                const SizedBox(height: 5),
                _lineaCupo('Disponible', _pesos(_cupoDisponible)),
                const SizedBox(height: 5),
                _lineaCupo('Valor del pedido', _pesos(_total), destacado: true),
              ]),
            ),
            const SizedBox(height: 12),
            const Text(
              'De aprobar la grabación, el pedido quedará en estado BLOQUEADO. ¿Desea grabar el pedido?',
              textAlign: TextAlign.center,
              style: TextStyle(color: _gray, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gray,
                      side: const BorderSide(color: _line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('NO', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () { HapticFeedback.mediumImpact(); Navigator.of(ctx).pop(true); },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('SÍ, GRABAR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _lineaCupo(String label, String value, {bool destacado = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: destacado ? _ink : _gray, fontSize: 12.5, fontWeight: destacado ? FontWeight.w800 : FontWeight.w500)),
      Text(value, style: TextStyle(color: destacado ? const Color(0xFFB45309) : _ink, fontSize: 13.5, fontWeight: FontWeight.w900)),
    ]);
  }
}

/// Formatea miles con puntos mientras se escribe.
class _MilesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final s = int.parse(digits.length > 12 ? digits.substring(0, 12) : digits).toString();
    final b = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      c++;
      if (c % 3 == 0 && i > 0) b.write('.');
    }
    final f = b.toString().split('').reversed.join();
    return TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
  }
}
