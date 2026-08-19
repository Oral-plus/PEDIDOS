import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/session_provider.dart';
import '../providers/visita_activa_provider.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import '../widgets/app_header.dart';
import 'encuesta_visita_screen.dart';
import 'forma_pago_screen.dart';
import 'gestion_pedido_screen.dart';
import 'products.dart';

/// Pantalla "Información visita" — resumen y gestión de la visita al cliente.
class InformacionVisitaScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic> ruta;
  final Map<String, dynamic>? cartera;
  final bool segundaVisita;
  final String? motivoSegundaVisita;

  const InformacionVisitaScreen({
    super.key,
    required this.cliente,
    required this.ruta,
    this.cartera,
    this.segundaVisita = false,
    this.motivoSegundaVisita,
  });

  @override
  State<InformacionVisitaScreen> createState() => _InformacionVisitaScreenState();
}

class _InformacionVisitaScreenState extends State<InformacionVisitaScreen> {
  final ApiEasyService _api = ApiEasyService();
  final TextEditingController _obs = TextEditingController();

  Map<String, dynamic>? _cartera;
  int _totalObjetivos = 0;
  List<Map<String, dynamic>> _tareas = [];
  Map<String, dynamic>? _ultimoPedido;
  bool _cargando = true;
  String? _motivo;
  bool _guardando = false;

  // Cronómetro de la visita (persistente: no se reinicia al salir/entrar)
  DateTime _horaInicio = DateTime.now();
  Duration _transcurrido = Duration.zero;
  Timer? _timer;

  String get _visitaKey {
    final rid = '${widget.ruta['id'] ?? ''}';
    return rid.isNotEmpty ? 'visita_inicio_ruta_$rid' : 'visita_inicio_cli_$_codigo';
  }

  double _totalPedidos = 0;
  bool _recargandoPedidos = false;

  VisitaActivaProvider? _visitaActiva;

  static const List<String> _motivos = [
    'Establecimiento cerrado',
    'No se encontró el encargado',
    'Cliente sin presupuesto',
    'Inventario suficiente',
    'No desea comprar hoy',
    'Cartera pendiente por pagar',
    'Otro',
  ];

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  static Color get _primary => AppTheme.primaryBlue;

