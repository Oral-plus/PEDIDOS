import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/api_easy_service.dart';
import '../services/order_receipt_service.dart';

class VendorOrdersScreen extends StatefulWidget {
  const VendorOrdersScreen({super.key});

  @override
  State<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends State<VendorOrdersScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _isLoading = true;
  String? _error;
  String _filtroEstado = 'TODOS';
  final TextEditingController _searchController = TextEditingController();
  String? _baseUrl;

  static const _blue = Color(0xFF1A1A2E);
  static const _blueLight = Color(0xFF374151);
  static const _bg = Color(0xFFF8FAFC);
  static const _white = Color(0xFFFFFFFF);
  static const _textDark = Color(0xFF111827);
  static const _textMuted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  static const _baseUrls = ['http://localhost:3000', 'http://10.0.2.2:3000', 'http://192.168.2.244:3000'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _cargarPedidos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _obtenerUrlBase() async {
    if (_baseUrl != null) return _baseUrl!;
    for (final url in _baseUrls) {
      try {
        final res = await http.get(Uri.parse('$url/api/test'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
          if (data['success'] == true) {
            _baseUrl = url;
            return url;
          }
        }
      } catch (_) {}
    }
    _baseUrl = _baseUrls.first;
    return _baseUrl!;
  }

  dynamic _get(dynamic map, String keySnake, String keyCamel) {
    if (map == null || map is! Map) return null;
    final m = Map<String, dynamic>.from(map);
    return m[keySnake] ?? m[keyCamel];
  }

  Future<Map<String, dynamic>?> _obtenerDetallePedido(String numeroPedido) async {
    if (numeroPedido.isEmpty) return null;
    try {
      final base = await _obtenerUrlBase();
      final encoded = Uri.encodeComponent(numeroPedido);
      final url = '$base/api/orders/detail/$encoded';
      final res = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['success'] != true) return null;

      // Soportar ambos formatos: api/server.js { pedido, detalle } o API-EASY { data: { pedido, productos } }
      dynamic pedidoRaw = data['pedido'];
      List<dynamic> detalleRaw = data['detalle'] as List<dynamic>? ?? [];
      if (pedidoRaw == null && data['data'] != null) {
        final inner = data['data'] as Map<String, dynamic>;
        pedidoRaw = inner['pedido'];
        detalleRaw = inner['productos'] as List<dynamic>? ?? [];
      }
      if (pedidoRaw == null) return null;

      final p = Map<String, dynamic>.from(pedidoRaw as Map);
      final pedido = {
        'numeroPedido': _get(p, 'numero_pedido', 'numeroPedido'),
        'codigoCliente': _get(p, 'codigo_cliente', 'codigoCliente'),
        'nombreCliente': _get(p, 'nombre_cliente', 'nombreCliente'),
        'cedulaCliente': _get(p, 'cedula_cliente', 'cedulaCliente'),
        'direccion': _get(p, 'direccion', 'direccion'),
        'telefono': _get(p, 'telefono', 'telefono'),
        'correo': _get(p, 'correo', 'correo'),
        'subtotal': _get(p, 'subtotal', 'subtotal'),
        'iva': _get(p, 'iva', 'iva'),
        'total': _get(p, 'total', 'total'),
        'observaciones': _get(p, 'observaciones', 'observaciones'),
        'estado': _get(p, 'estado', 'estado'),
        'vendedor': _get(p, 'vendedor', 'vendedor'),
        'fechaCreacion': _get(p, 'fecha_creacion', 'fechaCreacion'),
      };
      final productos = detalleRaw.map((e) {
        final d = Map<String, dynamic>.from(e as Map);
        return {
          'nombre': d['nombre_producto'] ?? d['nombre'],
          'cantidad': d['cantidad'],
          'precioUnitario': d['precio_unitario'] ?? d['precioUnitario'],
          'totalLinea': d['total_linea'] ?? d['totalLinea'],
        };
      }).toList();
      return {'pedido': pedido, 'productos': productos};
    } catch (e) {
      debugPrint('Error cargando detalle: $e');
    }
    return null;
  }

  Future<void> _mostrarDetallePedido(String? numeroPedido) async {
    if (numeroPedido == null || numeroPedido.isEmpty) return;
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: _blue)),
    );
    final detail = await _obtenerDetallePedido(numeroPedido);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al cargar los detalles del pedido. Verifica la conexión con el servidor.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'Reintentar', textColor: Colors.white, onPressed: () => _mostrarDetallePedido(numeroPedido)),
        ),
      );
      return;
    }
    final pedido = detail['pedido'] as Map<String, dynamic>? ?? {};
    final productos = (detail['productos'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    _mostrarSheetDetalle(pedido, productos);
  }

  void _mostrarSheetDetalle(Map<String, dynamic> pedido, List<Map<String, dynamic>> productos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    _detalleHeader(pedido),
                    const SizedBox(height: 20),
                    _detalleCliente(pedido),
                    const SizedBox(height: 20),
                    _detalleProductos(productos),
                    const SizedBox(height: 16),
                    _detalleTotales(pedido),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
                decoration: BoxDecoration(color: _white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))]),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await OrderReceiptService.generateAndSavePdfFactura(pedido: pedido, productos: productos);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: const Text('PDF descargado'), backgroundColor: Colors.green.shade700),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 24),
                      label: const Text('Descargar PDF (Factura)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleHeader(Map<String, dynamic> p) {
    final estado = (p['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final color = _estadoColor(estado);
    String dateStr = '—';
    try {
      if (p['fechaCreacion'] != null) dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(p['fechaCreacion'].toString()));
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(estado, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ),
            const Spacer(),
            Text(p['numeroPedido'] ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Fecha: $dateStr', style: const TextStyle(fontSize: 14, color: _textMuted)),
        if ((p['vendedor'] ?? '').toString().isNotEmpty)
          Text('Vendedor: ${p['vendedor']}', style: const TextStyle(fontSize: 13, color: _textMuted)),
      ],
    );
  }

  Widget _detalleCliente(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Datos del cliente', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
          const SizedBox(height: 12),
          _detalleRow('Nombre', p['nombreCliente'] ?? '—'),
          _detalleRow('Cédula', p['cedulaCliente'] ?? '—'),
          _detalleRow('Código', p['codigoCliente'] ?? '—'),
          _detalleRow('Teléfono', p['telefono'] ?? '—'),
          _detalleRow('Correo', p['correo'] ?? '—'),
          _detalleRow('Dirección', p['direccion'] ?? '—'),
          if ((p['observaciones'] ?? '').toString().isNotEmpty) _detalleRow('Observaciones', p['observaciones'] ?? '—'),
        ],
      ),
    );
  }

  Widget _detalleRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _textDark, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _detalleProductos(List<Map<String, dynamic>> productos) {
    final formatter = NumberFormat('#,##0', 'es_CO');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Productos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: _blue.withOpacity(0.06), borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('Producto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textDark))),
                    SizedBox(width: 50, child: Text('Cant.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textDark))),
                    SizedBox(width: 70, child: Text('P. unit.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textDark))),
                    SizedBox(width: 80, child: Text('Total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textDark))),
                  ],
                ),
              ),
              ...productos.map((item) {
                final total = (item['totalLinea'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(item['nombre'] ?? '—', style: const TextStyle(fontSize: 12, color: _textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 50, child: Text('${item['cantidad'] ?? 0}', style: const TextStyle(fontSize: 12, color: _textMuted))),
                      SizedBox(width: 70, child: Text('\$${formatter.format((item['precioUnitario'] as num?)?.toInt() ?? 0)}', style: const TextStyle(fontSize: 12, color: _textMuted))),
                      SizedBox(width: 80, child: Text('\$${formatter.format(total.round())}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _blue))),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detalleTotales(Map<String, dynamic> p) {
    final formatter = NumberFormat('#,##0', 'es_CO');
    final subtotal = (p['subtotal'] as num?)?.toDouble() ?? 0;
    final iva = (p['iva'] as num?)?.toDouble() ?? 0;
    final total = (p['total'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_blue.withOpacity(0.08), _blueLight.withOpacity(0.06)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          if (iva > 0) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal', style: TextStyle(fontSize: 14, color: _textMuted)), Text('\$${formatter.format(subtotal.round())}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('IVA', style: TextStyle(fontSize: 14, color: _textMuted)), Text('\$${formatter.format(iva.round())}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 8),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark)), Text('\$${formatter.format(total.round())}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _blue))]),
        ],
      ),
    );
  }

  Future<void> _cargarPedidos() async {
    final usuario = ApiEasyService().usuario;
    final nombre = usuario?['nombre']?.toString() ?? '';
    if (nombre.isEmpty) {
      setState(() { _isLoading = false; _error = 'Sin datos de vendedor'; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      final base = await _obtenerUrlBase();
      final encoded = Uri.encodeComponent(nombre);
      final url = '$base/api/orders/vendedor/$encoded';
      final res = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && data['success'] == true) {
        final list = (data['data'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        if (mounted) setState(() { _pedidos = list; _isLoading = false; });
      } else {
        if (mounted) setState(() { _error = data['message']?.toString() ?? 'Error'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Error de conexión'; _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get _pedidosFiltrados {
    var list = _pedidos;
    if (_filtroEstado != 'TODOS') {
      list = list.where((p) => p['estado'] == _filtroEstado).toList();
    }
    final q = _searchController.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final num = (p['numeroPedido'] ?? '').toString().toLowerCase();
        final nombre = (p['nombreCliente'] ?? '').toString().toLowerCase();
        final codigo = (p['codigoCliente'] ?? '').toString().toLowerCase();
        final cedula = (p['cedulaCliente'] ?? '').toString().toLowerCase();
        return num.contains(q) || nombre.contains(q) || codigo.contains(q) || cedula.contains(q);
      }).toList();
    }
    return list;
  }

  String _fmtDate(dynamic date) {
    if (date == null) return '—';
    try {
      final d = DateTime.parse(date.toString());
      return DateFormat('dd/MM/yyyy HH:mm').format(d);
    } catch (_) {
      return date.toString();
    }
  }

  String _fmtMoney(dynamic v) => '\$${NumberFormat('#,##0', 'es_CO').format((v as num?)?.toInt() ?? 0)}';

  Color _estadoColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'PENDIENTE': return const Color(0xFFF59E0B);
      case 'CONFIRMADO': return _blue;
      case 'EN_PROCESO': case 'EN PROCESO': return const Color(0xFF8B5CF6);
      case 'ENVIADO': return const Color(0xFF06B6D4);
      case 'ENTREGADO': return const Color(0xFF059669);
      case 'CANCELADO': return const Color(0xFFDC2626);
      default: return _textMuted;
    }
  }

  IconData _estadoIcon(String estado) {
    switch (estado.toUpperCase()) {
      case 'PENDIENTE': return Icons.schedule_rounded;
      case 'CONFIRMADO': return Icons.thumb_up_alt_rounded;
      case 'EN_PROCESO': case 'EN PROCESO': return Icons.settings_rounded;
      case 'ENVIADO': return Icons.local_shipping_rounded;
      case 'ENTREGADO': return Icons.check_circle_rounded;
      case 'CANCELADO': return Icons.cancel_rounded;
      default: return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = ApiEasyService().usuario;
    final nombreVendedor = usuario?['nombre']?.toString() ?? 'Vendedor';

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _header(nombreVendedor),
          _searchBar(),
          _filterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _blue))
                : _error != null
                    ? _errorWidget()
                    : _pedidosFiltrados.isEmpty
                        ? _emptyWidget()
                        : RefreshIndicator(
                            onRefresh: _cargarPedidos,
                            color: _blue,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                              itemCount: _pedidosFiltrados.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => _mostrarDetallePedido(_pedidosFiltrados[i]['numeroPedido']?.toString()),
                                child: _pedidoCard(_pedidosFiltrados[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _header(String nombre) {
    return Container(
      color: _white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                  child: const Icon(Icons.arrow_back_rounded, color: _textDark, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pedidos del Vendedor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textDark, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text(nombre, style: const TextStyle(fontSize: 13, color: _textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('${_pedidos.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _blue)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _cargarPedidos,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                  child: const Icon(Icons.refresh_rounded, color: _textMuted, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _textDark),
          decoration: InputDecoration(
            hintText: 'Buscar por número, cliente o código...',
            hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: _blueLight, size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, color: _textMuted, size: 20),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final filtros = ['TODOS', 'PENDIENTE', 'CONFIRMADO', 'ENVIADO', 'ENTREGADO', 'CANCELADO'];
    return Container(
      color: _white,
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: filtros.map((f) {
            final isActive = _filtroEstado == f;
            final color = f == 'TODOS' ? _blue : _estadoColor(f);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filtroEstado = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? color.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isActive ? color.withOpacity(0.4) : _border),
                  ),
                  child: Text(
                    f == 'TODOS' ? 'Todos (${_pedidos.length})' : f,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isActive ? color : _textMuted),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _pedidoCard(Map<String, dynamic> p) {
    final estado = (p['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final color = _estadoColor(estado);
    final icon = _estadoIcon(estado);

    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['numeroPedido'] ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
                      const SizedBox(height: 2),
                      Text(_fmtDate(p['fechaCreacion']), style: const TextStyle(fontSize: 12, color: _textMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(estado, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, size: 16, color: _blueLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${p['nombreCliente'] ?? '—'} (${p['codigoCliente'] ?? ''})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                _miniStat(Icons.shopping_bag_outlined, '${p['totalProductos'] ?? 0} prod.'),
                const SizedBox(width: 16),
                _miniStat(Icons.inventory_2_outlined, '${p['totalUnidades'] ?? 0} uds.'),
                const Spacer(),
                Text(_fmtMoney(p['total']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _blue)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _emptyWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 64, color: _textMuted.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('Sin pedidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textDark)),
          const SizedBox(height: 6),
          const Text('Aún no hay pedidos registrados con tu nombre', style: TextStyle(fontSize: 14, color: _textMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _errorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(_error ?? 'Error', style: const TextStyle(fontSize: 14, color: _textMuted)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _cargarPedidos,
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
