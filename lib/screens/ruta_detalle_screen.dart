import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_header.dart';
import 'editar_cliente_screen.dart';
import 'informacion_visita_screen.dart';

/// Umbral (días) para considerar la información de un cliente desactualizada:
/// solo cuando lleva más de un año sin actualizarse.
const int kUmbralDiasDesactualizado = 365;

/// Antigüedad legible ("hace 1 año y 3 meses") a partir de los días.
String formatAntiguedadDias(int dias) {
  if (dias < 0) dias = 0;
  if (dias < 30) return 'hace $dias ${dias == 1 ? 'día' : 'días'}';
  if (dias < 365) {
    final meses = (dias / 30).floor();
    return 'hace $meses ${meses == 1 ? 'mes' : 'meses'}';
  }
  final anios = dias ~/ 365;
  final meses = ((dias % 365) / 30).floor();
  final aTxt = 'hace $anios ${anios == 1 ? 'año' : 'años'}';
  return meses > 0 ? '$aTxt y $meses ${meses == 1 ? 'mes' : 'meses'}' : aTxt;
}

class RutaDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> ruta;
  final Map<String, dynamic> cliente;
  final Map<String, dynamic>? detalleSAP;

  const RutaDetalleScreen({
    super.key,
    required this.ruta,
    required this.cliente,
    this.detalleSAP,
  });

  @override
  State<RutaDetalleScreen> createState() => _RutaDetalleScreenState();
}

class _RutaDetalleScreenState extends State<RutaDetalleScreen> {
  final ApiEasyService _api = ApiEasyService();

  Map<String, dynamic>? _tareasData;
  bool _loadingTareas = true;

  String? _sugerenciaIA;
  bool _loadingIA = false;

  Map<String, dynamic>? _geo;
  bool _loadingGeo = true;
  String? _geoError;

  Map<String, dynamic>? _detalleSAP;
  bool _loadingDetalle = false;

  bool _visitaRegistrada = false;

  // ── Información desactualizada del cliente ────────────────────────────
  // El umbral (solo > 1 año) está en la constante global kUmbralDiasDesactualizado.

  // Se refresca localmente cuando el vendedor corrige los datos en la visita,
  // para ocultar el aviso de inmediato sin recargar la pantalla.
  String? _fechaActualizacionOverride;

  DateTime? get _ultimaActualizacionInfo {
    final raw = _fechaActualizacionOverride ??
        widget.ruta['fechaActualizacion'] ??
        widget.ruta['fechaCreacion'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  int? get _diasSinActualizar {
    final f = _ultimaActualizacionInfo;
    if (f == null) return null;
    return DateTime.now().difference(f).inDays;
  }

  bool get _infoDesactualizada =>
      (_diasSinActualizar ?? -1) >= kUmbralDiasDesactualizado;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  // Paleta monocromática: blanco / negro / gris
  static const Color _primary = Color(0xFF1F2937); // negro-gris (acento)
  static const Color _grayAccent = Color(0xFF6B7280); // gris

  @override
  void initState() {
    super.initState();
    _detalleSAP = widget.detalleSAP;
    _cargarTareas();
    _cargarSugerencia();
    _cargarUltimaVisita();
    if (_detalleSAP == null) {
      _cargarDetalleSAP().then((_) => _cargarGeocodificacion());
    } else {
      _cargarGeocodificacion();
    }
    // Al ingresar: avisar si la información del cliente está desactualizada.
    if (_infoDesactualizada) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _avisarInfoDesactualizada());
    }
  }

