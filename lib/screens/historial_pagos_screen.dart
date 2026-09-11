import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/price_utils.dart';

class HistorialPagosScreen extends StatefulWidget {
  const HistorialPagosScreen({super.key});

  @override
  State<HistorialPagosScreen> createState() => _HistorialPagosScreenState();
}

class _HistorialPagosScreenState extends State<HistorialPagosScreen> {
  final ApiEasyService _api = ApiEasyService();
  final TextEditingController _search = TextEditingController();

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _ambar = Color(0xFFD97706);

  List<Map<String, dynamic>> _pagos = [];
  Map<String, dynamic> _resumen = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _api.getHistorialPagos();
    if (!mounted) return;
    final lista = (res['data'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _pagos = lista;
      _resumen = Map<String, dynamic>.from(res['resumen'] as Map? ?? {});
      _cargando = false;
      _error = res['success'] == true
          ? null
          : (res['message']?.toString() ?? 'No se pudo cargar el historial de pagos');
    });
  }

  double _n(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  String _pesos(dynamic v) => PriceUtils.formatPriceDisplay(_n(v));

  String _fecha(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _pagos;
    return _pagos.where((p) {
      final campos = [
        p['clienteNombre'],
        p['clienteId'],
        p['numeroRecaudo'],
        p['recibo'],
        p['formaPago'],
        p['banco'],
        p['referencia'],
      ].map((e) => (e ?? '').toString().toLowerCase());
      return campos.any((c) => c.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const Text('Historial de pagos',
            style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded, color: _ink),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _vacio(Icons.cloud_off_rounded, _error!, accion: 'Reintentar')
              : Column(children: [
                  _buscador(),
                  Expanded(child: _lista()),
                ]),
    );
  }

  Widget _buscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
        decoration: InputDecoration(
          hintText: 'Cliente, recibo, forma de pago o referencia',
          hintStyle: const TextStyle(color: _gray, fontWeight: FontWeight.w500, fontSize: 13.5),
          prefixIcon: const Icon(Icons.search_rounded, color: _gray, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: _gray, size: 18),
                  onPressed: () => _search.clear(),
                ),
          isDense: true,
          filled: true,
          fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _lista() {
    final lista = _filtrados;
    if (_pagos.isEmpty) {
      return _vacio(Icons.receipt_long_rounded,
          'Todavía no has registrado ningún pago.\nLos recaudos que cargues desde la app aparecerán aquí.');
    }
    if (lista.isEmpty) {
      return _vacio(Icons.search_off_rounded, 'Ningún pago coincide con la búsqueda');
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _cabecera(),
          const SizedBox(height: 14),
          ...lista.map(_fila),
        ],
      ),
    );
  }

  Widget _cabecera() {
    final formas = (_resumen['porFormaPago'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Column(children: [
      Row(children: [
        Expanded(child: _stat('Pagos', '${_resumen['cantidad'] ?? _pagos.length}', _inkDeep, Icons.receipt_long_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _stat('Total recaudado', _pesos(_resumen['total']), _verde, Icons.payments_rounded)),
      ]),
      if ((_resumen['porCuadrar'] as num? ?? 0) > 0) ...[
        const SizedBox(height: 10),
        _stat('Por cuadrar', '${_resumen['porCuadrar']}', _ambar, Icons.pending_actions_rounded),
      ],
      if (formas.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in formas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _line),
              ),
              child: Text('${f['formaPago']}: ${_pesos(f['valor'])} (${f['cantidad']})',
                  style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ],
    ]);
  }

  Widget _stat(String titulo, String valor, Color color, IconData icono) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(titulo.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(valor, style: const TextStyle(color: _inkDeep, fontSize: 18, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _fila(Map<String, dynamic> p) {
    final cuadrado = p['cuadrado'] == true;
    final recibo = (p['recibo'] ?? '').toString();
    final banco = (p['banco'] ?? '').toString();
    final docs = (p['documentos'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((p['clienteNombre'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _inkDeep, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 3),
              Text((p['clienteId'] ?? '').toString(),
                  style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(_pesos(p['valor']),
              style: const TextStyle(color: _inkDeep, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(_fecha(p['fecha']), _gray),
          if ((p['formaPago'] ?? '').toString().isNotEmpty) _chip(p['formaPago'].toString(), _inkDeep),
          if (recibo.isNotEmpty) _chip('Recibo $recibo', _inkDeep),
          if (banco.isNotEmpty) _chip(banco, _gray),
          if (docs > 0) _chip('$docs factura(s)', _gray),
          _chip(cuadrado ? 'Cuadrado' : 'Por cuadrar', cuadrado ? _verde : _ambar),
        ]),
      ]),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _vacio(IconData icono, String mensaje, {String? accion}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 56, color: _gray.withOpacity(0.5)),
          const SizedBox(height: 14),
          Text(mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gray, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
          if (accion != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: ElevatedButton.styleFrom(backgroundColor: _inkDeep, foregroundColor: Colors.white),
              label: Text(accion),
            ),
          ],
        ]),
      ),
    );
  }
}
