import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import 'dashboard_screen.dart';
import 'ruta_detalle_screen.dart';

class RuteroScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic>? detalle;

  const RuteroScreen({
    super.key,
    required this.cliente,
    this.detalle,
  });

  @override
  State<RuteroScreen> createState() => _RuteroScreenState();
}

class _RuteroScreenState extends State<RuteroScreen> {
  final ApiEasyService _api = ApiEasyService();
  Map<String, dynamic>? _rutasData;
  bool _loadingRutas = true;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;

  @override
  void initState() {
    super.initState();
    _cargarRutas();
  }

  Future<void> _cargarRutas() async {
    setState(() => _loadingRutas = true);
    final codigo = widget.cliente['id']?.toString() ?? '';
    final data = await _api.getRutasCliente(codigo);
    if (mounted) setState(() { _rutasData = data; _loadingRutas = false; });
  }

  void _verCatalogo() {
    HapticFeedback.mediumImpact();
    final codigo = widget.cliente['id']?.toString() ?? '';
    if (codigo.isEmpty) return;

    final sap = widget.detalle;
    context.read<SessionProvider>().setClienteData(
      codigo: codigo,
      nombre: sap?['nombre']?.toString() ??
          widget.cliente['nombre']?.toString() ??
          widget.cliente['cardName']?.toString() ??
          '',
      direccion: sap?['direccion']?.toString() ?? '',
      telefono: sap?['telefono']?.toString() ?? '',
      correo: '',
      vendedor: sap?['vendedor']?.toString() ?? '',
      ciudad: sap?['ciudad']?.toString() ?? '',
      balance: (sap?['balance'] as num?)?.toDouble() ?? 0,
    );

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DashboardScreen(),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  String _formatFecha(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
    } catch (_) {
      return v.toString();
    }
  }

  String _formatFechaCorta(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }

  Color _colorEstado(String estado) {
    final e = estado.toUpperCase();
    if (e.contains('COMPLET') || e.contains('FINALIZ')) return AppTheme.successColor;
    if (e.contains('PENDIENTE') || e.contains('PROGRAM')) return AppTheme.accentColor;
    if (e.contains('CANCEL')) return AppTheme.errorColor;
    return AppTheme.primaryBlue;
  }

  IconData _iconoEstado(String estado) {
    final e = estado.toUpperCase();
    if (e.contains('COMPLET') || e.contains('FINALIZ')) return Icons.check_circle_rounded;
    if (e.contains('PENDIENTE') || e.contains('PROGRAM')) return Icons.schedule_rounded;
    if (e.contains('CANCEL')) return Icons.cancel_rounded;
    return Icons.alt_route_rounded;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    final nombre = (widget.cliente['nombre'] ??
            widget.cliente['cardName'] ??
            widget.cliente['nombre1'] ??
            'Cliente')
        .toString();
    final codigo = widget.cliente['id']?.toString() ?? '';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: _textDark,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.alt_route_rounded, color: AppTheme.successColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rutero',
                    style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w800)),
                Text('Acciones y rutas',
                    style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadingRutas ? null : _cargarRutas,
            icon: Icon(Icons.refresh_rounded, color: _textMuted, size: 20),
            tooltip: 'Recargar rutas',
          ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _buildClienteHeader(nombre, codigo),
          const SizedBox(height: 18),
          _buildSeccionTitle('Acciones'),
          const SizedBox(height: 10),
          _accionCard(
            icon: Icons.shopping_bag_rounded,
            color: AppTheme.successColor,
            title: 'Ver Catálogo',
            subtitle: 'Crear pedido para el cliente',
            onTap: _verCatalogo,
          ),
          const SizedBox(height: 22),
          _buildSeccionRutas(),
        ],
      ),
    );
  }

  Widget _buildSeccionRutas() {
    final d = _rutasData;
    final rutas = (d?['rutas'] as List<dynamic>?) ?? [];
    final total = d?['total'] ?? 0;
    final completadas = d?['completadas'] ?? 0;
    final pendientes = d?['pendientes'] ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Rutas registradas',
            style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        const SizedBox(width: 8),
        if (!_loadingRutas && total > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$total',
                style: TextStyle(color: AppTheme.primaryBlue, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
      ]),
      const SizedBox(height: 10),
      if (_loadingRutas)
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: const Center(child: CircularProgressIndicator()),
        )
      else if (d == null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: _textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text('No se pudieron cargar las rutas',
                style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500))),
            TextButton(onPressed: _cargarRutas, child: const Text('Reintentar')),
          ]),
        )
      else if (rutas.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Icon(Icons.route_outlined, color: _textMuted.withOpacity(0.6)),
            const SizedBox(width: 10),
            Expanded(child: Text('Sin rutas registradas para este cliente',
                style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500))),
          ]),
        )
      else ...[
        Row(children: [
          Expanded(child: _miniStat('Completadas', '$completadas', AppTheme.successColor, Icons.check_circle_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _miniStat('Pendientes', '$pendientes', AppTheme.accentColor, Icons.schedule_rounded)),
        ]),
        const SizedBox(height: 10),
        ...rutas.map((raw) {
          final r = Map<String, dynamic>.from(raw as Map);
          return _ruteroItem(r);
        }),
      ],
    ]);
  }

  Widget _ruteroItem(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    final icon = _iconoEstado(estado);
    final nombre = (r['nombre'] ?? 'Ruta').toString();
    final ciudad = (r['ciudad'] ?? '').toString();
    final vendedor = (r['usuarioNombre'] ?? '').toString();
    final fechaProgramada = r['fechaProgramada'];
    final fechaCreacion = r['fechaCreacion'];
    final hora = r['horaVisita']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => RutaDetalleScreen(
                  ruta: r,
                  cliente: widget.cliente,
                  detalleSAP: widget.detalle,
                ),
                transitionsBuilder: (_, a, __, c) => SlideTransition(
                  position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
                      .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: c,
                ),
                transitionDuration: const Duration(milliseconds: 350),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre,
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('#${r['id']}',
                style: TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          ])),
          if (estado.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(estado.toUpperCase(),
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          if (fechaProgramada != null)
            _chip(Icons.event_rounded, 'Prog: ${_formatFechaCorta(fechaProgramada)}${hora.isNotEmpty ? ' $hora' : ''}'),
          if (fechaCreacion != null)
            _chip(Icons.history_rounded, 'Creada: ${_formatFecha(fechaCreacion)}'),
          if (ciudad.isNotEmpty) _chip(Icons.location_city_rounded, ciudad),
          if (vendedor.isNotEmpty) _chip(Icons.person_rounded, vendedor),
        ]),
      ]),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border.withOpacity(0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: _textMuted),
        const SizedBox(width: 5),
        Text(text,
            style: TextStyle(color: _textDark, fontSize: 11, fontWeight: FontWeight.w600)),
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
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _buildClienteHeader(String nombre, String codigo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.successColor, AppTheme.successColor.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: AppTheme.successColor.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(codigo,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          ),
        ])),
      ]),
    );
  }

  Widget _buildSeccionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    );
  }

  Widget _accionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
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
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            ])),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.arrow_forward_rounded, color: color, size: 17),
            ),
          ]),
        ),
      ),
    );
  }
}
