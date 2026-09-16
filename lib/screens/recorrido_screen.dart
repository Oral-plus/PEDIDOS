import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_easy_service.dart';
import '../services/rastreo/estado_ubicacion_cliente.dart';
import '../services/rastreo/rastreo_ubicacion.dart';

class RecorridoScreen extends StatefulWidget {
  final String? usuarioCodigo;
  final String? usuarioNombre;

  const RecorridoScreen({super.key, this.usuarioCodigo, this.usuarioNombre});

  static String fechaTexto(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String horaDe(String? fecha) {
    final t = (fecha ?? '').trim();
    if (t.length < 16) return '—';
    final h = int.tryParse(t.substring(11, 13)) ?? 0;
    final m = t.substring(14, 16);
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h < 12 ? 'a. m.' : 'p. m.'}';
  }

  static String origenTexto(String? origen) {
    switch (origen) {
      case 'visita_inicio':
        return 'Inicio de visita';
      case 'visita_fin':
        return 'Fin de visita';
      case 'inicio_sesion':
        return 'Inicio de jornada';
      case 'pedido':
        return 'Pedido';
      case 'manual':
        return 'Validación manual';
      default:
        return 'Registro automático';
    }
  }

  @override
  State<RecorridoScreen> createState() => _RecorridoScreenState();
}

