import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import '../widgets/cliente_sheets.dart';

class SocioNegocioScreen extends StatefulWidget {
  final ApiEasyService api;
  final List<Map<String, dynamic>> clientes;
  final Map<String, dynamic>? seleccionadoInicial;
  final Map<String, dynamic>? detalleInicial;

  const SocioNegocioScreen({
    super.key,
    required this.api,
    required this.clientes,
    this.seleccionadoInicial,
    this.detalleInicial,
  });

  @override
  State<SocioNegocioScreen> createState() => _SocioNegocioScreenState();
}

class _SocioNegocioScreenState extends State<SocioNegocioScreen> {
  final TextEditingController _search = TextEditingController();
  Map<String, dynamic>? _seleccionado;
  Map<String, dynamic>? _detalle;
  bool _loadingDetalle = false;
  List<Map<String, dynamic>> _filtrados = [];

  Map<String, dynamic>? _facturasHistorico;
  bool _loadingHistorico = false;
  bool _historicoExpanded = false;

  // Paleta monocromática (blanco / negro / gris) — igual que el resto de la app
  static const Color _blue = Color(0xFF1F2937); // negro-gris principal
  static const Color _blueLight = Color(0xFF374151); // gris oscuro (degradados)
  static const Color _bluePale = Color(0xFFF3F4F6); // gris muy claro (fondos de ícono)
  static const Color _grayAccent = Color(0xFF6B7280); // gris medio (acento secundario)
  static Color get _bg => AppTheme.backgroundColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  static Color get _border => AppTheme.borderColor;

