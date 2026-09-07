import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_easy_service.dart';
import '../utils/price_utils.dart';

class CuadreDetalleScreen extends StatefulWidget {
  final int recaudoId;
  final String clienteNombre;

  const CuadreDetalleScreen({
    super.key,
    required this.recaudoId,
    this.clienteNombre = '',
  });

  @override
  State<CuadreDetalleScreen> createState() => _CuadreDetalleScreenState();
}

class _CuadreDetalleScreenState extends State<CuadreDetalleScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _rojo = Color(0xFFDC2626);

  static const List<String> _bancos = [
    'Bancolombia',
    'Banco de Bogotá',
    'Davivienda',
    'BBVA',
    'Banco de Occidente',
    'Banco Popular',
    'Banco Agrario',
    'Nequi',
    'Daviplata',
    'Otro',
  ];

  final ApiEasyService _api = ApiEasyService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _numeroRecibo = TextEditingController();
  final TextEditingController _observaciones = TextEditingController();
  final TextEditingController _bancoOtro = TextEditingController();

  Map<String, dynamic>? _recaudo;
  bool _cargando = true;
  bool _guardando = false;
  String? _banco;
  XFile? _comprobante;
  late final DateTime _fecha;

  @override
  void initState() {
    super.initState();
    _fecha = DateTime.now();
    _cargar();
  }

  @override
  void dispose() {
    _numeroRecibo.dispose();
    _observaciones.dispose();
    _bancoOtro.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final r = await _api.getRecaudoCuadre(widget.recaudoId);
    if (!mounted) return;
    setState(() {
      _recaudo = r;
      _cargando = false;
    });
  }

  bool get _cuadrado => _recaudo?['cuadrado'] == true;

  String get _bancoElegido =>
      _banco == 'Otro' ? _bancoOtro.text.trim() : (_banco ?? '');

  bool get _completo =>
      _bancoElegido.isNotEmpty &&
      _numeroRecibo.text.trim().isNotEmpty &&
      _comprobante != null;

  String _pesos(num v) => PriceUtils.formatPriceDisplay(v.toDouble());

  String _fechaTexto(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}  $hh:$mi';
  }

  String _fechaDe(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    return d == null ? '' : _fechaTexto(d);
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _rojo : _ink,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ));
  }

  Future<void> _adjuntar() async {
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: _ink),
            title: const Text('Tomar foto', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: const Text('Foto del comprobante', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: _ink),
            title: const Text('Elegir de galería', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (fuente == null) return;
    try {
      final foto = await _picker.pickImage(source: fuente, imageQuality: 70, maxWidth: 1600);
      if (foto != null && mounted) setState(() => _comprobante = foto);
    } catch (_) {
      if (mounted) _aviso('No se pudo abrir ${fuente == ImageSource.camera ? 'la cámara' : 'la galería'}', error: true);
    }
  }

  Future<void> _guardar() async {
    if (!_completo) {
      _aviso('Banco, número del recibo y comprobante son obligatorios', error: true);
      return;
    }
    setState(() => _guardando = true);
    HapticFeedback.mediumImpact();
    final res = await _api.registrarCuadre(
      recaudoId: widget.recaudoId,
      banco: _bancoElegido,
      numeroRecibo: _numeroRecibo.text,
      observaciones: _observaciones.text,
      fotoRuta: _comprobante!.path,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res['success'] == true) {
      HapticFeedback.heavyImpact();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.verified_rounded, color: _verde),
            SizedBox(width: 10),
            Expanded(child: Text('Caja cuadrada')),
          ]),
          content: Text((res['message'] ?? '').toString(), style: const TextStyle(fontSize: 14, height: 1.4)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } else {
      _aviso((res['message'] ?? 'No se pudo registrar el cuadre').toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(children: [
        _header(),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _recaudo == null
                  ? const Center(child: Text('No se pudo cargar el recaudo'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                      child: LayoutBuilder(builder: (_, c) {
                        final anchoDoble = c.maxWidth >= 720;
                        final entrada = _panelEntrada();
                        final cuadre = _panelCuadre();
                        if (!anchoDoble) {
                          return Column(children: [entrada, const SizedBox(height: 12), cuadre]);
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: entrada),
                            const SizedBox(width: 12),
                            Expanded(child: cuadre),
                          ],
                        );
                      }),
                    ),
        ),
      ]),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_ink, _inkDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 14),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.clienteNombre.isEmpty ? 'Cuadre de caja' : widget.clienteNombre,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(_cuadrado ? 'Recaudo ya cuadrado' : 'Recaudo pendiente por cuadrar',
                    style: TextStyle(
                        color: _cuadrado ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tarjeta({required String titulo, required IconData icono, required List<Widget> hijos}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, color: _ink, size: 18),
          const SizedBox(width: 8),
          Text(titulo, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        ...hijos,
      ]),
    );
  }

  Widget _dato(String etiqueta, String valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: Text(etiqueta, style: const TextStyle(color: _gray, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Text(valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: _ink,
                  fontSize: destacado ? 15 : 13,
                  fontWeight: destacado ? FontWeight.w900 : FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _panelEntrada() {
    final r = _recaudo!;
    final docs = (r['documentos'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return _tarjeta(
      titulo: 'Entrada del recaudo',
      icono: Icons.download_rounded,
      hijos: [
        _dato('Cliente', (r['clienteNombre'] ?? '').toString().isEmpty
            ? (r['clienteId'] ?? '').toString()
            : (r['clienteNombre'] ?? '').toString()),
        _dato('Código', (r['clienteId'] ?? '').toString()),
        _dato('N° de recaudo', (r['numeroRecaudo'] ?? '').toString()),
        _dato('Recibo de caja', r['reciboCaja'] == null ? 'sin recibo' : 'N° ${r['reciboCaja']}'),
        _dato('Forma de pago', (r['formaPago'] ?? '').toString()),
        _dato('Fecha del recaudo', _fechaDe(r['fecha'])),
        const Divider(height: 22, color: _line),
        _dato('Valor recaudado', _pesos((r['valor'] as num?)?.toDouble() ?? 0), destacado: true),
        _dato('Total aplicado', _pesos((r['aplicado'] as num?)?.toDouble() ?? 0)),
        if (docs.isNotEmpty) ...[
          const Divider(height: 22, color: _line),
          const Text('Facturas cruzadas',
              style: TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...docs.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('${d['numFactura'] ?? d['docNum'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Text(_pesos((d['abono'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              )),
        ],
      ],
    );
  }

  Widget _panelCuadre() {
    if (_cuadrado) {
      final c = Map<String, dynamic>.from(_recaudo!['cuadre'] as Map);
      return _tarjeta(
        titulo: 'Cuadre registrado',
        icono: Icons.verified_rounded,
        hijos: [
          _dato('Fecha del cuadre', _fechaDe(c['fecha'])),
          _dato('Banco', (c['banco'] ?? '').toString()),
          _dato('N° del recibo', (c['numeroRecibo'] ?? '').toString()),
          _dato('Comprobante', '${c['evidencias'] ?? 0} imagen(es)'),
          if ((c['observaciones'] ?? '').toString().isNotEmpty) ...[
            const Divider(height: 22, color: _line),
            const Text('Observación',
                style: TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text((c['observaciones'] ?? '').toString(),
                style: const TextStyle(color: _gray, fontSize: 12.5, height: 1.35)),
          ],
        ],
      );
    }

    final r = _recaudo!;
    return _tarjeta(
      titulo: 'Cuadrar la caja',
      icono: Icons.account_balance_rounded,
      hijos: [
        _campoFijo('Fecha', _fechaTexto(_fecha), Icons.event_rounded),
        const SizedBox(height: 12),
        _campoFijo('N° de recaudo', (r['numeroRecaudo'] ?? '').toString(), Icons.receipt_rounded),
        const SizedBox(height: 12),
        _campoFijo('Recibo de caja',
            r['reciboCaja'] == null ? 'sin recibo' : 'N° ${r['reciboCaja']}', Icons.confirmation_number_rounded),
        const SizedBox(height: 16),
        _etiqueta('Banco al que consignó', obligatorio: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _banco,
          isExpanded: true,
          decoration: _decoracion('Selecciona el banco'),
          items: _bancos
              .map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 13.5))))
              .toList(),
          onChanged: (v) => setState(() => _banco = v),
        ),
        if (_banco == 'Otro') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _bancoOtro,
            style: const TextStyle(fontSize: 13.5),
            decoration: _decoracion('Nombre del banco'),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 14),
        _etiqueta('N° del recibo de consignación', obligatorio: true),
        const SizedBox(height: 6),
        TextField(
          controller: _numeroRecibo,
          style: const TextStyle(fontSize: 13.5),
          decoration: _decoracion('Número que aparece en el comprobante'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _etiqueta('Comprobante', obligatorio: true),
        const SizedBox(height: 6),
        _adjunto(),
        const SizedBox(height: 14),
        _etiqueta('Observación', obligatorio: false),
        const SizedBox(height: 6),
        TextField(
          controller: _observaciones,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          style: const TextStyle(fontSize: 13.5),
          decoration: _decoracion('Opcional').copyWith(counterText: ''),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _completo ? _ink : _gray.withOpacity(0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _guardando || !_completo ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(_guardando ? 'Guardando…' : 'Cuadrar caja',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _etiqueta(String texto, {required bool obligatorio}) {
    return Row(children: [
      Text(texto, style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
      if (obligatorio) ...[
        const SizedBox(width: 4),
        const Text('*', style: TextStyle(color: _rojo, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    ]);
  }

  InputDecoration _decoracion(String hint) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: _gray, fontSize: 13),
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _ink, width: 1.4)),
    );
  }

  Widget _campoFijo(String etiqueta, String valor, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _line),
      ),
      child: Row(children: [
        Icon(icono, size: 17, color: _gray),
        const SizedBox(width: 9),
        Text(etiqueta, style: const TextStyle(color: _gray, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(valor,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
              style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 6),
        Icon(Icons.lock_rounded, size: 13, color: _gray.withOpacity(0.7)),
      ]),
    );
  }

  Widget _adjunto() {
    if (_comprobante == null) {
      return OutlinedButton.icon(
        onPressed: _adjuntar,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        icon: const Icon(Icons.photo_camera_rounded, size: 18, color: _ink),
        label: const Text('Adjuntar comprobante',
            style: TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
      );
    }
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(_comprobante!.path), width: 56, height: 56, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  width: 56, height: 56, color: _surface,
                  child: const Icon(Icons.image_rounded, color: _gray),
                )),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: _verde, size: 18),
          SizedBox(width: 5),
          Expanded(
            child: Text('Comprobante adjunto',
                style: TextStyle(color: _verde, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      TextButton(
        onPressed: _adjuntar,
        child: const Text('Cambiar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}