class _RecorridoScreenState extends State<RecorridoScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _azul = Color(0xFF1A56DB);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _ambar = Color(0xFFD97706);

  final ApiEasyService _api = ApiEasyService();
  DateTime _fecha = DateTime.now();
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _puntos = [];
  Map<String, dynamic> _resumen = {};
  EstadoRastreo? _estado;
  bool _activando = false;

  bool get _propio => widget.usuarioCodigo == null;

  bool get _esHoy {
    final h = DateTime.now();
    return _fecha.year == h.year && _fecha.month == h.month && _fecha.day == h.day;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _api.getRecorrido(fecha: RecorridoScreen.fechaTexto(_fecha), usuario: widget.usuarioCodigo);
    EstadoRastreo? estado;
    if (_propio && RastreoUbicacion.disponible) {
      try {
        estado = await RastreoUbicacion.estado();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _estado = estado;
      if (res['success'] == true) {
        _puntos = ((res['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _resumen = Map<String, dynamic>.from((res['resumen'] as Map?) ?? {});
      } else {
        _puntos = [];
        _resumen = {};
        _error = res['message']?.toString() ?? 'No se pudo cargar el recorrido';
      }
    });
  }

  Future<void> _activar() async {
    if (_activando) return;
    setState(() => _activando = true);
    await RastreoUbicacion.asegurar(context, forzar: true);
    if (!mounted) return;
    setState(() => _activando = false);
    _cargar();
  }

  void _moverDia(int dias) {
    final nueva = _fecha.add(Duration(days: dias));
    if (nueva.isAfter(DateTime.now())) return;
    HapticFeedback.selectionClick();
    setState(() => _fecha = nueva);
    _cargar();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (elegida == null || !mounted) return;
    setState(() => _fecha = elegida);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (widget.usuarioNombre ?? '').trim();
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_propio ? 'Mi recorrido' : 'Recorrido',
              style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
          if (!_propio && nombre.isNotEmpty)
            Text(nombre, style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded, color: _ink),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _selectorFecha(),
            if (_propio && _estado != null) ...[
              const SizedBox(height: 12),
              _tarjetaEstado(_estado!),
            ],
            const SizedBox(height: 12),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _mensaje(Icons.cloud_off_rounded, _error!)
            else if (_puntos.isEmpty)
              _mensaje(Icons.location_off_rounded, 'No hay ubicaciones registradas en esta fecha')
            else ...[
              _resumenTarjetas(),
              const SizedBox(height: 12),
              _mapa(),
              const SizedBox(height: 16),
              const Text('DETALLE DEL RECORRIDO',
                  style: TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              ..._puntos.reversed.map(_filaPunto),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectorFecha() {
    final texto = _esHoy
        ? 'Hoy'
        : '${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}';
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left_rounded, color: _ink), onPressed: _cargando ? null : () => _moverDia(-1)),
        Expanded(
          child: InkWell(
            onTap: _cargando ? null : _elegirFecha,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: _azul),
                const SizedBox(width: 8),
                Text(texto, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right_rounded, color: _esHoy ? _line : _ink),
          onPressed: _cargando || _esHoy ? null : () => _moverDia(1),
        ),
      ]),
    );
  }

  Widget _tarjetaEstado(EstadoRastreo e) {
    final String titulo;
    final String detalle;
    final Color color;
    if (e.completo) {
      titulo = 'Rastreo activo';
      final ultima = e.ultimaCaptura;
      detalle = ultima == null
          ? 'Se registra tu ubicación cada 15 minutos'
          : 'Última ubicación ${RecorridoScreen.horaDe(ultima.toString())}${e.pendientes > 0 ? ' · ${e.pendientes} por enviar' : ''}';
      color = _verde;
    } else if (!e.gpsEncendido) {
      titulo = 'GPS apagado';
      detalle = 'Enciende la ubicación del dispositivo';
      color = _rojo;
    } else if (!e.servicioActivo) {
      titulo = 'Rastreo detenido';
      detalle = 'Actívalo para registrar tu recorrido';
      color = _rojo;
    } else {
      titulo = 'Rastreo parcial';
      detalle = 'Falta "Permitir todo el tiempo": con la app cerrada no se registra';
      color = _ambar;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(e.completo ? Icons.satellite_alt_rounded : Icons.warning_amber_rounded, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(color: color, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(detalle, style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (!e.completo)
          TextButton(
            onPressed: _activando ? null : _activar,
            child: _activando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Activar', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }

  Widget _resumenTarjetas() {
    int entero(String k) => (_resumen[k] as num?)?.toInt() ?? 0;
    final km = (_resumen['distanciaKm'] as num?)?.toDouble() ?? 0;
    final simuladas = entero('simuladas');
    Widget dato(String etiqueta, String valor, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
            child: Column(children: [
              Text(valor, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(etiqueta, textAlign: TextAlign.center, style: const TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return Row(children: [
      dato('Registros', '${entero('puntos')}', _ink),
      const SizedBox(width: 8),
      dato('En cliente', '${entero('enCliente')}', _verde),
      const SizedBox(width: 8),
      dato('Simuladas', '$simuladas', simuladas > 0 ? _rojo : _gray),
      const SizedBox(width: 8),
      dato('Km', km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ','), _azul),
    ]);
  }

  LatLng _latLng(Map<String, dynamic> p) =>
      LatLng((p['latitud'] as num).toDouble(), (p['longitud'] as num).toDouble());

  Color _colorPunto(Map<String, dynamic> p) {
    if (p['simulada'] == true) return _rojo;
    if (p['enCliente'] == true) return _verde;
    return _azul;
  }

  Widget _mapa() {
    final validos = _puntos.where((p) => p['latitud'] is num && p['longitud'] is num).toList();
    if (validos.isEmpty) return const SizedBox.shrink();
    final ruta = validos.where((p) => p['simulada'] != true).map(_latLng).toList();
    final todos = validos.map(_latLng).toList();
    final unico = todos.length == 1 ||
        todos.every((p) => (p.latitude - todos.first.latitude).abs() < 0.00001 && (p.longitude - todos.first.longitude).abs() < 0.00001);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 280,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: todos.last,
            initialZoom: 16,
            initialCameraFit: unico
                ? null
                : CameraFit.bounds(bounds: LatLngBounds.fromPoints(todos), padding: const EdgeInsets.all(36), maxZoom: 17),
            minZoom: 3,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.oralplus.pedidos',
              maxZoom: 19,
            ),
            if (ruta.length > 1)
              PolylineLayer(polylines: [Polyline(points: ruta, strokeWidth: 3.5, color: _azul.withOpacity(0.75))]),
            MarkerLayer(
              markers: [
                for (var i = 0; i < validos.length; i++)
                  Marker(
                    point: todos[i],
                    width: i == validos.length - 1 ? 22 : 14,
                    height: i == validos.length - 1 ? 22 : 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _colorPunto(validos[i]),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaPunto(Map<String, dynamic> p) {
    final color = _colorPunto(p);
    final cliente = (p['clienteCodigo'] ?? '').toString();
    final distancia = (p['distanciaClienteM'] as num?)?.toInt();
    final precision = (p['precisionM'] as num?)?.toDouble();
    final partes = <String>[
      RecorridoScreen.origenTexto(p['origen']?.toString()),
      if (cliente.isNotEmpty)
        p['enCliente'] == true
            ? 'En cliente $cliente${distancia != null ? ' (${EstadoUbicacionCliente.distanciaTexto(distancia)})' : ''}'
            : 'Fuera de $cliente${distancia != null ? ' (${EstadoUbicacionCliente.distanciaTexto(distancia)})' : ''}',
      if (precision != null) 'Precisión ${precision.round()} m',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(
            p['simulada'] == true
                ? Icons.gps_off_rounded
                : (p['enCliente'] == true ? Icons.where_to_vote_rounded : Icons.place_rounded),
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(RecorridoScreen.horaDe(p['fecha']?.toString()),
                  style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
              if (p['simulada'] == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _rojo.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: const Text('SIMULADA', style: TextStyle(color: _rojo, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(partes.join(' · '), style: const TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _mensaje(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icono, size: 44, color: _gray),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: _gray, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );
}