  /// Aviso al ingresar cuando la información del cliente está desactualizada.
  Future<void> _avisarInfoDesactualizada() async {
    if (!mounted) return;
    final dias = _diasSinActualizar ?? 0;
    final fecha = _formatFecha(
        widget.ruta['fechaActualizacion'] ?? widget.ruta['fechaCreacion']);
    await showAppDialog(
      context,
      child: AppDialogShell(
        icon: Icons.history_toggle_off_rounded,
        title: 'Información desactualizada',
        content: Text(
          'El cliente tiene la información desactualizada.\n\n'
          'Última actualización: $fecha (${formatAntiguedadDias(dias)}). '
          'Verifica dirección, teléfono y datos de contacto durante la visita.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
        ),
        actions: [
          appDialogAction(
            context,
            text: 'Entendido',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarDetalleSAP() async {
    final codigo = widget.cliente['id']?.toString() ?? '';
    if (codigo.isEmpty) return;
    setState(() => _loadingDetalle = true);
    final data = await _api.getCarteraCliente(codigo);
    if (mounted) setState(() { _detalleSAP = data; _loadingDetalle = false; });
  }

  Future<void> _cargarUltimaVisita() async {
    final codigo = widget.cliente['id']?.toString() ?? '';
    if (codigo.isEmpty) return;
    final v = await _api.getUltimaVisita(codigo);
    if (mounted && v != null) {
      setState(() => _visitaRegistrada = true);
    }
  }

  Future<void> _abrirVisita() async {
    HapticFeedback.selectionClick();
    final codigo = widget.cliente['id']?.toString() ?? '';

    // Verificar si el cliente ya fue visitado hoy (no se permite doble visita
    // salvo excepción justificada = segunda visita).
    bool segunda = false;
    String? motivoSegunda;
    final vh = await _api.getVisitasHoy(codigo);
    if (vh != null && vh['visitadoHoy'] == true) {
      if (!mounted) return;
      final motivo = await _dialogSegundaVisita(vh);
      if (motivo == null) return; // canceló → no abre la visita
      segunda = true;
      motivoSegunda = motivo;
    }

    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InformacionVisitaScreen(
          cliente: widget.cliente,
          ruta: widget.ruta,
          cartera: _detalleSAP,
          segundaVisita: segunda,
          motivoSegundaVisita: motivoSegunda,
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _visitaRegistrada = true);
    }
  }

  /// Diálogo cuando el cliente ya fue visitado hoy. Devuelve el motivo de la
  /// segunda visita, o null si el vendedor cancela.
  Future<String?> _dialogSegundaVisita(Map<String, dynamic> vh) {
    final ultima = vh['ultima']?.toString() ?? '';
    final horaTxt = ultima.length >= 16 ? ' (${ultima.substring(11)})' : '';
    return showAppInput(
      context,
      title: 'Cliente ya visitado hoy',
      subtitle:
          'Ya hay una visita registrada hoy$horaTxt. No se permite visitar dos veces el mismo día salvo una excepción (emergencia, etc.). Indica el motivo de la segunda visita:',
      hint: 'Ej: emergencia, entrega urgente, corrección…',
      icon: Icons.event_available_rounded,
      accent: _grayAccent,
      confirmText: 'Segunda visita',
      minLength: 4,
    );
  }

  Future<void> _cargarGeocodificacion() async {
    setState(() { _loadingGeo = true; _geoError = null; });
    final codigo = widget.cliente['id']?.toString() ?? '';
    if (codigo.isEmpty) {
      setState(() { _loadingGeo = false; _geoError = 'Sin código de cliente'; });
      return;
    }
    final addr = _direccionCompleta();
    final data = await _api.getGeocodeCliente(codigo, address: addr);
    if (!mounted) return;
    if (data == null) {
      setState(() { _loadingGeo = false; _geoError = 'No se pudo geocodificar la dirección'; });
    } else {
      setState(() { _geo = data; _loadingGeo = false; });
    }
  }

  Future<void> _cargarTareas() async {
    setState(() => _loadingTareas = true);
    final codigo = widget.cliente['id']?.toString() ?? '';
    final data = await _api.getTareasCliente(codigo);
    if (mounted) setState(() { _tareasData = data; _loadingTareas = false; });
  }

  Future<void> _cargarSugerencia() async {
    setState(() => _loadingIA = true);
    final codigo = widget.cliente['id']?.toString() ?? '';
    final txt = await _api.getSugerenciasIA(
      codigo,
      cliente: widget.cliente,
      ruta: widget.ruta,
    );
    if (mounted) setState(() { _sugerenciaIA = txt; _loadingIA = false; });
  }

  String _formatFecha(dynamic v) {
    if (v == null) return 'â€”';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
    } catch (_) {
      return v.toString();
    }
  }

  Color _colorEstado(String estado) {
    final e = estado.toUpperCase();
    if (e.contains('COMPLET') || e.contains('FINALIZ') || e.contains('CUMPLI')) return _primary;
    if (e.contains('PENDIENTE') || e.contains('PROGRAM') || e.contains('ACTIVA')) return _grayAccent;
    if (e.contains('CANCEL') || e.contains('VENCID')) return _grayAccent;
    return _primary;
  }

  String _direccionCompleta() {
    final dir = _detalleSAP?['direccion']?.toString().trim() ?? '';
    final ciudad = (_detalleSAP?['ciudad'] ?? widget.ruta['ciudad'] ?? '').toString().trim();
    final parts = [if (dir.isNotEmpty) dir, if (ciudad.isNotEmpty) ciudad, 'Colombia'];
    return parts.join(', ');
  }

  String _mapsLinkUrl() {
    if (_geo != null && _geo!['lat'] != null && _geo!['lng'] != null) {
      return 'https://www.google.com/maps/search/?api=1&query=${_geo!['lat']},${_geo!['lng']}';
    }
    final addr = Uri.encodeComponent(_direccionCompleta());
    return 'https://www.google.com/maps/search/?api=1&query=$addr';
  }

  Widget _buildMapaInteractivo() {
    if (_geo == null || _geo!['lat'] == null || _geo!['lng'] == null) {
      return const SizedBox.shrink();
    }
    final lat = (_geo!['lat'] as num).toDouble();
    final lng = (_geo!['lng'] as num).toDouble();
    final punto = LatLng(lat, lng);

    return SizedBox(
      height: 240,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: punto,
          initialZoom: 16,
          minZoom: 3,
          maxZoom: 19,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.oralplus.pedidos',
            maxZoom: 19,
          ),
          MarkerLayer(markers: [
            Marker(
              point: punto,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: Icon(Icons.location_on, color: AppTheme.errorColor, size: 40),
            ),
          ]),
          RichAttributionWidget(
            attributions: const [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

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
        titleSpacing: 0,
        title: AppBarTitle('Detalle de Ruta', subtitle: '#${widget.ruta['id'] ?? ''}'),
        actions: [_buildVisitaButton(), const SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _buildRutaCard(),
          if (_infoDesactualizada) ...[
            const SizedBox(height: 12),
            _buildAvisoDesactualizado(),
          ],
          const SizedBox(height: 16),
          _buildMapaCard(),
          const SizedBox(height: 16),
          _buildIACard(),
          const SizedBox(height: 16),
          _buildTareasSection(),
        ],
      ),
    );
  }

  Widget _buildVisitaButton() {
    final baseColor = _visitaRegistrada ? _primary : _primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _abrirVisita,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [baseColor, Color.lerp(baseColor, Colors.black, 0.12)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: baseColor.withOpacity(0.32), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_visitaRegistrada ? Icons.how_to_reg_rounded : Icons.add_task_rounded,
                color: Colors.white, size: 17),
            const SizedBox(width: 6),
            Text(_visitaRegistrada ? 'Visitado' : 'Visita',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
          ]),
        ),
      ),
    );
  }

  /// Banner persistente y clickeable: el cliente tiene la información
  /// desactualizada. Al tocarlo se abre la pantalla para corregir los datos.
  Widget _buildAvisoDesactualizado() {
    final dias = _diasSinActualizar ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _abrirEditarCliente,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.history_toggle_off_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cliente con información desactualizada',
                      style: TextStyle(color: _textDark, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Sin actualizar ${formatAntiguedadDias(dias)} · toca para actualizar los datos',
                      style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(9)),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.edit_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('Actualizar',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Abre la pantalla de edición de datos del cliente y, si se guardó,
  /// refresca la fecha localmente para ocultar el aviso.
  Future<void> _abrirEditarCliente() async {
    HapticFeedback.selectionClick();
    final rutaIdRaw = widget.ruta['id'];
    final rutaId = rutaIdRaw is int ? rutaIdRaw : int.tryParse('${rutaIdRaw ?? ''}');

    final resultado = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditarClienteScreen(
          cliente: widget.cliente,
          rutaId: rutaId,
          diasSinActualizar: _diasSinActualizar,
        ),
      ),
    );

    if (!mounted) return;
    if (resultado != null && resultado.isNotEmpty) {
      setState(() => _fechaActualizacionOverride = resultado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos del cliente actualizados'),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildRutaCard() {
    final r = widget.ruta;
    final estado = (r['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    final nombre = (r['nombre'] ?? 'Visita').toString();
    final ciudad = (r['ciudad'] ?? '').toString();
    final vendedor = (r['usuarioNombre'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.route_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(7)),
              child: Text(estado.isEmpty ? 'SIN ESTADO' : estado.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          ])),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (r['fechaProgramada'] != null)
            _whiteChip(Icons.event_rounded, 'Prog: ${_formatFecha(r['fechaProgramada'])}'),
          if (r['horaVisita'] != null)
            _whiteChip(Icons.access_time_rounded, 'Hora: ${r['horaVisita']}'),
          if (r['fechaCreacion'] != null)
            _whiteChip(Icons.history_rounded, 'Creada: ${_formatFecha(r['fechaCreacion'])}'),
          if (r['fechaActualizacion'] != null)
            _whiteChip(Icons.update_rounded, 'Actualiz: ${_formatFecha(r['fechaActualizacion'])}'),
          if (ciudad.isNotEmpty) _whiteChip(Icons.location_city_rounded, ciudad),
          if (vendedor.isNotEmpty) _whiteChip(Icons.person_rounded, vendedor),
        ]),
      ]),
    );
  }

  Widget _whiteChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildMapaCard() {
    final direccionOriginal = _direccionCompleta();
    final tieneDireccion = (_detalleSAP?['direccion']?.toString().trim().isNotEmpty ?? false);
    final formatted = _geo?['formattedAddress']?.toString();
    final direccionMostrar = formatted?.isNotEmpty == true ? formatted! : direccionOriginal;
    final tieneCoords = _geo != null && _geo!['lat'] != null && _geo!['lng'] != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: _primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.map_rounded, color: _primary, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Ubicación',
                    style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                if (tieneCoords)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('GEO',
                        style: TextStyle(color: _primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(
                tieneDireccion ? direccionMostrar : 'Sin dirección registrada',
                style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              if (tieneCoords)
                Text(
                  '${_geo!['lat'].toStringAsFixed(5)}, ${_geo!['lng'].toStringAsFixed(5)}',
                  style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.w700),
                ),
            ])),
            if (tieneDireccion) ...[
              IconButton(
                onPressed: _loadingGeo ? null : _cargarGeocodificacion,
                icon: Icon(Icons.refresh_rounded, color: _textMuted, size: 18),
                tooltip: 'Reintentar geocodificación',
                visualDensity: VisualDensity.compact,
              ),
              Tooltip(
                message: _mapsLinkUrl(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new_rounded, color: _primary, size: 14),
                    const SizedBox(width: 4),
                    Text('Maps',
                        style: TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        if (_loadingDetalle && !tieneDireccion)
          Container(
            height: 160,
            decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 10),
              Text('Cargando dirección del cliente...',
                  style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
          )
        else if (!tieneDireccion)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10)),
            child: Text('Este cliente no tiene dirección registrada en SAP.',
                style: TextStyle(color: _textMuted, fontSize: 12)),
          )
        else if (_loadingGeo)
          Container(
            height: 200,
            decoration: BoxDecoration(color: _bg, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 10),
              Text('Geocodificando dirección...',
                  style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
          )
        else if (!tieneCoords && _geoError != null)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.errorColor.withOpacity(0.15)),
            ),
            child: Row(children: [
              Icon(Icons.error_outline_rounded, color: AppTheme.errorColor, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_geoError!,
                  style: TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: _cargarGeocodificacion,
                child: const Text('Reintentar'),
              ),
            ]),
          )
        else
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: _buildMapaInteractivo(),
          ),
      ]),
    );
  }

  Widget _buildIACard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primary.withOpacity(0.08),
            _grayAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_primary, _grayAccent]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Asistente IA',
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800)),
            Text('Recomendaciones para esta visita',
                style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ])),
          IconButton(
            onPressed: _loadingIA ? null : _cargarSugerencia,
            icon: Icon(Icons.refresh_rounded, color: _primary, size: 20),
            tooltip: 'Regenerar',
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primary.withOpacity(0.15)),
          ),
          child: _loadingIA
              ? Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('Pensando...', style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600)),
                ])
              : SelectableText(
                  _sugerenciaIA?.isNotEmpty == true
                      ? _sugerenciaIA!
                      : 'Sin sugerencias por ahora. Toca el botón de refrescar para reintentar.',
                  style: TextStyle(color: _textDark, fontSize: 13, height: 1.55, fontWeight: FontWeight.w500),
                ),
        ),
      ]),
    );
  }

  Widget _buildTareasSection() {
    final d = _tareasData;
    final tareas = (d?['tareas'] as List<dynamic>?) ?? [];
    final total = d?['total'] ?? 0;
    final cumplidas = d?['cumplidas'] ?? 0;
    final activas = d?['activas'] ?? 0;
    final promedio = d?['promedio'] ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Tareas asignadas',
            style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        const SizedBox(width: 8),
        if (!_loadingTareas && total > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$total',
                style: TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
      ]),
      const SizedBox(height: 10),
      if (_loadingTareas)
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: const Center(child: CircularProgressIndicator()),
        )
      else if (tareas.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Icon(Icons.task_alt_rounded, color: _textMuted.withOpacity(0.6)),
            const SizedBox(width: 10),
            Expanded(child: Text('Sin tareas asignadas a este cliente',
                style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500))),
          ]),
        )
      else ...[
        Row(children: [
          Expanded(child: _miniStat('Cumplidas', '$cumplidas', _primary, Icons.check_circle_rounded)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat('Activas', '$activas', _grayAccent, Icons.schedule_rounded)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat('Promedio', '$promedio%', _primary, Icons.trending_up_rounded)),
        ]),
        const SizedBox(height: 10),
        ...tareas.map((raw) {
          final t = Map<String, dynamic>.from(raw as Map);
          return _tareaCard(t);
        }),
      ],
    ]);
  }

  Widget _tareaCard(Map<String, dynamic> t) {
    final cumplida = t['cumplida'] == true;
    final activa = t['activa'] == true;
    final color = cumplida ? _primary : (activa ? _grayAccent : _textMuted);
    final icon = cumplida ? Icons.check_circle_rounded : (activa ? Icons.radio_button_unchecked_rounded : Icons.pause_circle_outline_rounded);
    final estado = cumplida ? 'CUMPLIDA' : (activa ? 'ACTIVA' : 'INACTIVA');
    final tarea = (t['tarea'] ?? '').toString();
    final lista = (t['lista'] ?? '').toString();
    final subcanal = (t['subcanal'] ?? '').toString();
    final porc = t['porcentajeFinal'];
    final comentario = (t['comentario'] ?? '').toString();
    final estadoVend = (t['estadoVendedor'] ?? '').toString();
    final vendedor = (t['vendedor'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tarea.isEmpty ? '(sin descripción)' : tarea,
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('#${t['id']} Â· Lote ${t['loteCarga'] ?? 'â€”'}',
                style: TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(estado,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ),
        ]),
        if (porc != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (porc as num).toDouble().clamp(0, 100) / 100,
                  minHeight: 6,
                  backgroundColor: _border.withOpacity(0.5),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$porc%',
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (lista.isNotEmpty) _chip(Icons.list_rounded, lista),
          if (subcanal.isNotEmpty) _chip(Icons.category_rounded, subcanal),
          if (vendedor.isNotEmpty) _chip(Icons.person_rounded, vendedor),
          if (estadoVend.isNotEmpty) _chip(Icons.flag_rounded, 'Vend: $estadoVend'),
          if (t['fechaCarga'] != null) _chip(Icons.upload_rounded, 'Carga: ${_formatFecha(t['fechaCarga'])}'),
          if (t['fechaCumplida'] != null) _chip(Icons.check_rounded, 'Cumplida: ${_formatFecha(t['fechaCumplida'])}'),
        ]),
        if (comentario.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(9)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.comment_rounded, size: 14, color: _textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(comentario,
                  style: TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic))),
            ]),
          ),
        ],
      ]),
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

  Widget _miniStat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.8), size: 12),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
