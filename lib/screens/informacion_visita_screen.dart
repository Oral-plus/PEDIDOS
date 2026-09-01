import 'dart:async';
import 'dart:convert';
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

  DateTime _horaInicio = DateTime.now();
  final ValueNotifier<Duration> _transcurrido = ValueNotifier(Duration.zero);
  Timer? _timer;

  String get _visitaKey {
    final rid = '${widget.ruta['id'] ?? ''}';
    return rid.isNotEmpty ? 'visita_inicio_ruta_$rid' : 'visita_inicio_cli_$_codigo';
  }

  Map<String, dynamic>? _pago;
  String get _pagoKey => '${_visitaKey}_pago';

  String? _numeroRecaudo;
  double _valorRecaudo = 0;
  String get _recaudoKey => '${_visitaKey}_recaudo';

  double get _totalPedidoBasePago => (_pago?['totalPedidoBase'] as num?)?.toDouble() ?? 0;
  bool get _pagoDesactualizado =>
      _pago != null && !_recargandoPedidos && _totalPedidoBasePago != _totalPedidos;

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
    _restaurarCronometro();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _transcurrido.value = DateTime.now().difference(_horaInicio);
    });
    _cargar();
  }

  Future<void> _restaurarCronometro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardada = prefs.getString(_visitaKey);
      final dt = guardada != null ? DateTime.tryParse(guardada) : null;
      if (dt != null) {
        if (mounted) {
          setState(() => _horaInicio = dt);
          _transcurrido.value = DateTime.now().difference(dt);
        }
      } else {
        await prefs.setString(_visitaKey, _horaInicio.toIso8601String());
      }
      final pagoGuardado = prefs.getString(_pagoKey);
      final recaudoGuardado = prefs.getString(_recaudoKey);
      if (mounted) {
        setState(() {
          if (pagoGuardado != null) {
            final decoded = jsonDecode(pagoGuardado);
            if (decoded is Map) _pago = Map<String, dynamic>.from(decoded);
          }
          if (recaudoGuardado != null && recaudoGuardado.isNotEmpty) {
            final rec = jsonDecode(recaudoGuardado);
            if (rec is Map) {
              _numeroRecaudo = rec['numero']?.toString();
              _valorRecaudo = (rec['aplicado'] as num?)?.toDouble() ?? 0;
            }
          }
        });
      }
    } catch (_) {}
    _visitaActiva?.iniciar(cliente: widget.cliente, ruta: widget.ruta, inicio: _horaInicio);
    _visitaActiva?.setEnPantallaVisita(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transcurrido.dispose();
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

  static final RegExp _reProductosTarea = RegExp(r'(\d+)\s*PRODUCTO', caseSensitive: false);

  int _requeridoTarea(String texto) {
    final m = _reProductosTarea.firstMatch(texto);
    if (m != null) return int.tryParse(m.group(1) ?? '') ?? 1;
    return 1;
  }

  int _productosPedido = 0;

  static int _contarProductosPedido(Map<String, dynamic>? pedido) {
    final items = (pedido?['items'] as List<dynamic>?) ?? [];
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
    _recargarTotalPedidos();
  }

  Future<void> _recargarTotalPedidos() async {
    if (_codigo.isEmpty) return;
    setState(() => _recargandoPedidos = true);
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
        _productosPedido = _contarProductosPedido(_ultimoPedido);
        _recargandoPedidos = false;
      });
    }
  }

  Future<void> _finalizarVisita() async {
    if (_guardando) return;
    HapticFeedback.mediumImpact();

    final tieneMotivo = _motivo != null && _motivo!.isNotEmpty;

    Map<String, dynamic>? encuesta;
    if (!tieneMotivo) {
      encuesta = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => EncuestaVisitaScreen(nombreCliente: _nombreCliente),
        ),
      );
      if (encuesta == null) {
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

    var pago = _pago;
    if (pago == null) {
      pago = await _abrirFormaPago();
      if (pago == null) {
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
    } else if (_pagoDesactualizado) {
      final revisar = await _confirmarRevisarPago();
      if (!mounted) return;
      if (revisar) {
        final nuevo = await _abrirFormaPago();
        if (nuevo != null) pago = nuevo;
      }
    }
    if (!mounted) return;
    final totalRecaudos = (pago['valor'] as num?)?.toDouble() ?? 0;
    final metodoPago = pago['metodo']?.toString() ?? '';
    final bancoPago = pago['banco']?.toString() ?? '';
    final referenciaPago = pago['referencia']?.toString() ?? '';

    if (!mounted) return;

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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_visitaKey);
        await prefs.remove(_pagoKey);
        await prefs.remove(_recaudoKey);
      } catch (_) {}
      _pago = null;
      _numeroRecaudo = null;
      _valorRecaudo = 0;
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

  Future<Map<String, dynamic>?> _abrirFormaPago() async {
    if (_guardando) return null;
    final pago = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => FormaPagoScreen(
          nombreCliente: _nombreCliente,
          numeroCuenta: _codigo,
          totalDocumentos: (_cartera?['totalFacturasAbiertas'] as num?)?.toInt() ?? 0,
          documentosPorCruzar: (_cartera?['facturasVencidas'] as num?)?.toInt() ?? 0,
          dineroFaltante: _totalCartera,
          totalPedido: _totalPedidos,
          pagoInicial: _pago,
          numeroRecaudoPrevio: _numeroRecaudo,
          valorRecaudoPrevio: _valorRecaudo,
          onRecaudoGuardado: _guardarNumeroRecaudo,
        ),
      ),
    );
    if (pago == null || !mounted) return null;

    final fecha = pago['fecha'];
    final guardado = <String, dynamic>{
      ...pago,
      'fecha': fecha is DateTime ? fecha.toIso8601String() : fecha?.toString(),
      'totalPedidoBase': _totalPedidos,
    };
    setState(() => _pago = guardado);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pagoKey, jsonEncode(guardado));
    } catch (_) {}
    return guardado;
  }

  Future<void> _guardarNumeroRecaudo(String numero, double aplicado) async {
    if (numero.isEmpty) return;
    if (mounted) {
      setState(() {
        _numeroRecaudo = numero;
        _valorRecaudo = aplicado;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recaudoKey, jsonEncode({'numero': numero, 'aplicado': aplicado}));
    } catch (_) {}
  }

  Future<bool> _confirmarRevisarPago() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('El pedido cambió', style: TextStyle(color: _textDark, fontWeight: FontWeight.w800)),
        content: Text(
          'Cuando registraste el pago el pedido sumaba ${_pesos(_totalPedidoBasePago)} y ahora suma ${_pesos(_totalPedidos)}. ¿Quieres revisar el pago antes de finalizar?',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Continuar así', style: TextStyle(color: _textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revisar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Widget _tarjetaPago() {
    final p = _pago;
    final registrado = p != null;
    final valor = (p?['valor'] as num?)?.toDouble() ?? 0;
    final metodo = (p?['metodo'] ?? '').toString();
    final numRecaudo = (p?['numeroRecaudo'] ?? _numeroRecaudo ?? '').toString();
    final color = !registrado ? AppTheme.accentColor : (valor > 0 ? AppTheme.successColor : _textMuted);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: registrado ? _border : AppTheme.accentColor.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(registrado ? Icons.payments_rounded : Icons.pending_actions_rounded, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(registrado ? 'Pago de la visita' : 'Pago pendiente',
                style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              !registrado
                  ? (numRecaudo.isNotEmpty
                      ? 'Recaudo $numRecaudo guardado; falta confirmar el pago'
                      : 'Se registra desde el menú "Cartera y pago" o al finalizar')
                  : valor > 0
                      ? '${_pesos(valor)} · $metodo${numRecaudo.isNotEmpty ? ' · Recaudo $numRecaudo' : ''}'
                      : 'Sin recaudo',
              style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            if (registrado && _pagoDesactualizado)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('El pedido cambió después de registrar el pago',
                    style: TextStyle(color: AppTheme.accentColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        TextButton(
          onPressed: _guardando ? null : _abrirFormaPago,
          child: Text(registrado ? 'Editar' : 'Registrar',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w800)),
        ),
      ]),
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
                  _abrirFormaPago();
                  break;
                case 'finalizar':
                  _finalizarVisita();
                  break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('pedido', Icons.shopping_cart_rounded, 'Pedido', _primary),
              _menuItem('cartera', Icons.account_balance_wallet_rounded, 'Cartera y pago', AppTheme.accentColor),
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
                const SizedBox(height: 14),
                _tarjetaPago(),
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
          child: ValueListenableBuilder<Duration>(
            valueListenable: _transcurrido,
            builder: (_, d, __) => Text(
              _cronoFormato(d),
              style: const TextStyle(
                color: AppTheme.successColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
                letterSpacing: 0.5,
              ),
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
            ValueListenableBuilder<Duration>(
              valueListenable: _transcurrido,
              builder: (_, d, __) => _carteraRow('Tiempo de visita', _cronoFormato(d), _textDark),
            ),
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
