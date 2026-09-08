import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/filtro_cliente.dart';
import '../utils/price_utils.dart';

class CarteraScreen extends StatefulWidget {
  final String? codigoInicial;
  final String? nombreInicial;

  const CarteraScreen({super.key, this.codigoInicial, this.nombreInicial});

  @override
  State<CarteraScreen> createState() => _CarteraScreenState();
}

class _CarteraScreenState extends State<CarteraScreen> {
  final ApiEasyService _api = ApiEasyService();
  final TextEditingController _search = TextEditingController();

  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _verde = Color(0xFF16A34A);

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _filtrados = [];
  bool _cargandoClientes = true;
  String? _errorClientes;

  Map<String, dynamic>? _seleccionado;
  Map<String, dynamic>? _cartera;
  List<Map<String, dynamic>> _documentos = [];
  bool _cargandoCartera = false;
  String? _errorCartera;

  @override
  void initState() {
    super.initState();
    _search.addListener(_filtrar);
    _cargarClientes();
  }

  @override
  void dispose() {
    _search.removeListener(_filtrar);
    _search.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes({bool forzar = false}) async {
    setState(() {
      _cargandoClientes = true;
      _errorClientes = null;
    });

    final res = await _api.getClientes(forzar: forzar);
    if (!mounted) return;

    final lista = ((res['data'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    setState(() {
      _clientes = lista;
      _cargandoClientes = false;
      _errorClientes = res['success'] == true
          ? null
          : (res['message']?.toString() ?? 'No se pudieron cargar los clientes');
    });

    _filtrar();
    _preseleccionar();
  }

  void _preseleccionar() {
    final codigo = (widget.codigoInicial ?? '').trim();
    if (codigo.isEmpty || _seleccionado != null) return;

    final encontrado = _clientes.where((c) => (c['id'] ?? '').toString() == codigo).toList();
    _seleccionar(encontrado.isNotEmpty
        ? encontrado.first
        : {'id': codigo, 'nombre': widget.nombreInicial ?? ''});
  }

  void _filtrar() {
    if (!mounted) return;
    setState(() {
      _filtrados = FiltroCliente.aplicar(
        _search.text,
        _clientes,
        FiltroCliente.camposCliente,
      );
    });
  }

  Future<void> _seleccionar(Map<String, dynamic> cliente, {bool forzar = false}) async {
    HapticFeedback.selectionClick();
    final codigo = (cliente['id'] ?? '').toString().trim();
    if (codigo.isEmpty) return;

    setState(() {
      _seleccionado = cliente;
      _cargandoCartera = true;
      _errorCartera = null;
      _cartera = null;
      _documentos = [];
    });

    final futuroCartera = _api.getCarteraCliente(codigo, forzar: forzar);
    final futuroDocumentos = _api.getDocumentosCliente(codigo, forzar: forzar);
    final cartera = await futuroCartera;
    final docsRes = await futuroDocumentos;
    if (!mounted) return;

    final documentos = ((docsRes['documentos'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    setState(() {
      _cartera = cartera;
      _documentos = documentos;
      _cargandoCartera = false;
      _errorCartera = cartera == null ? 'No se pudo cargar la cartera del cliente' : null;
    });
  }

  void _limpiarSeleccion() {
    HapticFeedback.selectionClick();
    setState(() {
      _seleccionado = null;
      _cartera = null;
      _documentos = [];
      _errorCartera = null;
      _cargandoCartera = false;
    });
  }

  double _n(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  String _pesos(dynamic v) => PriceUtils.formatPriceDisplay(_n(v));

  String _fecha(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }

  double get _saldoDocumentos => _documentos.fold(0.0, (s, d) => s + _n(d['saldo']));

  int get _documentosVencidos => _documentos.where((d) => d['vencida'] == true).length;

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
        title: const Text(
          'Cartera',
          style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_seleccionado != null)
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh_rounded, color: _ink),
              onPressed: _cargandoCartera
                  ? null
                  : () => _seleccionar(_seleccionado!, forzar: true),
            ),
        ],
      ),
      body: Column(children: [
        _buscador(),
        Expanded(child: _seleccionado == null ? _listaClientes() : _detalleCartera()),
      ]),
    );
  }

  Widget _buscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
          decoration: InputDecoration(
            hintText: 'Código, nombre del cliente o del negocio',
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_seleccionado != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.person_rounded, color: _gray, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _tituloCliente(_seleccionado!),
                style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _limpiarSeleccion,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cambiar',
                  style: TextStyle(color: _inkDeep, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
      ]),
    );
  }

