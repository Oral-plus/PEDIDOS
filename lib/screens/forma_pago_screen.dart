import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import 'recaudos_screen.dart';

class FormaPagoScreen extends StatefulWidget {
  final String nombreCliente;
  final String numeroCuenta;
  final int totalDocumentos;
  final int documentosPorCruzar;
  final double dineroFaltante;
  final double totalPedido;
  final Map<String, dynamic>? pagoInicial;
  final String? numeroRecaudoPrevio;
  final double valorRecaudoPrevio;
  final void Function(String numeroRecaudo, double totalAplicado)? onRecaudoGuardado;

  const FormaPagoScreen({
    super.key,
    this.nombreCliente = '',
    this.numeroCuenta = '',
    this.totalDocumentos = 0,
    this.documentosPorCruzar = 0,
    this.dineroFaltante = 0,
    this.totalPedido = 0,
    this.pagoInicial,
    this.numeroRecaudoPrevio,
    this.valorRecaudoPrevio = 0,
    this.onRecaudoGuardado,
  });

  @override
  State<FormaPagoScreen> createState() => _FormaPagoScreenState();
}

class _FormaPagoScreenState extends State<FormaPagoScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);

  static const List<String> _meses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  final TextEditingController _pagoCartera = TextEditingController();
  final TextEditingController _pagoPedido = TextEditingController();
  final TextEditingController _valorCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();

  bool get _tieneCartera => widget.dineroFaltante > 0;
  bool get _tienePedido => widget.totalPedido > 0;
  bool get _tieneConceptos => _tieneCartera || _tienePedido;

  double _parse(TextEditingController c) => double.tryParse(c.text.replaceAll('.', '')) ?? 0;
  double get _montoCartera => _tieneCartera ? _parse(_pagoCartera) : 0;
  double get _montoPedido => _tienePedido ? _parse(_pagoPedido) : 0;

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _evidenciasFotos = [];
  int _evidenciasPrevias = 0;
  int get _evidencias => _evidenciasFotos.length + _evidenciasPrevias;

  String? _metodo;
  final TextEditingController _banco = TextEditingController();
  final TextEditingController _referencia = TextEditingController();

  String? _numeroRecaudo;
  bool get _recaudoCruzado => _numeroRecaudo != null && _numeroRecaudo!.isNotEmpty;

  static const List<Map<String, dynamic>> _metodos = [
    {'id': 'Efectivo', 'icon': Icons.payments_rounded, 'banco': false, 'ref': false},
    {'id': 'Transferencia', 'icon': Icons.swap_horiz_rounded, 'banco': true, 'ref': true},
  ];

  Map<String, dynamic>? get _metodoCfg =>
      _metodo == null ? null : _metodos.firstWhere((m) => m['id'] == _metodo);
  bool get _requiereBanco => _metodoCfg?['banco'] == true;
  bool get _requiereRef => _metodoCfg?['ref'] == true;
  bool get _esCheque => _metodo == 'Cheque';

  @override
  void initState() {
    super.initState();
    if (_tieneCartera) _pagoCartera.text = _miles(widget.dineroFaltante);
    if (_tienePedido) _pagoPedido.text = _miles(widget.totalPedido);
    _cargarPagoInicial();
    final previo = widget.numeroRecaudoPrevio ?? '';
    if (previo.isNotEmpty) {
      _numeroRecaudo = previo;
      if (_tieneCartera && widget.valorRecaudoPrevio > 0) {
        _pagoCartera.text = _miles(widget.valorRecaudoPrevio);
      }
    }
    for (final c in [_pagoCartera, _pagoPedido, _valorCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  void _cargarPagoInicial() {
    final p = widget.pagoInicial;
    if (p == null) return;
    double aDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;
    String texto(double v) => v > 0 ? _miles(v) : '';

    final metodo = p['metodo']?.toString();
    if (metodo != null && _metodos.any((m) => m['id'] == metodo)) _metodo = metodo;
    _banco.text = p['banco']?.toString() ?? '';
    _referencia.text = p['referencia']?.toString() ?? '';
    if (_tieneCartera) _pagoCartera.text = texto(aDouble(p['valorCartera']));
    final pedidoExistia = aDouble(p['totalPedidoBase']) > 0;
    if (_tienePedido && pedidoExistia) _pagoPedido.text = texto(aDouble(p['valorPedido']));
    if (!_tieneConceptos) _valorCtrl.text = texto(aDouble(p['valor']));
    final fecha = p['fecha'];
    if (fecha is DateTime) {
      _fecha = fecha;
    } else if (fecha != null) {
      _fecha = DateTime.tryParse(fecha.toString()) ?? _fecha;
    }
    _evidenciasPrevias = (p['evidencias'] as num?)?.toInt() ?? 0;
    final numRec = p['numeroRecaudo']?.toString() ?? '';
    if (numRec.isNotEmpty) _numeroRecaudo = numRec;
  }

  @override
  void dispose() {
    _pagoCartera.dispose();
    _pagoPedido.dispose();
    _valorCtrl.dispose();
    _banco.dispose();
    _referencia.dispose();
    super.dispose();
  }

  double get _valorNum =>
      _tieneConceptos ? (_montoCartera + _montoPedido) : _parse(_valorCtrl);

  String _miles(num v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      c++;
      if (c % 3 == 0 && i > 0) b.write('.');
    }
    return b.toString().split('').reversed.join();
  }

  String _pesos(num v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      c++;
      if (c % 3 == 0 && i > 0) b.write('.');
    }
    return '\$${b.toString().split('').reversed.join()}';
  }

  String _fechaFmt(DateTime d) => '${d.day}-${_meses[d.month - 1]}-${d.year}';

  Future<void> _elegirFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _ink, onPrimary: Colors.white, onSurface: _ink),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _fecha = d);
  }

  Future<void> _adicionarEvidencia() async {
    HapticFeedback.selectionClick();
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
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Adicionar evidencia',
                  style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          _opcionFuente(ctx, Icons.photo_camera_rounded, 'Tomar foto', 'Usa la cámara', ImageSource.camera),
          _opcionFuente(ctx, Icons.photo_library_rounded, 'Elegir de galería', 'Selecciona una imagen', ImageSource.gallery),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (fuente == null) return;

    try {
      final XFile? foto = await _picker.pickImage(
        source: fuente,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (foto == null) return;
      setState(() => _evidenciasFotos.add(foto));
      _aviso('Evidencia $_evidencias registrada');
    } catch (e) {
      _aviso('No se pudo abrir ${fuente == ImageSource.camera ? 'la cámara' : 'la galería'}');
    }
  }

  Widget _opcionFuente(BuildContext ctx, IconData icon, String titulo, String sub, ImageSource fuente) {
    return ListTile(
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _ink, size: 21),
      ),
      title: Text(titulo, style: const TextStyle(color: _ink, fontSize: 14.5, fontWeight: FontWeight.w800)),
      subtitle: Text(sub, style: const TextStyle(color: _gray, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: _gray),
      onTap: () => Navigator.of(ctx).pop(fuente),
    );
  }

  void _quitarEvidencia(int i) {
    HapticFeedback.selectionClick();
    setState(() => _evidenciasFotos.removeAt(i));
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
        elevation: 6,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ));
  }

  Future<void> _realizar() async {
    // Sin el cruce de documentos diligenciado no se puede realizar el pago
    if (!_recaudoCruzado) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Expanded(child: Text('Falta cruzar los documentos')),
          ]),
          content: const Text(
            'No puedes realizar el pago sin diligenciar el recaudo.\n\n'
            '1. Toca "Cruzar documentos (Recaudos)".\n'
            '2. Selecciona la(s) factura(s) de la cartera que el cliente está pagando y ajusta el abono.\n'
            '3. Guarda el recaudo y vuelve aquí a realizar el pago.\n\n'
            'Si el cliente no hace recaudo en esta visita, usa la opción "Sin recaudo".',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    if (_valorNum <= 0) {
      _aviso('Ingresa el valor del pago');
      return;
    }
    if (_metodo == null) {
      _aviso('Selecciona el método de pago');
      return;
    }
    if (_requiereBanco && _banco.text.trim().isEmpty) {
      _aviso('Indica el banco / entidad');
      return;
    }
    if (_requiereRef && _referencia.text.trim().isEmpty) {
      _aviso(_esCheque ? 'Indica el número de cheque' : 'Indica la referencia / N° de comprobante');
      return;
    }
    FocusScope.of(context).unfocus();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'procesando',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const _ProcesandoPagoDialog(),
      transitionBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    );

    if (!mounted) return;
    final noSubidas = await _subirEvidenciasPago();
    if (!mounted) return;
    if (noSubidas > 0) {
      _aviso('$noSubidas evidencia(s) no se pudieron enviar al servidor');
    }
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop({
      'valor': _valorNum,
      'valorCartera': _montoCartera,
      'valorPedido': _montoPedido,
      'fecha': _fecha,
      'evidencias': _evidencias,
      'metodo': _metodo,
      'banco': _banco.text.trim(),
      'referencia': _referencia.text.trim(),
      'numeroRecaudo': _numeroRecaudo,
    });
  }

  Future<int> _subirEvidenciasPago() async {
    if (_evidenciasFotos.isEmpty) return 0;
    final api = ApiEasyService();
    final numeroRecaudo = _numeroRecaudo ?? '';
    var fallidas = 0;
    for (final foto in _evidenciasFotos) {
      final r = await api.subirEvidencia(
        foto.path,
        origen: numeroRecaudo.isNotEmpty ? 'recaudo' : 'visita',
        numeroRecaudo: numeroRecaudo,
        clienteId: widget.numeroCuenta,
      );
      if (r['success'] != true) fallidas++;
    }
    return fallidas;
  }

  Future<void> _sinRecaudo() async {
    HapticFeedback.selectionClick();
    if (_recaudoCruzado) {
      _aviso('Ya hay un recaudo registrado ($_numeroRecaudo); no se puede marcar sin recaudo');
      return;
    }
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('¿Sin recaudo?',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        content: const Text(
            'Confirmas que el cliente no entregó ningún pago en esta visita.',
            style: TextStyle(color: _gray)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver', style: TextStyle(color: _gray, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (seguro == true && mounted) {
      final noSubidas = await _subirEvidenciasPago();
      if (!mounted) return;
      if (noSubidas > 0) {
        _aviso('$noSubidas evidencia(s) no se pudieron enviar al servidor');
      }
      Navigator.of(context).pop({
        'valor': 0.0,
        'valorCartera': 0.0,
        'valorPedido': 0.0,
        'fecha': _fecha,
        'evidencias': _evidencias,
        'metodo': 'Sin recaudo',
        'banco': '',
        'referencia': '',
        'numeroRecaudo': null,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _seccionConceptos(),
                  const SizedBox(height: 10),
                  _seccionMetodoPago(),
                  const SizedBox(height: 10),
                  _campo(
                    label: 'Fecha de consignación',
                    valor: _fechaFmt(_fecha),
                    icon: Icons.event_rounded,
                    onTap: _elegirFecha,
                    trailing: Icons.edit_calendar_rounded,
                  ),
                  const SizedBox(height: 10),
                  _seccionEvidencias(),
                  const SizedBox(height: 10),
                  _campo(
                    label: 'Cliente',
                    valor: widget.nombreCliente.isNotEmpty ? widget.nombreCliente : '—',
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 10),
                  _campo(
                    label: 'NIT / Código',
                    valor: widget.numeroCuenta.isNotEmpty ? widget.numeroCuenta : '—',
                    icon: Icons.badge_rounded,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _footerAcciones(),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_ink, _inkDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset(AppAssets.logo, height: 24, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.payments_rounded, color: _ink, size: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Forma de pago',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                  Text('Registra el recaudo de la visita',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: 'Volver',
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(children: [
                _stat('Facturas', '${widget.totalDocumentos}'),
                _dividerV(),
                _stat('Vencidas', '${widget.documentosPorCruzar}'),
                _dividerV(),
                _stat('Cartera', _pesos(widget.dineroFaltante)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label.toUpperCase(),
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ]),
      );

  Widget _dividerV() => Container(width: 1, height: 30, color: Colors.white.withOpacity(0.10));

  Widget _seccionEvidencias() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.photo_library_rounded, color: _ink, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Evidencias',
                style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          if (_evidencias > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(30)),
              child: Text('$_evidencias',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          _evidencias == 0
              ? 'Toma una foto o elige de la galería'
              : '$_evidencias soporte(s) registrado(s)',
          style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        if (_evidenciasFotos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _evidenciasFotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _miniaturaEvidencia(i),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _adicionarEvidencia,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _ink, width: 1.3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
            icon: const Icon(Icons.add_a_photo_rounded, size: 18),
            label: const Text('Adicionar evidencia',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          ),
        ),
      ]),
    );
  }

  Widget _miniaturaEvidencia(int i) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_evidenciasFotos[i].path),
          width: 84, height: 84, cacheWidth: 256, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 84, height: 84, color: _surface,
            child: const Icon(Icons.image_rounded, color: _gray),
          ),
        ),
      ),
      Positioned(
        top: 2, right: 2,
        child: GestureDetector(
          onTap: () => _quitarEvidencia(i),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
          ),
        ),
      ),
    ]);
  }

  Widget _seccionMetodoPago() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.account_balance_wallet_rounded, color: _ink, size: 18),
          SizedBox(width: 8),
          Text('Método de pago',
              style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          SizedBox(width: 6),
          Text('*', style: TextStyle(color: Color(0xFFDC2626), fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 4),
        const Text('¿Con qué método cancela el cliente?',
            style: TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _metodos.map((m) {
            final id = m['id'] as String;
            final sel = _metodo == id;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _metodo = id;
                  if (!_requiereBanco) _banco.clear();
                  if (!_requiereRef) _referencia.clear();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? _ink : _surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: sel ? _ink : _line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(m['icon'] as IconData, size: 15, color: sel ? Colors.white : _ink),
                  const SizedBox(width: 6),
                  Text(id,
                      style: TextStyle(
                        color: sel ? Colors.white : _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      )),
                ]),
              ),
            );
          }).toList(),
        ),
        if (_requiereBanco) ...[
          const SizedBox(height: 14),
          _inputPago(
            controller: _banco,
            label: _esCheque ? 'Banco del cheque' : 'Banco / Entidad',
            hint: _esCheque ? 'Ej: Bancolombia' : 'Ej: Bancolombia, Davivienda…',
            icon: Icons.account_balance_rounded,
            capitalize: true,
          ),
        ],
        if (_requiereRef) ...[
          const SizedBox(height: 12),
          _inputPago(
            controller: _referencia,
            label: _esCheque ? 'Número de cheque' : 'Referencia / N° comprobante',
            hint: _esCheque ? 'N° del cheque' : 'N° de la transacción o comprobante',
            icon: _esCheque ? Icons.numbers_rounded : Icons.confirmation_number_rounded,
            keyboardType: TextInputType.text,
          ),
        ],
      ]),
    );
  }

  Widget _inputPago({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool capitalize = false,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.characters,
        style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          prefixIcon: Icon(icon, color: _gray, size: 19),
          filled: true,
          fillColor: _surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.4)),
        ),
      ),
    ]);
  }

  Widget _campo({
    required String label,
    required String valor,
    required IconData icon,
    VoidCallback? onTap,
    IconData? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: _ink, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: const TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text(valor,
                    style: const TextStyle(color: _ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (trailing != null) Icon(trailing, color: _gray, size: 18),
          ]),
        ),
      ),
    );
  }

  Future<void> _abrirRecaudos() async {
    HapticFeedback.selectionClick();
    if (_metodo == null) {
      _aviso('Selecciona el método de pago antes de cruzar la cartera');
      return;
    }
    if (_requiereBanco && _banco.text.trim().isEmpty) {
      _aviso('Indica el banco / entidad antes de cruzar la cartera');
      return;
    }
    if (_requiereRef && _referencia.text.trim().isEmpty) {
      _aviso('Indica la referencia / N° de comprobante antes de cruzar la cartera');
      return;
    }
    if (_recaudoCruzado) {
      _aviso('El recaudo $_numeroRecaudo ya quedó registrado en esta visita');
      return;
    }
    final resultado = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecaudosScreen(
          codigoCliente: widget.numeroCuenta,
          nombreCliente: widget.nombreCliente,
          pago: {
            'metodo': _metodo,
            'banco': _banco.text.trim(),
            'referencia': _referencia.text.trim(),
            'valorCartera': _montoCartera,
            'valor': _valorNum,
          },
          fotos: _evidenciasFotos.map((f) => f.path).toList(),
        ),
      ),
    );
    if (resultado is Map) {
      final numero = (resultado['numeroRecaudo'] ?? '').toString();
      final aplicado = (resultado['totalAplicado'] as num?)?.toDouble() ?? 0;
      final guardadas = (resultado['evidencias'] as num?)?.toInt() ?? 0;
      if (numero.isEmpty) return;
      widget.onRecaudoGuardado?.call(numero, aplicado);
      if (mounted) {
        setState(() {
          _numeroRecaudo = numero;
          if (_tieneCartera && aplicado > 0) _pagoCartera.text = _miles(aplicado);
          // Las fotos ya quedaron guardadas junto al recaudo: se contabilizan
          // como previas para no volver a subirlas al registrar el pago.
          if (guardadas > 0) {
            _evidenciasPrevias += guardadas;
            _evidenciasFotos.removeRange(0, guardadas.clamp(0, _evidenciasFotos.length));
          }
        });
      }
    }
  }

  BoxDecoration get _cardDeco => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      );

  Widget _seccionConceptos() {
    if (!_tieneConceptos) return _seccionValorSimple();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.payments_rounded, color: _ink, size: 18),
          SizedBox(width: 8),
          Text('Valor del pago', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          SizedBox(width: 6),
          Text('*', style: TextStyle(color: Color(0xFFDC2626), fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 4),
        const Text('¿Qué está pagando el cliente?',
            style: TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        if (_tieneCartera) ...[
          _conceptoRow(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Cartera pendiente',
            referencia: _recaudoCruzado
                ? 'Recaudo $_numeroRecaudo registrado'
                : 'Saldo ${_pesos(widget.dineroFaltante)}',
            controller: _pagoCartera,
            maximo: widget.dineroFaltante,
            bloqueado: _recaudoCruzado,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: _abrirRecaudos,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_recaudoCruzado ? Icons.check_circle_rounded : Icons.playlist_add_check_rounded, size: 15, color: _ink),
                  const SizedBox(width: 6),
                  Text(
                    _recaudoCruzado ? 'Documentos cruzados: recaudo $_numeroRecaudo' : 'Cruzar documentos (Recaudos)',
                    style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  if (!_recaudoCruzado) ...const [
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 16, color: _ink),
                  ],
                ]),
              ),
            ),
          ),
        ],
        if (_tieneCartera && _tienePedido)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: _line)),
        if (_tienePedido)
          _conceptoRow(
            icon: Icons.shopping_bag_rounded,
            label: 'Pedido reservado',
            referencia: 'Total ${_pesos(widget.totalPedido)}',
            controller: _pagoPedido,
            maximo: widget.totalPedido,
          ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: _line)),
        Row(children: [
          const Text('Total a pagar', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: Text(_pesos(_valorNum),
                key: ValueKey<double>(_valorNum),
                style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
        ]),
      ]),
    );
  }

  Widget _conceptoRow({
    required IconData icon,
    required String label,
    required String referencia,
    required TextEditingController controller,
    required double maximo,
    bool bloqueado = false,
  }) {
    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, color: _ink, size: 20),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Row(children: [
            Flexible(child: Text(referencia, style: const TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            if (!bloqueado) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.text = _miles(maximo);
                },
                child: const Text('Todo', style: TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
              ),
            ],
          ]),
        ]),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 128,
        child: TextField(
          controller: controller,
          readOnly: bloqueado,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [_MilesInputFormatter()],
          textAlign: TextAlign.right,
          style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            prefixIcon: const Padding(padding: EdgeInsets.only(left: 10, right: 2), child: Text('\$', style: TextStyle(color: _gray, fontSize: 15, fontWeight: FontWeight.w900))),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: '0',
            isDense: true,
            filled: true, fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _ink, width: 1.4)),
          ),
        ),
      ),
    ]);
  }

  Widget _seccionValorSimple() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.payments_rounded, color: _ink, size: 18),
          SizedBox(width: 8),
          Text('Valor del pago', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          SizedBox(width: 6),
          Text('*', style: TextStyle(color: Color(0xFFDC2626), fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _valorCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [_MilesInputFormatter()],
          style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 12, right: 4),
              child: Text('\$', style: TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: '0',
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 26, fontWeight: FontWeight.w900),
            filled: true, fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.4)),
          ),
        ),
      ]),
    );
  }

  Widget _footerAcciones() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _realizar,
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 19),
                  SizedBox(width: 8),
                  Text('Registrar pago',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                ]),
              ),
            ),
            TextButton(
              onPressed: _sinRecaudo,
              child: const Text('El cliente no entregó pago',
                  style: TextStyle(color: _gray, fontSize: 12.5, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MilesInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final limitado = digits.length > 12 ? digits.substring(0, 12) : digits;
    final s = int.parse(limitado).toString();
    final b = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      c++;
      if (c % 3 == 0 && i > 0) b.write('.');
    }
    final formatted = b.toString().split('').reversed.join();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ProcesandoPagoDialog extends StatefulWidget {
  const _ProcesandoPagoDialog();

  @override
  State<_ProcesandoPagoDialog> createState() => _ProcesandoPagoDialogState();
}

class _ProcesandoPagoDialogState extends State<_ProcesandoPagoDialog>
    with TickerProviderStateMixin {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _track = Color(0xFFE5E7EB);

  late final AnimationController _pulse;
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _run();
  }

  Future<void> _run() async {
    try {
      await _progress.forward().orCancel;
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 44),
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 120, height: 120,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = Curves.easeInOut.transform(_pulse.value);
                    return Container(
                      width: 88 + 24 * t,
                      height: 88 + 24 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _ink.withOpacity(0.05 * (1 - t) + 0.02),
                      ),
                    );
                  },
                ),
                Image.asset(AppAssets.logo, width: 82, height: 82, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.payments_rounded, size: 48, color: _ink)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Procesando pago',
                style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: _progress,
              builder: (_, __) => Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 6,
                    color: _track,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progress.value.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_ink, _inkDeep]),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${(_progress.value * 100).round()}%',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