  @override
  void initState() {
    super.initState();
    _cartera = widget.cartera;
    _visitaActiva = context.read<VisitaActivaProvider>();
    // Cronómetro: recupera la hora de inicio si la visita ya estaba en curso;
    // si no, la registra ahora. No se reinicia al salir y volver a entrar.
    _restaurarCronometro();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _transcurrido = DateTime.now().difference(_horaInicio));
    });
    _cargar();
  }

  Future<void> _restaurarCronometro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardada = prefs.getString(_visitaKey);
      final dt = guardada != null ? DateTime.tryParse(guardada) : null;
      if (dt != null) {
        // Visita ya iniciada: continuar contando desde la hora original
        if (mounted) {
          setState(() {
            _horaInicio = dt;
            _transcurrido = DateTime.now().difference(dt);
          });
        }
      } else {
        // Primera vez: guardar la hora de inicio
        await prefs.setString(_visitaKey, _horaInicio.toIso8601String());
      }
    } catch (_) {}
    // Publicar la visita como activa (alimenta el cronómetro flotante global)
    _visitaActiva?.iniciar(cliente: widget.cliente, ruta: widget.ruta, inicio: _horaInicio);
    _visitaActiva?.setEnPantallaVisita(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Al salir sin finalizar, la visita sigue activa → mostrar el flotante.
    _visitaActiva?.setEnPantallaVisita(false);
    _obs.dispose();
    super.dispose();
  }

  String _horaFormato(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'a.m.' : 'p.m.';
    return '$h:$m $ampm';
  }

  String _cronoFormato(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String get _codigo => (widget.cliente['id'] ?? '').toString();

  String get _nombreCliente {
    final n = (widget.cliente['nombre'] ?? widget.cliente['cardName'] ?? _cartera?['nombre'] ?? '')
        .toString()
        .trim();
    if (n.isNotEmpty) return n;
    return (widget.ruta['nombre'] ?? 'Cliente')
        .toString()
        .replaceFirst(RegExp(r'^visita\s+a\s+', caseSensitive: false), '');
  }

  double get _totalCartera => ((_cartera?['balance'] ?? widget.cliente['balance']) as num?)?.toDouble() ?? 0;

  Future<void> _cargar() async {
    if (_codigo.isEmpty) {
      setState(() => _cargando = false);
      return;
    }
    final results = await Future.wait([
      _cartera == null ? _api.getCarteraCliente(_codigo) : Future.value(_cartera),
      _api.getTareasCliente(_codigo),
    ]);
    if (!mounted) return;
    final tareasData = results[1];
    setState(() {
      _cartera = results[0];
      _totalObjetivos = (tareasData?['total'] as int?) ?? 0;
      _tareas = ((tareasData?['tareas'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _cargando = false;
    });
    _recargarTotalPedidos();
  }

  /// Cantidad requerida de productos según el texto de la tarea (ej: "2 PRODUCTOS").
  int _requeridoTarea(String texto) {
    final m = RegExp(r'(\d+)\s*PRODUCTO', caseSensitive: false).firstMatch(texto);
    if (m != null) return int.tryParse(m.group(1) ?? '') ?? 1;
    return 1;
  }

  /// Productos distintos en el pedido de la visita (para calcular avance de tareas).
  int get _productosPedido {
    final items = (_ultimoPedido?['items'] as List<dynamic>?) ?? [];
    return items.map((e) => (e as Map)['codigo']).where((c) => '$c'.isNotEmpty).toSet().length;
  }

  String _pesos(double v) {
    final s = v.toStringAsFixed(2);
    final partes = s.split('.');
    final entero = partes[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    return '\$ $entero,${partes[1]}';
  }

  Future<void> _irAPedido() async {
    HapticFeedback.mediumImpact();
    if (_codigo.isEmpty) return;
    final sap = _cartera;
    context.read<SessionProvider>().setClienteData(
          codigo: _codigo,
          nombre: _nombreCliente,
          direccion: sap?['direccion']?.toString() ?? '',
          telefono: sap?['telefono']?.toString() ?? '',
          correo: '',
          vendedor: sap?['vendedor']?.toString() ?? '',
          ciudad: sap?['ciudad']?.toString() ?? widget.ruta['ciudad']?.toString() ?? '',
          balance: _totalCartera,
          listaPrecios: sap?['listaPrecios']?.toString() ?? '',
          listaPreciosCodigo: (sap?['listaPreciosCodigo'] as num?)?.toInt(),
        );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductsTab()),
    );
    // Al volver del catálogo, recargar el total de pedidos de esta visita
    _recargarTotalPedidos();
  }

  Future<void> _recargarTotalPedidos() async {
    if (_codigo.isEmpty) return;
    setState(() => _recargandoPedidos = true);
    // Sumar los pedidos del cliente desde el inicio del día (robusto a entrar/
    // salir de la pantalla). Cubre los pedidos hechos durante la visita de hoy.
    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final results = await Future.wait([
      _api.getTotalPedidos(_codigo, desde: inicioDia),
      _api.getUltimoPedido(_codigo, desde: inicioDia),
    ]);
    if (mounted) {
      setState(() {
        _totalPedidos = results[0] as double;
        _ultimoPedido = results[1] as Map<String, dynamic>?;
        _recargandoPedidos = false;
      });
    }
  }

  Future<void> _finalizarVisita() async {
    if (_guardando) return;
    HapticFeedback.mediumImpact();

    final tieneMotivo = _motivo != null && _motivo!.isNotEmpty;

    // La encuesta solo es obligatoria si HUBO gestión (sin motivo de no gestión).
    // Si se seleccionó un motivo de no gestión, se finaliza directo sin encuesta.
    Map<String, dynamic>? encuesta;
    if (!tieneMotivo) {
      encuesta = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => EncuestaVisitaScreen(nombreCliente: _nombreCliente),
        ),
      );
      if (encuesta == null) {
        // Canceló la encuesta → no se finaliza la visita
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Completa la encuesta o selecciona un motivo de no gestión para finalizar'),
              backgroundColor: AppTheme.accentColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // Formulario de pago OBLIGATORIO: siempre se muestra al finalizar la
    // visita para registrar el recaudo (o confirmar que no hubo pago).
    final pago = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => FormaPagoScreen(
          nombreCliente: _nombreCliente,
          numeroCuenta: _codigo,
          totalDocumentos: (_cartera?['totalFacturasAbiertas'] as num?)?.toInt() ?? 0,
          documentosPorCruzar: (_cartera?['facturasVencidas'] as num?)?.toInt() ?? 0,
          dineroFaltante: _totalCartera,
          totalPedido: _totalPedidos,
        ),
      ),
    );
    if (pago == null) {
      // Volvió atrás sin registrar el pago → no se finaliza la visita
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registra el pago (o confirma sin recaudo) para finalizar la visita'),
            backgroundColor: AppTheme.accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final totalRecaudos = (pago['valor'] as num?)?.toDouble() ?? 0;
    final metodoPago = pago['metodo']?.toString() ?? '';
    final bancoPago = pago['banco']?.toString() ?? '';
    final referenciaPago = pago['referencia']?.toString() ?? '';

    if (!mounted) return;

    // Tras la forma de pago: gestión del pedido (liquidación, condiciones,
    // evidencias, guardar). Es parte del proceso pero no bloquea la visita.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GestionPedidoScreen(
          cliente: widget.cliente,
          ruta: widget.ruta,
          ultimoPedido: _ultimoPedido,
          pago: pago,
          cartera: _cartera,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _guardando = true);

    final ahora = DateTime.now();
    final res = await _api.registrarVisita(
      _codigo,
      observacion: _obs.text.trim(),
      motivo: _motivo,
      rutaId: int.tryParse('${widget.ruta['id'] ?? ''}'),
      totalPedidos: _totalPedidos,
      totalCartera: _totalCartera,
      totalRecaudos: totalRecaudos,
      horaInicio: _horaInicio,
      horaFin: ahora,
      duracionSegundos: ahora.difference(_horaInicio).inSeconds,
      metodoPago: metodoPago,
      bancoPago: bancoPago,
      referenciaPago: referenciaPago,
      encuestaTipo: encuesta?['nombre']?.toString(),
      encuestaRespuestas: encuesta != null
          ? {
              'tipo': encuesta['tipo'],
              'nombre': encuesta['nombre'],
              'respuestas': encuesta['respuestas'],
            }
          : null,
      segundaVisita: widget.segundaVisita,
      motivoSegundaVisita: widget.motivoSegundaVisita,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    if (res != null) {
      // Visita finalizada: limpiar la hora de inicio para que la próxima
      // visita a esta ruta arranque un cronómetro nuevo.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_visitaKey);
      } catch (_) {}
      // Cerrar la visita activa → oculta el cronómetro flotante global
      _visitaActiva?.finalizar();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('Visita finalizada correctamente'),
          ]),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo finalizar la visita. Intenta de nuevo.'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _verCartera() {
    final total = _totalCartera;
    final facturas = (_cartera?['totalFacturasAbiertas'] as num?)?.toInt() ?? 0;
    final vencidas = (_cartera?['facturasVencidas'] as num?)?.toInt() ?? 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.account_balance_wallet_rounded, color: _primary),
            const SizedBox(width: 10),
            Text('Cartera del cliente',
                style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          _carteraRow('Saldo total', _pesos(total), total > 0 ? AppTheme.errorColor : AppTheme.successColor),
          _carteraRow('Facturas abiertas', '$facturas', _textDark),
          _carteraRow('Facturas vencidas', '$vencidas', vencidas > 0 ? AppTheme.errorColor : _textDark),
        ]),
      ),
    );
  }

  Widget _carteraRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _vistaPreviaPedido() {
    final p = _ultimoPedido!;
    final items = (p['items'] as List<dynamic>?) ?? [];
    final total = (p['total'] as num?)?.toDouble() ?? 0;
    final numero = p['numeroPedido']?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.25)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: _primary.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.receipt_long_rounded, color: _primary, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pedido de la visita',
                    style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w800)),
                if (numero.isNotEmpty)
                  Text('#$numero',
                      style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: _primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${items.length} ítem(s)',
                  style: TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Divider(height: 1, color: _border.withOpacity(0.6)),
        ...items.take(6).map((raw) {
          final it = Map<String, dynamic>.from(raw as Map);
          final cant = (it['cantidad'] as num?)?.toInt() ?? 0;
          final tot = (it['total'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6)),
                child: Text('x$cant',
                    style: TextStyle(color: _primary, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text((it['nombre'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _textDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(_pesos(tot),
                  style: TextStyle(color: _textDark, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          );
        }),
        if (items.length > 6)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('+ ${items.length - 6} más',
                style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total del pedido',
                style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800)),
            Text(_pesos(total),
                style: TextStyle(color: _primary, fontSize: 16, fontWeight: FontWeight.w900)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: _textDark),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const AppBarTitle('Información visita'),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.menu_rounded, color: _textDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Colors.white,
            onSelected: (v) {
              switch (v) {
                case 'pedido':
                  _irAPedido();
                  break;
                case 'cartera':
                  _verCartera();
                  break;
                case 'finalizar':
                  _finalizarVisita();
                  break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('pedido', Icons.shopping_cart_rounded, 'Pedido', _primary),
              _menuItem('cartera', Icons.account_balance_wallet_rounded, 'Cartera', AppTheme.accentColor),
              _menuItem('finalizar', Icons.flag_rounded, 'Finalizar visita', AppTheme.successColor),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _clienteHeader(),
                const SizedBox(height: 12),
                _cronometro(),
                const SizedBox(height: 14),
                _seccionObjetivos(),
                const SizedBox(height: 10),
                _seccionInformes(),
                const SizedBox(height: 18),
                _label('Motivos de no gestión'),
                const SizedBox(height: 8),
                _dropdownMotivo(),
                const SizedBox(height: 18),
                _resumenVisita(),
                if (_ultimoPedido != null) ...[
                  const SizedBox(height: 14),
                  _vistaPreviaPedido(),
                ],
                const SizedBox(height: 18),
                _label('Observaciones'),
                const SizedBox(height: 8),
                _campoObservaciones(),
                const SizedBox(height: 24),
                _botonFinalizar(),
              ],
            ),
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label, Color color) =>
      PopupMenuItem<String>(
        value: v,
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _label(String t) => Text(
        t.toUpperCase(),
        style: TextStyle(
          color: _textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      );

  Widget _clienteHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nombreCliente,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text('NIT / Código: $_codigo',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  Widget _cronometro() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.successColor.withOpacity(0.35)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.successColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.timer_rounded, color: AppTheme.successColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tiempo de visita',
                style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.play_circle_fill_rounded, size: 13, color: AppTheme.successColor),
              const SizedBox(width: 4),
              Text('Inicio ${_horaFormato(_horaInicio)}',
                  style: TextStyle(color: _textDark, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _cronoFormato(_transcurrido),
            style: const TextStyle(
              color: AppTheme.successColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 0.5,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tarjeta({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _seccionObjetivos() {
    final asignado = _totalObjetivos > 0;
    const violeta = Color(0xFF8B5CF6);
    // Avance automático: tareas alcanzadas por los productos del pedido
    final cumplidasPorPedido = asignado
        ? _tareas.where((t) => _productosPedido >= _requeridoTarea((t['tarea'] ?? '').toString())).length
        : 0;
    return _tarjeta(
      onTap: asignado ? _verObjetivos : null,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: violeta.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.track_changes_rounded, color: violeta, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Objetivos',
                style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(asignado ? '$_totalObjetivos tarea(s) · toca para ver' : 'No asignado',
                style: TextStyle(
                    color: asignado ? violeta : _textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        if (asignado && _productosPedido > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('$cumplidasPorPedido/$_totalObjetivos',
                style: const TextStyle(color: AppTheme.successColor, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        if (asignado) Icon(Icons.chevron_right_rounded, color: _textMuted),
      ]),
    );
  }

  void _verObjetivos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, scroll) => Column(children: [
          const SizedBox(height: 12),
          Container(width: 42, height: 5, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              const Icon(Icons.track_changes_rounded, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Objetivos / Tareas',
                    style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (_productosPedido > 0)
                Text('Pedido: $_productosPedido prod.',
                    style: TextStyle(color: AppTheme.successColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _tareas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _tareaCard(_tareas[i]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tareaCard(Map<String, dynamic> t) {
    final texto = (t['tarea'] ?? '').toString();
    final lista = (t['lista'] ?? '').toString();
    final subcanal = (t['subcanal'] ?? '').toString();
    final req = _requeridoTarea(texto);
    final logrado = _productosPedido.clamp(0, req);
    final pct = req > 0 ? (logrado / req).clamp(0.0, 1.0) : 0.0;
    final completa = logrado >= req && _productosPedido > 0;
    final color = completa ? AppTheme.successColor : const Color(0xFF8B5CF6);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: completa ? AppTheme.successColor.withOpacity(0.4) : _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(completa ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto.isEmpty ? '(sin descripción)' : texto,
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3)),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (lista.isNotEmpty) _chipMini(Icons.list_alt_rounded, lista),
          if (subcanal.isNotEmpty) _chipMini(Icons.category_rounded, subcanal),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 7,
                backgroundColor: _bg,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$logrado/$req',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text(completa ? 'Cumplida con el pedido' : 'Codifica ${req - logrado} producto(s) más con el pedido',
            style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _chipMini(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: _textMuted),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: _textDark, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  String get _canalTexto {
    final nombre = _cartera?['canal']?.toString().trim() ?? '';
    if (nombre.isNotEmpty) return nombre;
    final cod = _cartera?['canalCodigo'];
    return cod != null && cod.toString().trim().isNotEmpty ? 'Grupo $cod' : '—';
  }

  String get _listaTexto {
    final nombre = _cartera?['listaPrecios']?.toString().trim() ?? '';
    if (nombre.isNotEmpty) return nombre;
    final cod = _cartera?['listaPreciosCodigo'];
    return cod != null && cod.toString().trim().isNotEmpty ? 'Lista $cod' : '—';
  }

  void _verInformes() {
    final req = _tareas.fold<int>(0, (a, t) => a + _requeridoTarea((t['tarea'] ?? '').toString()));
    final cumplidas = _tareas.where((t) => _productosPedido >= _requeridoTarea((t['tarea'] ?? '').toString())).length;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 44, height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(children: [
              Icon(Icons.assignment_rounded, color: _primary),
              const SizedBox(width: 10),
              Text('Informe de la visita',
                  style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            _carteraRow('Canal', _canalTexto, _textDark),
            _carteraRow('Lista de precios', _listaTexto, _textDark),
            Divider(height: 22, thickness: 1, color: _border),
            _carteraRow('Tiempo de visita', _cronoFormato(_transcurrido), _textDark),
            _carteraRow('Tareas asignadas', '${_tareas.length}', _textDark),
            _carteraRow('Tareas cumplidas (pedido)', '$cumplidas', AppTheme.successColor),
            _carteraRow('Productos requeridos', '$req', _textDark),
            _carteraRow('Productos del pedido', '$_productosPedido', _primary),
            _carteraRow('Total del pedido', _pesos(_totalPedidos), _primary),
            _carteraRow('Total cartera', _pesos(_totalCartera), _totalCartera > 0 ? AppTheme.errorColor : AppTheme.successColor),
          ]),
        ),
      ),
    );
  }

  Widget _seccionInformes() {
    return _tarjeta(
      onTap: _verInformes,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.assignment_rounded, color: _primary, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text('Informes',
              style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        Icon(Icons.chevron_right_rounded, color: _textMuted),
      ]),
    );
  }

  Widget _dropdownMotivo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _motivo,
          isExpanded: true,
          hint: Text('Seleccione un motivo',
              style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500)),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textMuted),
          borderRadius: BorderRadius.circular(14),
          style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600),
          items: _motivos
              .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _motivo = v);
          },
        ),
      ),
    );
  }

  Widget _resumenVisita() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            Icon(Icons.emoji_events_rounded, color: AppTheme.accentColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Resumen de la visita',
                  style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: 'Actualizar pedidos',
              visualDensity: VisualDensity.compact,
              onPressed: _recargandoPedidos ? null : _recargarTotalPedidos,
              icon: _recargandoPedidos
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue))
                  : Icon(Icons.refresh_rounded, color: _primary, size: 20),
            ),
          ]),
        ),
        _resumenRow('Total pedidos', _pesos(_totalPedidos), Icons.shopping_bag_rounded, _primary),
        Divider(height: 1, color: _border.withOpacity(0.6), indent: 16, endIndent: 16),
        _resumenRow('Total cartera', _pesos(_totalCartera), Icons.account_balance_wallet_rounded,
            _totalCartera > 0 ? AppTheme.errorColor : AppTheme.successColor),
        Divider(height: 1, color: _border.withOpacity(0.6), indent: 16, endIndent: 16),
        _resumenRow('Total recaudos', _pesos(0), Icons.payments_rounded, AppTheme.successColor),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _resumenRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _campoObservaciones() {
    return TextField(
      controller: _obs,
      maxLines: 3,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(fontSize: 14, color: _textDark),
      decoration: InputDecoration(
        hintText: 'Escribe una observación de la visita…',
        hintStyle: TextStyle(color: AppTheme.textTertiaryColor, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primary, width: 1.6),
        ),
      ),
    );
  }

  Widget _botonFinalizar() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _guardando ? null : _finalizarVisita,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.successColor, Color(0xFF2AAE4E)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppTheme.successColor.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: _guardando
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Finalizar visita',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
          ),
        ),
      ),
    );
  }
}