  String _tituloCliente(Map<String, dynamic> c) {
    final nombre = (c['nombre'] ?? '').toString().trim();
    final codigo = (c['id'] ?? '').toString().trim();
    if (nombre.isEmpty) return codigo;
    return '$codigo · $nombre';
  }

  Widget _listaClientes() {
    if (_cargandoClientes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorClientes != null) {
      return _vacio(
        icono: Icons.wifi_off_rounded,
        titulo: _errorClientes!,
        accion: 'Reintentar',
        onAccion: () => _cargarClientes(forzar: true),
      );
    }
    if (_filtrados.isEmpty) {
      return _vacio(
        icono: Icons.search_off_rounded,
        titulo: _clientes.isEmpty
            ? 'No hay clientes asignados'
            : 'Ningún cliente coincide con la búsqueda',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cargarClientes(forzar: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _filtrados.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = _filtrados[i];
          final comercial = FiltroCliente.nombreComercial(c);
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _seleccionar(c),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _inkDeep.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: _inkDeep, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        (c['nombre'] ?? '').toString().trim().isEmpty
                            ? (c['id'] ?? '').toString()
                            : (c['nombre'] ?? '').toString(),
                        style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        comercial.isEmpty
                            ? (c['id'] ?? '').toString()
                            : '${c['id'] ?? ''} · $comercial',
                        style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _gray),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _detalleCartera() {
    if (_cargandoCartera) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorCartera != null) {
      return _vacio(
        icono: Icons.error_outline_rounded,
        titulo: _errorCartera!,
        accion: 'Reintentar',
        onAccion: () => _seleccionar(_seleccionado!, forzar: true),
      );
    }

    final d = _cartera ?? const {};
    final vencidos = _documentosVencidos;

    return RefreshIndicator(
      onRefresh: () => _seleccionar(_seleccionado!, forzar: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Row(children: [
            Expanded(child: _stat('Saldo SAP', _pesos(d['balance']), _inkDeep, Icons.account_balance_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Saldo facturas', _pesos(_saldoDocumentos), _ink, Icons.receipt_long_rounded)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _stat('Abiertas', '${_documentos.length}', _gray, Icons.folder_open_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Vencidas', '$vencidos', vencidos > 0 ? _rojo : _verde, Icons.warning_amber_rounded)),
          ]),
          const SizedBox(height: 10),
          _fichaCliente(d),
          const SizedBox(height: 18),
          const Text('Facturas pendientes',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          if (_documentos.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded, color: _verde),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Este cliente no tiene facturas pendientes',
                      style: TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
            )
          else
            ..._documentos.map(_filaDocumento),
        ],
      ),
    );
  }

  Widget _fichaCliente(Map<String, dynamic> d) {
    final comercial = FiltroCliente.nombreComercial(d).isNotEmpty
        ? FiltroCliente.nombreComercial(d)
        : FiltroCliente.nombreComercial(_seleccionado);
    final filas = <List<String>>[
      ['Código', (_seleccionado?['id'] ?? '').toString()],
      ['Cliente', (d['nombre'] ?? _seleccionado?['nombre'] ?? '').toString()],
      if (comercial.isNotEmpty) ['Negocio', comercial],
      ['Vendedor', (d['vendedor'] ?? '—').toString()],
      ['Límite crédito', _pesos(d['limiteCredito'])],
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: filas
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 108,
                      child: Text(f[0],
                          style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text(f[1].trim().isEmpty ? '—' : f[1],
                          style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _filaDocumento(Map<String, dynamic> f) {
    final vencida = f['vencida'] == true;
    final dias = (f['diasVencimiento'] is num) ? (f['diasVencimiento'] as num).toInt() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vencida ? _rojo.withOpacity(0.35) : _line),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (vencida ? _rojo : _gray).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            vencida ? Icons.warning_amber_rounded : Icons.receipt_rounded,
            color: vencida ? _rojo : _gray,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Factura ${f['docNum'] ?? '—'}',
                style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              'Vence ${_fecha(f['dueDate'])}${vencida ? ' · ${dias.abs()} días' : ''}',
              style: TextStyle(
                color: vencida ? _rojo : _gray,
                fontWeight: FontWeight.w500,
                fontSize: 11.5,
              ),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_pesos(f['saldo']),
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13.5)),
          const SizedBox(height: 2),
          Text('Total ${_pesos(f['total'])}',
              style: const TextStyle(color: _gray, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.7), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _vacio({
    required IconData icono,
    required String titulo,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, color: _gray, size: 40),
          const SizedBox(height: 12),
          Text(titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gray, fontWeight: FontWeight.w600, fontSize: 13.5)),
          if (accion != null && onAccion != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onAccion,
              style: ElevatedButton.styleFrom(
                backgroundColor: _inkDeep,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(accion, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }
}
