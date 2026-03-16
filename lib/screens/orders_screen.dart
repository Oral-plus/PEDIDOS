import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../utils/theme.dart';
import '../utils/price_utils.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _isLoading = true;
  String? _error;
  String _filtroEstado = 'TODOS';

  static const _textDark = AppTheme.primaryBlue;
  static const _textMuted = AppTheme.secondaryBlue;
  static const _border = Color(0xFFE5E7EB);

  static const _baseUrl = 'http://localhost:3000';

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    final codigo = context.read<SessionProvider>().codigoCliente;
    if (codigo.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'Sin cliente seleccionado'; });
      return;
    }

    if (mounted) setState(() { _isLoading = true; _error = null; });
    try {
      final url = '$_baseUrl/api/orders?cliente=$codigo';
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
    if (_filtroEstado == 'TODOS') return _pedidos;
    return _pedidos.where((p) => p['estado'] == _filtroEstado).toList();
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

  String _fmtMoney(dynamic v) => PriceUtils.formatPriceDisplay((v as num?)?.toDouble() ?? 0.0);

  Color _estadoColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'PENDIENTE': return const Color(0xFFF59E0B);
      case 'CONFIRMADO': return AppTheme.primaryBlue;
      case 'EN_PROCESO': case 'EN PROCESO': return const Color(0xFF8B5CF6);
      case 'ENVIADO': return const Color(0xFF06B6D4);
      case 'ENTREGADO': return AppTheme.successColor;
      case 'CANCELADO': return AppTheme.errorColor;
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
    return Column(
      children: [
        _header(),
        _filterChips(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
              : _error != null
                  ? _errorWidget()
                  : _pedidosFiltrados.isEmpty
                      ? _emptyWidget()
                      : RefreshIndicator(
                          onRefresh: _cargarPedidos,
                          color: AppTheme.primaryBlue,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                            itemCount: _pedidosFiltrados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _pedidoCard(_pedidosFiltrados[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mis Pedidos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textDark, letterSpacing: -0.5)),
                    SizedBox(height: 2),
                    Text('Historial y seguimiento', style: TextStyle(fontSize: 13, color: _textMuted)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _cargarPedidos,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                  child: const Icon(Icons.refresh_rounded, color: _textMuted, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final filtros = ['TODOS', 'PENDIENTE', 'CONFIRMADO', 'ENVIADO', 'ENTREGADO', 'CANCELADO'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: filtros.map((f) {
            final isActive = _filtroEstado == f;
            final color = f == 'TODOS' ? AppTheme.primaryBlue : _estadoColor(f);
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                _miniStat(Icons.shopping_bag_outlined, '${p['totalProductos'] ?? 0} productos'),
                const SizedBox(width: 16),
                _miniStat(Icons.inventory_2_outlined, '${p['totalUnidades'] ?? 0} unidades'),
                const Spacer(),
                Text(_fmtMoney(p['total']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
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
          const Text('Aún no has realizado pedidos para este cliente', style: TextStyle(fontSize: 14, color: _textMuted), textAlign: TextAlign.center),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
