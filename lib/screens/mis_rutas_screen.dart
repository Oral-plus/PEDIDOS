import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import '../widgets/app_header.dart';
import '../widgets/ruta_extra_sheet.dart';
import 'ruta_detalle_screen.dart';

class MisRutasScreen extends StatefulWidget {
  const MisRutasScreen({super.key});

  @override
  State<MisRutasScreen> createState() => _MisRutasScreenState();
}

class _MisRutasScreenState extends State<MisRutasScreen> {
  final ApiEasyService _api = ApiEasyService();

  String _periodo = 'hoy';
  Map<String, dynamic>? _data;
  bool _loading = true;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  // Paleta monocromática (el verde solo se usa para "Visitado")
  static const Color _primary = Color(0xFF1F2937); // negro-gris
  static const Color _grayAccent = Color(0xFF6B7280); // gris

  static const List<Map<String, String>> _periodos = [
    {'key': 'hoy', 'label': 'Hoy'},
    {'key': 'semana', 'label': 'Semana'},
    {'key': 'mes', 'label': 'Mes'},
    {'key': 'todas', 'label': 'Todas'},
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() => _loading = true);
    final data = await _api.getMisRutas(periodo: _periodo, forzar: forzar);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  void _cambiarPeriodo(String p) {
    if (p == _periodo) return;
    HapticFeedback.selectionClick();
    setState(() => _periodo = p);
    _cargar();
  }

  // Rojo de urgencia: reservado para la acción de ruta extra.
  static const Color _rojoExtra = Color(0xFFDC2626);

  Future<void> _abrirRutaExtra() async {
    HapticFeedback.mediumImpact();
    final creado = await showRutaExtraSheet(context);
    if (creado && mounted) {
      // Aseguramos que la ruta nueva (programada para hoy) sea visible.
      if (_periodo != 'hoy') {
        setState(() => _periodo = 'hoy');
      }
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ruta extra agregada correctamente'),
            backgroundColor: _rojoExtra,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatFecha(dynamic v, {bool soloFecha = false}) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final fecha = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      if (soloFecha) return fecha;
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$fecha $hh:$mm';
    } catch (_) {
      return v.toString();
    }
  }

  Color _colorEstado(String estado) {
    final e = estado.toUpperCase();
    // Paleta monocromática: los estados usan gris/negro. El verde queda
    // reservado únicamente para las tarjetas ya "Visitado" (visitadoHoy).
    if (e.contains('COMPLET') || e.contains('FINALIZ')) return _primary;
    if (e.contains('PENDIENTE') || e.contains('PROGRAM') || e.contains('ACTIVA')) return _grayAccent;
    if (e.contains('CANCEL')) return _grayAccent;
    return _primary;
  }