  @override
  void initState() {
    super.initState();
    _seleccionado = widget.seleccionadoInicial;
    _detalle = widget.detalleInicial;
    _filtrados = List.from(widget.clientes);
    _search.addListener(_filtrar);
    if (_seleccionado != null && _detalle == null) {
      _cargarDetalle(_seleccionado!['id']?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filtrar() {
    final q = _search.text.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtrados = List.from(widget.clientes);
      } else {
        _filtrados = widget.clientes.where((c) {
          final id = (c['id'] ?? '').toString().toLowerCase();
          final nombre = (c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '').toString().toLowerCase();
          return id.contains(q) || nombre.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _seleccionar(Map<String, dynamic> c) async {
    HapticFeedback.selectionClick();
    final codigo = c['id']?.toString() ?? '';
    setState(() {
      _seleccionado = c;
      _detalle = null;
      _facturasHistorico = null;
      _historicoExpanded = false;
      _loadingDetalle = codigo.isNotEmpty;
    });
    if (codigo.isNotEmpty) await _cargarDetalle(codigo);
  }

  Future<void> _cargarDetalle(String codigo) async {
    try {
      final data = await widget.api.getCarteraCliente(codigo);
      if (mounted) setState(() { _detalle = data; _loadingDetalle = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingDetalle = false);
    }
  }

  Future<void> _cargarHistorico() async {
    final codigo = _seleccionado?['id']?.toString() ?? '';
    if (codigo.isEmpty || _loadingHistorico) return;
    setState(() => _loadingHistorico = true);
    final data = await widget.api.getFacturasHistoricasCliente(codigo);
    if (mounted) setState(() { _facturasHistorico = data; _loadingHistorico = false; });
  }

  void _toggleHistorico() {
    setState(() => _historicoExpanded = !_historicoExpanded);
    if (_historicoExpanded && _facturasHistorico == null) {
      _cargarHistorico();
    }
  }

  void _abrirCartera() {
    HapticFeedback.selectionClick();
    final codigo = _seleccionado?['id']?.toString() ?? '';
    if (codigo.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CarteraSheet(
        codigo: codigo,
        api: widget.api,
        initialData: _detalle,
        color: _blue,
      ),
    );
  }

  void _abrirComentarios() {
    HapticFeedback.selectionClick();
    final codigo = _seleccionado?['id']?.toString() ?? '';
    if (codigo.isEmpty) return;
    final nombre = (_seleccionado!['nombre'] ??
            _seleccionado!['cardName'] ??
            _seleccionado!['nombre1'] ??
            '')
        .toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ComentariosSheet(
        codigo: codigo,
        nombreCliente: nombre,
        api: widget.api,
        color: _grayAccent,
      ),
    );
  }

  void _cambiarCliente() {
    setState(() {
      _seleccionado = null;
      _detalle = null;
      _facturasHistorico = null;
      _historicoExpanded = false;
      _search.clear();
      _filtrados = List.from(widget.clientes);
    });
  }

  void _volver() {
    Navigator.of(context).pop({
      'cliente': _seleccionado,
      'detalle': _detalle,
    });
  }

  String _formatCurrency(dynamic value) {
    final n = (double.tryParse(value.toString()) ?? 0);
    final parts = n.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    int count = 0;
    for (int i = parts.length - 1; i >= 0; i--) {
      buffer.write(parts[i]);
      count++;
      if (count % 3 == 0 && i > 0 && parts[i] != '-') buffer.write('.');
    }
    return '\$${buffer.toString().split('').reversed.join()}';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volver();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: _textDark,
            onPressed: _volver,
          ),
          title: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.business_center_rounded, color: _blue, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Socio de Negocio', style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(
                  _seleccionado == null
                      ? 'Elige un cliente'
                      : 'Datos del cliente',
                  style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
          ]),
          actions: _seleccionado != null
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: _cambiarCliente,
                      icon: Icon(Icons.swap_horiz_rounded, size: 18, color: _blue),
                      label: Text('Cambiar',
                          style: TextStyle(color: _blue, fontWeight: FontWeight.w700, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 36),
                        backgroundColor: _blue.withOpacity(0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]
              : null,
        ),
        body: _seleccionado == null ? _buildPicker() : _buildDetalle(),
      ),
    );
  }

  Widget _buildPicker() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(Icons.search_rounded, color: _textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre o código...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_search.text.isNotEmpty)
              GestureDetector(
                onTap: () => _search.clear(),
                child: Icon(Icons.close_rounded, color: _textMuted, size: 18),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Text('${_filtrados.length} de ${widget.clientes.length}',
              style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: _filtrados.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off_rounded, size: 40, color: _textMuted.withOpacity(0.4)),
                    const SizedBox(height: 10),
                    Text('Sin resultados',
                        style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500)),
                  ]),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: _filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final c = _filtrados[i];
                  final nombre = (c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? 'Cliente').toString();
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _seleccionar(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.storefront_rounded, color: _textMuted, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(nombre,
                                  style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('${c['id'] ?? '—'}',
                                  style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          Icon(Icons.chevron_right_rounded, color: _textMuted, size: 20),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildDetalle() {
    final c = _seleccionado!;
    final codigo = c['id']?.toString() ?? '';
    final nombre = (c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '—').toString();
    final sap = _detalle;
    final telefono = sap?['telefono']?.toString().trim().isNotEmpty == true ? sap!['telefono'].toString() : '—';
    final direccion = sap?['direccion']?.toString().trim().isNotEmpty == true ? sap!['direccion'].toString() : '—';
    final ciudad = sap?['ciudad']?.toString().trim().isNotEmpty == true ? sap!['ciudad'].toString() : '—';
    final vendedor = sap?['vendedor']?.toString().trim().isNotEmpty == true ? sap!['vendedor'].toString() : '—';
    final limiteCredito = sap?['limiteCredito'] ?? 0;
    final descuentoRaw = sap?['descuento'];
    final descuentoNum = (descuentoRaw is num) ? descuentoRaw.toDouble() : double.tryParse(descuentoRaw?.toString() ?? '') ?? 0.0;
    final descuento = '${descuentoNum.toStringAsFixed(descuentoNum % 1 == 0 ? 0 : 2)}%';
    final canal = (sap?['canal']?.toString().trim().isNotEmpty == true)
        ? sap!['canal'].toString()
        : (sap?['canalCodigo'] != null ? 'Grupo ${sap!['canalCodigo']}' : '—');
    final listaPrecios = (sap?['listaPrecios']?.toString().trim().isNotEmpty == true)
        ? sap!['listaPrecios'].toString()
        : (sap?['listaPreciosCodigo'] != null ? 'Lista ${sap!['listaPreciosCodigo']}' : '—');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _buildAccionesGrid(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_blue, _blueLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: _blue.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(codigo,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
            ])),
            if (_loadingDetalle)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            else
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _stat(Icons.credit_score_rounded, 'Límite crédito', _formatCurrency(limiteCredito), _blue)),
          const SizedBox(width: 10),
          Expanded(child: _stat(Icons.percent_rounded, 'Descuento', descuento, _grayAccent)),
        ]),
        const SizedBox(height: 14),
        _detail(Icons.phone_rounded, 'Teléfono', telefono),
        const SizedBox(height: 8),
        _detail(Icons.location_on_rounded, 'Dirección', direccion),
        const SizedBox(height: 8),
        _detail(Icons.location_city_rounded, 'Ciudad', ciudad),
        const SizedBox(height: 8),
        _detail(Icons.badge_rounded, 'Vendedor', vendedor),
        const SizedBox(height: 8),
        _detail(Icons.hub_rounded, 'Canal', canal),
        const SizedBox(height: 8),
        _detail(Icons.price_change_rounded, 'Lista de precios', listaPrecios),
        const SizedBox(height: 16),
        _buildHistoricoCard(),
      ],
    );
  }

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }

  Widget _buildHistoricoCard() {
    final h = _facturasHistorico;
    final facturas = (h?['facturas'] as List<dynamic>?) ?? [];
    final totalCompras = h?['totalCompras'] ?? 0;
    final totalPagado = h?['totalPagado'] ?? 0;
    final pagadas = h?['pagadas'] ?? 0;
    final abiertas = h?['abiertas'] ?? 0;
    final total = h?['total'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _toggleHistorico,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.history_rounded, color: _blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Facturas históricas',
                      style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    _facturasHistorico == null
                        ? (_loadingHistorico ? 'Cargando...' : 'Toca para ver el historial completo')
                        : '$total facturas · $pagadas pagadas · $abiertas abiertas',
                    style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
              if (_loadingHistorico)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(_historicoExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: _textMuted),
            ]),
          ),
        ),
        if (_historicoExpanded && !_loadingHistorico && _facturasHistorico != null) ...[
          Container(height: 1, color: _border.withOpacity(0.5)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: _miniStat('Compras', _formatCurrency(totalCompras), _blue, Icons.shopping_bag_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Pagado', _formatCurrency(totalPagado), _grayAccent, Icons.payments_rounded)),
            ]),
          ),
          if (facturas.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Sin facturas históricas',
                    style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: facturas.take(50).map((raw) {
                  final f = Map<String, dynamic>.from(raw as Map);
                  final estado = (f['estado'] ?? '').toString();
                  Color color;
                  IconData icon;
                  switch (estado) {
                    case 'PAGADA':
                      color = _grayAccent; icon = Icons.check_circle_rounded; break;
                    case 'VENCIDA':
                      color = _blue; icon = Icons.warning_amber_rounded; break;
                    default:
                      color = _grayAccent; icon = Icons.receipt_rounded;
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withOpacity(0.18)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('#${f['numero'] ?? '—'}',
                              style: TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(estado,
                                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text('Emit: ${_formatDate(f['fecha'])}  ·  Venc: ${_formatDate(f['vencimiento'])}',
                            style: TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w500)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_formatCurrency(f['total']),
                            style: TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 13)),
                        if ((f['saldo'] ?? 0) > 0)
                          Text('Saldo: ${_formatCurrency(f['saldo'])}',
                              style: const TextStyle(color: _blue, fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  );
                }).toList(),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.8), size: 13),
          const SizedBox(width: 5),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _buildAccionesGrid() {
    return Row(children: [
      Expanded(child: _accionCard(
        icon: Icons.account_balance_wallet_rounded,
        color: _blue,
        title: 'Cartera',
        subtitle: _detalle != null
            ? '${_detalle!['totalFacturasAbiertas'] ?? 0} facturas'
            : 'Ver saldo y facturas',
        onTap: _abrirCartera,
      )),
      const SizedBox(width: 10),
      Expanded(child: _accionCard(
        icon: Icons.chat_bubble_rounded,
        color: _grayAccent,
        title: 'Comentarios',
        subtitle: 'Ver y agregar',
        onTap: _abrirComentarios,
      )),
    ]);
  }

  Widget _accionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool wide = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: wide
              ? Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
                  ])),
                  Icon(Icons.chevron_right_rounded, color: _textMuted, size: 20),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(title,
                      style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.8), size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _bluePale, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: _blueLight, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 3, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}
