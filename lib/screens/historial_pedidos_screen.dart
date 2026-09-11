import 'package:flutter/material.dart';
import '../services/api_easy_service.dart';
import '../utils/price_utils.dart';

class HistorialPedidosScreen extends StatefulWidget {
  const HistorialPedidosScreen({super.key});

  @override
  State<HistorialPedidosScreen> createState() => _HistorialPedidosScreenState();
}

class _HistorialPedidosScreenState extends State<HistorialPedidosScreen> {
  final ApiEasyService _api = ApiEasyService();
  final TextEditingController _search = TextEditingController();

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _azul = Color(0xFF007BFF);
  static const Color _rojo = Color(0xFFDC3545);
  static const Color _naranja = Color(0xFFE67E22);
  static const Color _cian = Color(0xFF17A2B8);
  static const Color _verde = Color(0xFF28A745);

  List<Map<String, dynamic>> _pedidos = [];
  Map<String, dynamic> _resumen = {};
  bool _cargando = true;
  String? _error;
  bool _sapOk = true;
  String _sapMensaje = '';
  String _filtroEtapa = '';

  static const List<String> _etapas = [
    'ENVIADO',
    'BLOQUEO CARTERA',
    'BLOQUEO CUPO',
    'NUEVO',
    'OK',
    'N/D',
  ];

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
    final res = await _api.getHistorialPedidos();
    if (!mounted) return;
    final lista = (res['data'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _pedidos = lista;
      _resumen = Map<String, dynamic>.from(res['resumen'] as Map? ?? {});
      _sapOk = res['sapOk'] != false;
      _sapMensaje = res['sapMensaje']?.toString() ?? '';
      _cargando = false;
      _error = res['success'] == true
          ? null
          : (res['message']?.toString() ?? 'No se pudo cargar el historial de pedidos');
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

  Color _colorEtapa(String etapa) {
    switch (etapa) {
      case 'ENVIADO':
        return _azul;
      case 'BLOQUEO CARTERA':
        return _rojo;
      case 'BLOQUEO CUPO':
        return _naranja;
      case 'NUEVO':
        return _cian;
      case 'OK':
        return _verde;
      default:
        return _gray;
    }
  }

  String _explicacion(String etapa, Map<String, dynamic> e) {
    switch (etapa) {
      case 'ENVIADO':
        return 'Pedido enviado y registrado en SAP';
      case 'BLOQUEO CARTERA':
        return 'Cliente con ${e['facturasVencidas'] ?? 0} factura(s) vencida(s) abiertas en SAP';
      case 'BLOQUEO CUPO':
        return 'Supera el cupo disponible (${_pesos(e['cupoDisponible'])} de ${_pesos(e['cupoLimite'])})';
      case 'NUEVO':
        return 'El cliente no tiene facturas previas en SAP';
      case 'OK':
        return 'Cliente con historial en SAP, sin bloqueos';
      case 'N/D':
        return 'Código no encontrado en SAP (OCRD)';
      default:
        return 'Sin conexión a SAP';
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _search.text.trim().toLowerCase();
    return _pedidos.where((p) {
      final etapa = Map<String, dynamic>.from(p['etapa'] as Map? ?? {});
      final etiquetas = (etapa['etiquetas'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      if (_filtroEtapa.isNotEmpty && !etiquetas.contains(_filtroEtapa)) return false;
      if (q.isEmpty) return true;
      final campos = [
        p['clienteNombre'],
        p['clienteId'],
        p['numeroPedido'],
        p['docNumSap'],
        p['estado'],
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
        title: const Text('Historial de pedidos',
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
                  if (!_sapOk) _avisoSap(),
                  Expanded(child: _lista()),
                ]),
    );
  }

  Widget _avisoSap() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3CD),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'No se pudieron validar las etapas en SAP${_sapMensaje.isEmpty ? '' : ': $_sapMensaje'}',
        style: const TextStyle(color: Color(0xFF856404), fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
          decoration: InputDecoration(
            hintText: 'Cliente, número de pedido o Nº SAP',
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
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _pill('Todas', _filtroEtapa.isEmpty, () => setState(() => _filtroEtapa = '')),
            for (final e in _etapas) ...[
              const SizedBox(width: 7),
              _pill(e, _filtroEtapa == e, () => setState(() => _filtroEtapa = e), color: _colorEtapa(e)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String texto, bool activo, VoidCallback onTap, {Color color = _inkDeep}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? color : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: activo ? color : _line),
          ),
          child: Center(
            child: Text(texto,
                style: TextStyle(
                  color: activo ? Colors.white : _ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      ),
    );
  }

  Widget _lista() {
    final lista = _filtrados;
    if (_pedidos.isEmpty) {
      return _vacio(Icons.shopping_bag_outlined,
          'Todavía no has registrado ningún pedido.\nLos pedidos que crees desde la app aparecerán aquí.');
    }
    if (lista.isEmpty) {
      return _vacio(Icons.search_off_rounded, 'Ningún pedido coincide con el filtro');
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
    return Column(children: [
      Row(children: [
        Expanded(child: _stat('Pedidos', '${_resumen['cantidad'] ?? _pedidos.length}', _inkDeep, Icons.shopping_bag_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _stat('Total', _pesos(_resumen['total']), _inkDeep, Icons.payments_rounded)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _stat('Enviados', '${_resumen['enviados'] ?? 0}', _azul, Icons.cloud_done_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _stat('Bloqueo cartera', '${_resumen['bloqueoCartera'] ?? 0}', _rojo, Icons.block_rounded)),
      ]),
      if ((_resumen['bloqueoCupo'] as num? ?? 0) > 0) ...[
        const SizedBox(height: 10),
        _stat('Bloqueo cupo', '${_resumen['bloqueoCupo']}', _naranja, Icons.credit_card_off_rounded),
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
    final etapa = Map<String, dynamic>.from(p['etapa'] as Map? ?? {});
    final etiquetas = (etapa['etiquetas'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final docSap = (p['docNumSap'] ?? '').toString();
    final lineas = (p['lineas'] as num?)?.toInt() ?? 0;
    final principal = etiquetas.isEmpty ? '—' : etiquetas.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorEtapa(principal).withOpacity(0.35)),
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
              Text('${p['clienteId'] ?? ''} · ${p['numeroPedido'] ?? ''}',
                  style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(_pesos(p['total']),
              style: const TextStyle(color: _inkDeep, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in etiquetas) _chip(e, _colorEtapa(e), fuerte: true),
          _chip(_fecha(p['fecha']), _gray),
          if (lineas > 0) _chip('$lineas ítem(s)', _gray),
          if (docSap.isNotEmpty) _chip('SAP $docSap', _azul),
          if ((p['estado'] ?? '').toString().isNotEmpty) _chip(p['estado'].toString(), _gray),
        ]),
        if (etiquetas.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(_explicacion(principal, etapa),
              style: const TextStyle(color: _gray, fontSize: 11.5, height: 1.3)),
        ],
      ]),
    );
  }

  Widget _chip(String texto, Color color, {bool fuerte = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fuerte ? color : color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto,
          style: TextStyle(
            color: fuerte ? Colors.white : color,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          )),
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