  IconData _iconoEstado(String estado) {
    final e = estado.toUpperCase();
    if (e.contains('COMPLET') || e.contains('FINALIZ')) return Icons.check_circle_rounded;
    if (e.contains('PENDIENTE') || e.contains('PROGRAM') || e.contains('ACTIVA')) return Icons.schedule_rounded;
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

    final rutas = (_data?['rutas'] as List<dynamic>?) ?? [];
    final total = _data?['total'] ?? 0;
    final completadas = _data?['completadas'] ?? 0;
    final pendientes = _data?['pendientes'] ?? 0;
    final clientesUnicos = _data?['clientesUnicos'] ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirRutaExtra,
        backgroundColor: _rojoExtra,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_road_rounded, size: 22),
        label: const Text('Ruta Extra',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.2)),
      ),
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
        titleSpacing: 0,
        title: Row(children: [
          Expanded(
            child: AppBarTitle('Mis Rutas',
                subtitle: _periodos.firstWhere((p) => p['key'] == _periodo)['label']!),
          ),
          IconButton(
            onPressed: _loading ? null : _cargar,
            icon: Icon(Icons.refresh_rounded, color: _textMuted, size: 20),
          ),
        ]),
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Row(children: _periodos.map((p) {
            final activo = _periodo == p['key'];
            return Expanded(
              child: GestureDetector(
                onTap: () => _cambiarPeriodo(p['key']!),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activo ? _primary : _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: activo ? _primary : _border),
                  ),
                  child: Center(
                    child: Text(
                      p['label']!,
                      style: TextStyle(
                        color: activo ? Colors.white : _textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList()),
        ),
        if (!_loading && _data != null && total > 0)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(child: _stat('Total', '$total', _primary, Icons.list_alt_rounded)),
              const SizedBox(width: 6),
              Expanded(child: _stat('Pendientes', '$pendientes', _grayAccent, Icons.schedule_rounded)),
              const SizedBox(width: 6),
              Expanded(child: _stat('Cumplidas', '$completadas', _primary, Icons.check_circle_rounded)),
              const SizedBox(width: 6),
              Expanded(child: _stat('Clientes', '$clientesUnicos', _grayAccent, Icons.storefront_rounded)),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (rutas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.route_outlined, size: 50, color: _textMuted.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text('Sin rutas en este periodo',
                              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _cargar(forzar: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: rutas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = Map<String, dynamic>.from(rutas[i] as Map);
                          return _rutaCard(r);
                        },
                      ),
                    )),
        ),
      ]),
    );
  }

  Widget _rutaCard(Map<String, dynamic> r) {
    final estado = (r['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    final icon = _iconoEstado(estado);
    final nombre = (r['nombre'] ?? 'Ruta').toString();
    final ciudad = (r['ciudad'] ?? '').toString();
    final clienteId = (r['clienteId'] ?? '').toString();
    final fechaProgramada = r['fechaProgramada'];
    final hora = r['horaVisita']?.toString() ?? '';
    final visitado = r['visitadoHoy'] == true;
    final esExtra = r['esExtra'] == true;
    final motivoExtra = (r['motivoExtra'] ?? '').toString();
    // Cuando el cliente ya fue visitado hoy, toda la tarjeta se pone verde.
    final acento = visitado ? AppTheme.successColor : color;

    return Container(
      decoration: BoxDecoration(
        color: visitado
            ? AppTheme.successColor.withOpacity(0.10)
            : (esExtra ? _rojoExtra.withOpacity(0.05) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: visitado
              ? AppTheme.successColor.withOpacity(0.55)
              : (esExtra ? _rojoExtra.withOpacity(0.45) : color.withOpacity(0.18)),
          width: (visitado || esExtra) ? 1.4 : 1,
        ),
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
                  cliente: {
                    'id': clienteId,
                    'nombre': nombre.replaceFirst(RegExp(r'^visita\s+a\s+', caseSensitive: false), ''),
                  },
                  detalleSAP: null,
                ),
                transitionsBuilder: (_, a, __, c) => SlideTransition(
                  position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
                      .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: c,
                ),
                transitionDuration: const Duration(milliseconds: 250),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: acento.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
                  child: Icon(visitado ? Icons.check_circle_rounded : icon, color: acento, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre,
                      style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('#${r['id']}${clienteId.isNotEmpty ? ' · $clienteId' : ''}',
                      style: TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                ])),
                if (esExtra && !visitado) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _rojoExtra.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.bolt_rounded, color: _rojoExtra, size: 11),
                      SizedBox(width: 2),
                      Text('EXTRA',
                          style: TextStyle(color: _rojoExtra, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                    ]),
                  ),
                  const SizedBox(width: 5),
                ],
                if (visitado)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 11),
                      const SizedBox(width: 3),
                      const Text('VISITADO',
                          style: TextStyle(color: AppTheme.successColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                    ]),
                  )
                else if (estado.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(estado.toUpperCase(),
                        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                  ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (fechaProgramada != null)
                  _chip(Icons.event_rounded, '${_formatFecha(fechaProgramada, soloFecha: true)}${hora.isNotEmpty ? ' · $hora' : ''}'),
                if (ciudad.isNotEmpty) _chip(Icons.location_city_rounded, ciudad),
                if (esExtra && motivoExtra.isNotEmpty) _chipRojo(Icons.flag_rounded, motivoExtra),
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
        Icon(icon, size: 11, color: _textMuted),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: _textDark, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // Chip rojo para el motivo de una ruta extra.
  Widget _chipRojo(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _rojoExtra.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _rojoExtra.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: _rojoExtra),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: _rojoExtra, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label,
            style: TextStyle(color: color.withOpacity(0.75), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
