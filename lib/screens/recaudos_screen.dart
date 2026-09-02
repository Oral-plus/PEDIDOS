import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/price_utils.dart';

class RecaudosScreen extends StatefulWidget {
  final String codigoCliente;
  final String nombreCliente;
  final Map<String, dynamic>? pago;
  /// Rutas de las fotos de evidencia. Viajan con el recaudo en la misma
  /// peticion para que se guarden en la misma transaccion.
  final List<String> fotos;

  const RecaudosScreen({
    super.key,
    required this.codigoCliente,
    this.nombreCliente = '',
    this.pago,
    this.fotos = const [],
  });

  @override
  State<RecaudosScreen> createState() => _RecaudosScreenState();
}

class _RecaudosScreenState extends State<RecaudosScreen> {
  final ApiEasyService _api = ApiEasyService();

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _verde = Color(0xFF16A34A);

  List<Map<String, dynamic>> _docs = [];
  bool _cargando = true;
  bool _guardando = false;

  final Set<int> _cruzados = {};
  final Map<int, double> _abonos = {};
  final TextEditingController _recaudoCtrl = TextEditingController();
  final TextEditingController _notas = TextEditingController();

  late final String _numeroRecaudo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _numeroRecaudo =
        'REC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(9)}';
    final v = (widget.pago?['valorCartera'] ?? widget.pago?['valor']);
    if (v is num && v > 0) _recaudoCtrl.text = _miles(v);
    _recaudoCtrl.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _recaudoCtrl.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final res = await _api.getDocumentosCliente(widget.codigoCliente);
    if (!mounted) return;
    setState(() {
      _docs = (res['documentos'] as List).cast<Map<String, dynamic>>();
      _cargando = false;
    });
  }

  double _n(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
  int _docEntry(Map<String, dynamic> d) => (d['docEntry'] is int) ? d['docEntry'] : int.tryParse('${d['docEntry']}') ?? 0;

  double get _totalDocumentos =>
      _docs.where((d) => _cruzados.contains(_docEntry(d))).fold(0.0, (s, d) => s + _n(d['saldo']));
  double get _totalAplicado => _abonos.entries.where((e) => _cruzados.contains(e.key)).fold(0.0, (s, e) => s + e.value);
  double get _totalRecaudo => double.tryParse(_recaudoCtrl.text.replaceAll('.', '')) ?? 0;
  double get _saldo => _totalRecaudo - _totalAplicado;

  String _pesos(num v) => PriceUtils.formatPriceDisplay(v.toDouble());

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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _surface,
        body: Column(children: [
          _header(),
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: _ink,
              unselectedLabelColor: _gray,
              indicatorColor: _ink,
              indicatorWeight: 2.4,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.3),
              unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              tabs: [Tab(text: 'PAGOS'), Tab(text: 'DOCUMENTOS'), Tab(text: 'NOTAS')],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [_tabPagos(), _tabDocumentos(), _tabNotas()]),
          ),
          _footer(),
        ]),
      ),
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
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 14),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Image.asset(AppAssets.logo, height: 20, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.request_quote_rounded, color: _ink, size: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Recaudos', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('N° $_numeroRecaudo', style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w500)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Column(children: [
                _totRow('Total documentos', _totalDocumentos),
                const SizedBox(height: 6),
                _totRow('Total aplicado', _totalAplicado),
                const SizedBox(height: 6),
                _totRow('Total recaudo', _totalRecaudo),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Colors.white.withOpacity(0.12))),
                _totRow('Saldo', _saldo, destacado: true),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _totRow(String label, double value, {bool destacado = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: destacado ? Colors.white : Colors.white70, fontSize: destacado ? 14 : 12.5, fontWeight: destacado ? FontWeight.w800 : FontWeight.w500)),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: Text(_pesos(value),
            key: ValueKey<String>('$label${value.toStringAsFixed(0)}'),
            style: TextStyle(color: Colors.white, fontSize: destacado ? 17 : 13.5, fontWeight: destacado ? FontWeight.w900 : FontWeight.w700)),
      ),
    ]);
  }

  Widget _tabDocumentos() {
    if (_docs.isEmpty) {
      return _vacio(Icons.description_outlined, 'Sin documentos abiertos');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _docCard(_docs[i]),
    );
  }

  Widget _docCard(Map<String, dynamic> d) {
    final entry = _docEntry(d);
    final cruzado = _cruzados.contains(entry);
    final saldo = _n(d['saldo']);
    final abono = _abonos[entry] ?? saldo;
    final dias = (d['diasVencimiento'] is num) ? (d['diasVencimiento'] as num).toInt() : 0;
    final vencida = d['vencida'] == true || dias < 0;

    return Container(
      decoration: BoxDecoration(
        color: cruzado ? _ink.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cruzado ? _ink.withOpacity(0.4) : _line, width: cruzado ? 1.4 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _menuDocumento(d),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: cruzado ? _ink : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cruzado ? _ink : _line, width: 1.6),
                  ),
                  child: cruzado ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Factura ${d['numFactura'] ?? d['docNum']}',
                      style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(_pesos(saldo), style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip(Icons.event_rounded, 'F.D. ${d['docDate'] ?? '—'}'),
                _chip(Icons.event_available_rounded, 'F.V. ${d['dueDate'] ?? '—'}'),
                _chip(
                  vencida ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                  vencida ? 'Vencida hace ${dias.abs()} días' : 'Vence en $dias días',
                  color: vencida ? _rojo : _gray,
                ),
              ]),
              if (cruzado) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.payments_rounded, size: 15, color: _ink),
                    const SizedBox(width: 8),
                    const Text('Abono', style: TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(_pesos(abono), style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _editarAbono(d),
                      child: const Icon(Icons.edit_rounded, size: 15, color: _ink),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, {Color color = _gray}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color == _gray ? _ink : color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _menuDocumento(Map<String, dynamic> d) {
    final entry = _docEntry(d);
    final cruzado = _cruzados.contains(entry);
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          const Text('Seleccione', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (!cruzado)
            _menuItem(ctx, Icons.playlist_add_check_rounded, 'Cruzar documento', () {
              setState(() { _cruzados.add(entry); _abonos[entry] = _n(d['saldo']); });
            })
          else
            _menuItem(ctx, Icons.remove_circle_outline_rounded, 'Quitar documento', () {
              setState(() { _cruzados.remove(entry); _abonos.remove(entry); });
            }, color: _rojo),
          _menuItem(ctx, Icons.info_outline_rounded, 'Detalle documento', () => _detalleDocumento(d)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String text, VoidCallback onTap, {Color color = _ink}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      onTap: () { Navigator.of(ctx).pop(); onTap(); },
    );
  }

  void _detalleDocumento(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Factura ${d['numFactura'] ?? d['docNum']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _detRow('N° documento', '${d['docNum'] ?? '—'}'),
          _detRow('Fecha documento', '${d['docDate'] ?? '—'}'),
          _detRow('Fecha vencimiento', '${d['dueDate'] ?? '—'}'),
          _detRow('Total factura', _pesos(_n(d['total']))),
          _detRow('Pagado', _pesos(_n(d['pagado']))),
          _detRow('Saldo', _pesos(_n(d['saldo']))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _detRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(color: _gray, fontSize: 12.5)),
        Text(v, style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<void> _editarAbono(Map<String, dynamic> d) async {
    final entry = _docEntry(d);
    final saldo = _n(d['saldo']);
    final ctrl = TextEditingController(text: _miles(_abonos[entry] ?? saldo));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Abono al documento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [_MilesFmt()],
          decoration: InputDecoration(
            prefixText: '\$ ',
            helperText: 'Saldo: ${_pesos(saldo)}',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ink),
            onPressed: () {
              final v = (double.tryParse(ctrl.text.replaceAll('.', '')) ?? 0).clamp(0, saldo).toDouble();
              setState(() => _abonos[entry] = v);
              Navigator.of(ctx).pop();
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Widget _tabPagos() {
    final metodo = (widget.pago?['metodo'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recaudo recibido', style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _recaudoCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [_MilesFmt()],
              style: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 12, right: 4), child: Text('\$', style: TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w900))),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: '0',
                filled: true, fillColor: _surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.4)),
              ),
            ),
            if (metodo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.account_balance_wallet_rounded, size: 16, color: _ink),
                const SizedBox(width: 8),
                Text('Método: $metodo', style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
              if ((widget.pago?['banco'] ?? '').toString().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4, left: 24), child: Text('Banco: ${widget.pago!['banco']}', style: const TextStyle(color: _gray, fontSize: 12))),
              if ((widget.pago?['referencia'] ?? '').toString().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2, left: 24), child: Text('Ref: ${widget.pago!['referencia']}', style: const TextStyle(color: _gray, fontSize: 12))),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _tabNotas() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: TextField(
            controller: _notas,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: 'Notas del recaudo…',
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _vacio(IconData icon, String texto) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 46, color: _gray.withOpacity(0.4)),
        const SizedBox(height: 10),
        Text(texto, style: const TextStyle(color: _gray, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _footer() {
    final activo = _cruzados.isNotEmpty && !_guardando;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            height: 52, width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: activo ? _guardar : null,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: activo ? const LinearGradient(colors: [_ink, _inkDeep]) : null,
                    color: activo ? null : _line,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _guardando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.save_rounded, color: activo ? Colors.white : _gray, size: 20),
                            const SizedBox(width: 8),
                            Text(_cruzados.isEmpty ? 'Cruza un documento' : 'Guardar recaudo (${_cruzados.length})',
                                style: TextStyle(color: activo ? Colors.white : _gray, fontSize: 15, fontWeight: FontWeight.w800)),
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

  Future<void> _guardar() async {
    if (_totalAplicado > _totalRecaudo && _totalRecaudo > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Aplicado supera el recaudo'),
          content: Text('Estás aplicando ${_pesos(_totalAplicado)} pero el recaudo es ${_pesos(_totalRecaudo)}. ¿Continuar de todas formas?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Revisar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: _ink), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _guardando = true);
    HapticFeedback.mediumImpact();
    final documentos = _docs.where((d) => _cruzados.contains(_docEntry(d))).map((d) {
      final entry = _docEntry(d);
      return {
        'docEntry': entry,
        'docNum': '${d['docNum'] ?? ''}',
        'numFactura': '${d['numFactura'] ?? ''}',
        'saldo': _n(d['saldo']),
        'abono': _abonos[entry] ?? _n(d['saldo']),
        'dueDate': '${d['dueDate'] ?? ''}',
      };
    }).toList();

    final res = await _api.guardarRecaudo(
      numeroRecaudo: _numeroRecaudo,
      clienteId: widget.codigoCliente,
      clienteNombre: widget.nombreCliente,
      formaPago: (widget.pago?['metodo'] ?? '').toString(),
      bancoPago: (widget.pago?['banco'] ?? '').toString(),
      referenciaPago: (widget.pago?['referencia'] ?? '').toString(),
      totalDocumentos: _totalDocumentos,
      totalAplicado: _totalAplicado,
      totalRecaudo: _totalRecaudo,
      saldo: _saldo,
      notas: _notas.text.trim(),
      documentos: documentos,
      fotos: widget.fotos,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res['success'] == true) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Recaudo ${res['numeroRecaudo'] ?? ''} guardado'),
        backgroundColor: _verde,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop({
        'numeroRecaudo': (res['numeroRecaudo'] ?? _numeroRecaudo).toString(),
        'totalAplicado': _totalAplicado,
        'evidencias': res['evidencias'] ?? 0,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res['message'] ?? 'No se pudo guardar el recaudo').toString()),
        backgroundColor: _rojo,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _MilesFmt extends TextInputFormatter {
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
