import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/price_utils.dart';
import 'cuadre_detalle_screen.dart';

class CuadreCajaScreen extends StatefulWidget {
  const CuadreCajaScreen({super.key});

  @override
  State<CuadreCajaScreen> createState() => _CuadreCajaScreenState();
}

class _CuadreCajaScreenState extends State<CuadreCajaScreen>
    with SingleTickerProviderStateMixin {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _ambar = Color(0xFFB45309);

  final ApiEasyService _api = ApiEasyService();
  late final TabController _tabs;

  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _cuadrados = [];
  double _totalPendiente = 0;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final pend = await _api.getRecaudosCuadre(estado: 'pendiente');
    final cuad = await _api.getRecaudosCuadre(estado: 'cuadrado');
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _pendientes = (pend['data'] as List).cast<Map<String, dynamic>>();
      _cuadrados = (cuad['data'] as List).cast<Map<String, dynamic>>();
      _totalPendiente = (pend['valorTotal'] as num?)?.toDouble() ?? 0;
      if (pend['success'] != true) {
        _error = pend['message']?.toString() ?? 'No se pudieron cargar los recaudos';
      }
    });
  }

  String _pesos(num v) => PriceUtils.formatPriceDisplay(v.toDouble());

  String _fecha(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}  $hh:$mi';
  }

  Future<void> _abrir(Map<String, dynamic> r) async {
    HapticFeedback.selectionClick();
    final hecho = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CuadreDetalleScreen(
          recaudoId: (r['recaudoId'] as num).toInt(),
          clienteNombre: (r['clienteNombre'] ?? '').toString(),
        ),
      ),
    );
    if (hecho == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(children: [
        _header(),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: _ink,
            unselectedLabelColor: _gray,
            indicatorColor: _ink,
            indicatorWeight: 2.4,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.3),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            tabs: [
              Tab(text: 'PENDIENTES (${_pendientes.length})'),
              Tab(text: 'CUADRADOS (${_cuadrados.length})'),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _lista(_pendientes, pendiente: true),
                    _lista(_cuadrados, pendiente: false),
                  ],
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
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 14),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Image.asset(AppAssets.logo, height: 20, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_wallet_rounded, color: _ink, size: 18)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cuadre de caja',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Recaudos en efectivo',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w500)),
                ]),
              ),
              IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh_rounded, color: Colors.white)),
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Pendiente por cuadrar',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(_pesos(_totalPendiente),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> filas, {required bool pendiente}) {
    if (_error != null && pendiente) {
      return _vacio(Icons.error_outline_rounded, _error!, const Color(0xFFDC2626));
    }
    if (filas.isEmpty) {
      return _vacio(
        pendiente ? Icons.check_circle_outline_rounded : Icons.inbox_rounded,
        pendiente ? 'No tienes recaudos en efectivo por cuadrar' : 'Todavía no has cuadrado ningún recaudo',
        pendiente ? _verde : _gray,
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: filas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _tarjeta(filas[i], pendiente),
      ),
    );
  }

  Widget _vacio(IconData icono, String texto, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 46, color: color),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center,
              style: const TextStyle(color: _gray, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> r, bool pendiente) {
    final recibo = r['reciboCaja'];
    final cuadre = r['cuadre'] is Map ? Map<String, dynamic>.from(r['cuadre'] as Map) : null;
    return GestureDetector(
      onTap: () => _abrir(r),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: (pendiente ? _ambar : _verde).withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(pendiente ? Icons.pending_actions_rounded : Icons.verified_rounded,
                color: pendiente ? _ambar : _verde, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['clienteNombre'] ?? '').toString().isEmpty
                      ? (r['clienteId'] ?? '').toString()
                      : (r['clienteNombre'] ?? '').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${r['numeroRecaudo']}${recibo != null ? '  ·  Recibo N° $recibo' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(pendiente
                      ? _fecha(r['fecha'])
                      : 'Consignado en ${cuadre?['banco'] ?? ''}  ·  ${_fecha(cuadre?['fecha'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_pesos((r['valor'] as num?)?.toDouble() ?? 0),
                style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Icon(Icons.chevron_right_rounded, color: _gray.withOpacity(0.7), size: 20),
          ]),
        ]),
      ),
    );
  }
}
