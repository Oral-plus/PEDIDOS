import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';
import '../widgets/app_dialog.dart';
import '../services/sesion.dart';
import 'vendor_orders_screen.dart';
import 'socio_negocio_screen.dart';
import 'rutero_screen.dart';
import 'mis_rutas_screen.dart';
import 'cuadre_caja_screen.dart';
import 'indicadores_screen.dart';

class ClientMenuScreen extends StatefulWidget {
  const ClientMenuScreen({super.key});

  @override
  State<ClientMenuScreen> createState() => _ClientMenuScreenState();
}

class _ClientMenuScreenState extends State<ClientMenuScreen>
    with TickerProviderStateMixin {
  final ApiEasyService _api = ApiEasyService();
  List<Map<String, dynamic>> _clientes = [];
  Map<String, dynamic>? _clienteSeleccionado;
  Map<String, dynamic>? _clienteDetalleSAP;
  bool _isLoadingClientes = true;
  String? _errorMessage;
  int _cuadresPendientes = 0;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;


  static const Color _blue = Color(0xFF1F2937);
  static const Color _blueLight = Color(0xFF4B5563);
  static const Color _bluePale = Color(0xFFF3F4F6);
  static const Color _inkDeep = Color(0xFF0B1220);
  static Color get _bg => AppTheme.backgroundColor;
  static const Color _white = Colors.white;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  static Color get _border => AppTheme.borderColor;
  static Color get _danger => AppTheme.errorColor;

  static List<BoxShadow> get _softShadow => [
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 22, offset: const Offset(0, 12)),
        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
      ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _fadeController.forward();
    _slideController.forward();
    _cargarClientes();
    _cargarCuadresPendientes();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() { _isLoadingClientes = true; _errorMessage = null; _clienteSeleccionado = null; _clienteDetalleSAP = null; });
    final res = await _api.getClientes();
    if (!mounted) return;
    setState(() {
      _isLoadingClientes = false;
      _clientes = (res['data'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      if (res['success'] != true) {
        _errorMessage = res['message']?.toString() ?? 'Error al cargar clientes';
      }
      if (_errorMessage != null &&
          _errorMessage!.toLowerCase().contains('expirada')) {
        _redirectToLogin();
      }
    });
  }

  Future<void> _cargarCuadresPendientes() async {
    final res = await _api.getRecaudosCuadre(estado: 'pendiente');
    if (!mounted) return;
    setState(() {
      _cuadresPendientes = (res['data'] as List?)?.length ?? 0;
    });
  }

  Future<void> _redirectToLogin() => Sesion.expirar();

  void _logout() async {
    final salir = await showAppConfirm(
      context,
      title: 'Cerrar sesión',
      message: '¿Deseas salir del portal de pedidos?',
      confirmText: 'Salir',
      icon: Icons.logout_rounded,
    );
    if (salir) Sesion.cerrar();
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
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildHeader(),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 18),
                      _buildVendorHero(),
                      const SizedBox(height: 26),
                      _buildMenuTitle(),
                      const SizedBox(height: 18),
                      _buildMenuGrid(),
                      const SizedBox(height: 14),
                      _buildClienteChip(),
                      if (_errorMessage != null) ...[const SizedBox(height: 14), _buildErrorCard()],
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _verMisPedidos() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const VendorOrdersScreen(),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
        decoration: BoxDecoration(
          color: _white,
          border: Border(bottom: BorderSide(color: _border.withOpacity(0.7))),
        ),
        child: Row(
          children: [
            Image.asset(
              AppAssets.logo,
              height: 46,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.medical_services_rounded, size: 38, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Portal de Pedidos',
                      style: TextStyle(color: _textDark, fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                  const SizedBox(height: 1),
                  Text('Oral-Plus',
                      style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                ],
              ),
            ),
            _headerBtn(Icons.refresh_rounded, _cargarClientes),
            const SizedBox(width: 8),
            _headerBtn(Icons.logout_rounded, _logout),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorHero() {
    final usuario = _api.usuario;
    final nombrePersona = usuario?['nombre']?.toString() ?? '';
    final apellido = usuario?['apellido']?.toString() ?? '';
    final nombreCompleto = '$nombrePersona${apellido.isNotEmpty ? ' $apellido' : ''}'.trim();
    final nombreUsuario = _api.loginUsuario;
    final iniciales = (nombreCompleto.isNotEmpty ? nombreCompleto : 'V')
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, _inkDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: _blue.withOpacity(0.30), blurRadius: 26, offset: const Offset(0, 14)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              right: -28, top: -34,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
              ),
            ),
            Positioned(
              right: 44, bottom: -46,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.04)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          iniciales.isEmpty ? 'V' : iniciales,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bienvenido',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                            const SizedBox(height: 3),
                            Text(
                              nombreCompleto.isNotEmpty ? nombreCompleto : 'Vendedor',
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            if (nombreUsuario.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Usuario: $nombreUsuario',
                                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Pulsable(
                    onTap: _verMisPedidos,
                    radio: 13,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 5))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded, color: _blue, size: 18),
                          const SizedBox(width: 8),
                          Text('Mis Pedidos',
                              style: TextStyle(color: _blue, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, color: _blue.withOpacity(0.7), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerBtn(IconData icon, VoidCallback onTap) {
    return _Pulsable(
      onTap: onTap,
      radio: 13,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
        child: Icon(icon, color: _textMuted, size: 19),
      ),
    );
  }

  Widget _buildMenuTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Menú', style: TextStyle(color: _textDark, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(
          _isLoadingClientes
              ? 'Cargando clientes...'
              : 'Selecciona una opción para empezar',
          style: TextStyle(color: _textMuted, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildMenuGrid() {
    final hayCliente = _clienteSeleccionado != null;
    return Column(children: [
      Row(children: [
        Expanded(child: _menuTile(
          icon: Icons.storefront_rounded,
          title: 'Socio de Negocio',
          subtitle: hayCliente ? 'Cliente activo' : 'Elige un cliente',
          color: _blue,
          active: true,
          onTap: _showSocioNegocio,
        )),
        const SizedBox(width: 12),
        Expanded(child: _menuTile(
          icon: Icons.inventory_2_rounded,
          title: 'Rutero',
          subtitle: hayCliente ? 'Ver catálogo' : 'Requiere cliente',
          color: _blueLight,
          active: hayCliente,
          onTap: hayCliente ? _abrirRutero : _avisoElegirCliente,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _menuTile(
          icon: Icons.route_rounded,
          title: 'Mis Rutas',
          subtitle: 'Hoy · Semana · Mes',
          color: _blueLight,
          active: true,
          onTap: _abrirMisRutas,
        )),
        const SizedBox(width: 12),
        Expanded(child: _menuTile(
          icon: Icons.point_of_sale_rounded,
          title: 'Cuadre de Caja',
          subtitle: _cuadresPendientes > 0 ? 'Por cuadrar' : 'Recaudos en efectivo',
          color: _inkDeep,
          active: true,
          onTap: _abrirCuadreCaja,
          contador: _cuadresPendientes > 0 ? _cuadresPendientes : null,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _menuTile(
          icon: Icons.event_note_rounded,
          title: 'Programación',
          subtitle: 'Abrir en el navegador',
          color: _blue,
          active: true,
          onTap: _abrirProgramacion,
        )),
        const SizedBox(width: 12),
        Expanded(child: _menuTile(
          icon: Icons.insights_rounded,
          title: 'Indicadores',
          subtitle: 'Pagos y estado de pedidos',
          color: _inkDeep,
          active: true,
          onTap: _abrirIndicadores,
        )),
      ]),
    ]);
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool active,
    required VoidCallback onTap,
    int? contador,
  }) {
    return _Pulsable(
      onTap: onTap,
      radio: 20,
      child: Container(
        height: 134,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color.withOpacity(0.14) : _border),
          boxShadow: _softShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconoMenu(icon, color, active),
            const Spacer(),
            if (contador != null) _pastillaContador(contador) else _remateMenu(color, active),
          ]),
          const Spacer(),
          Text(title,
              style: TextStyle(color: active ? _textDark : _textMuted, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.3),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(subtitle,
              style: TextStyle(
                  color: contador != null ? _danger : _textMuted,
                  fontSize: 11.5,
                  fontWeight: contador != null ? FontWeight.w700 : FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _iconoMenu(IconData icon, Color color, bool active) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: active ? null : _bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: active ? Colors.white.withOpacity(0.22) : _border),
        boxShadow: active
            ? [BoxShadow(color: color.withOpacity(0.30), blurRadius: 14, offset: const Offset(0, 7))]
            : null,
      ),
      child: Icon(icon, color: active ? _white : _textMuted.withOpacity(0.7), size: 23),
    );
  }

  Widget _remateMenu(Color color, bool active) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.08) : _bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        active ? Icons.arrow_forward_rounded : Icons.lock_outline_rounded,
        color: active ? color : _textMuted.withOpacity(0.6),
        size: 15,
      ),
    );
  }

  Widget _pastillaContador(int valor) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      height: 28,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _danger,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: _danger.withOpacity(0.32), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Text('$valor',
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
    );
  }

  void _avisoElegirCliente() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _inkDeep,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text('Elige primero un cliente en Socio de Negocio',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ));
  }

  void _abrirMisRutas() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MisRutasScreen(),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Future<void> _abrirCuadreCaja() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const CuadreCajaScreen(),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    _cargarCuadresPendientes();
  }

  Future<void> _abrirIndicadores() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const IndicadoresScreen(),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Future<void> _abrirProgramacion() async {
    var abierto = false;
    try {
      abierto = await launchUrl(Uri.parse(AppConfig.urlProgramacion), mode: LaunchMode.externalApplication);
    } catch (_) {
      abierto = false;
    }
    if (!mounted || abierto) return;
    await showAppConfirm(
      context,
      title: 'No se pudo abrir la programación',
      message: 'Revisa que el dispositivo tenga un navegador disponible.',
      confirmText: 'Entendido',
      cancelText: 'Cerrar',
      icon: Icons.public_off_rounded,
    );
  }

  Widget _buildClienteChip() {
    final hay = _clienteSeleccionado != null;
    final nombre = hay
        ? (_clienteSeleccionado!['nombre'] ??
                _clienteSeleccionado!['cardName'] ??
                _clienteSeleccionado!['nombre1'] ??
                'Cliente')
            .toString()
        : 'Ningún cliente seleccionado';
    final codigo = hay ? (_clienteSeleccionado!['id']?.toString() ?? '') : '';

    return _Pulsable(
      onTap: _showSocioNegocio,
      radio: 16,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: hay ? _bluePale : _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hay ? _blueLight.withOpacity(0.25) : _border),
          boxShadow: hay ? null : _softShadow,
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: hay ? _white : _bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hay ? Icons.storefront_rounded : Icons.person_search_rounded,
              color: hay ? _blueLight : _textMuted,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(nombre,
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (hay) ...[
              const SizedBox(height: 2),
              Text(codigo,
                  style: TextStyle(color: _blueLight, fontSize: 11, fontWeight: FontWeight.w600)),
            ] else
              Text('Toca para elegir uno',
                  style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ])),
          if (_isLoadingClientes)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _blueLight))
          else if (!hay && _clientes.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
              child: Text('${_clientes.length}',
                  style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            )
          else
            Icon(Icons.chevron_right_rounded, color: _textMuted, size: 20),
        ]),
      ),
    );
  }

  void _abrirRutero() {
    if (_clienteSeleccionado == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RuteroScreen(
          cliente: _clienteSeleccionado!,
          detalle: _clienteDetalleSAP,
        ),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(14), border: Border.all(color: _danger.withOpacity(0.15))),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: _danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.error_outline_rounded, color: _danger, size: 19)),
        const SizedBox(width: 12),
        Expanded(child: Text(_errorMessage!, style: TextStyle(color: _danger, fontSize: 13, fontWeight: FontWeight.w500))),
        _Pulsable(
          onTap: _cargarClientes,
          radio: 8,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
            child: const Text('Reintentar', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
        ),
      ]),
    );
  }

  Future<void> _showSocioNegocio() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => SocioNegocioScreen(
          api: _api,
          clientes: _clientes,
          seleccionadoInicial: _clienteSeleccionado,
          detalleInicial: _clienteDetalleSAP,
        ),
        transitionsBuilder: (_, a, __, c) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    if (!mounted || result == null) return;
    final cliente = result['cliente'] as Map<String, dynamic>?;
    final detalle = result['detalle'] as Map<String, dynamic>?;
    setState(() {
      _clienteSeleccionado = cliente;
      _clienteDetalleSAP = detalle;
    });
  }
}

class _Pulsable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double radio;

  const _Pulsable({required this.child, required this.onTap, this.radio = 18});

  @override
  State<_Pulsable> createState() => _PulsableState();
}

class _PulsableState extends State<_Pulsable> {
  bool _presionado = false;

  void _marcar(bool v) {
    if (_presionado == v) return;
    setState(() => _presionado = v);
  }

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(widget.radio);
    return AnimatedScale(
      scale: _presionado ? 0.965 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: Stack(children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            borderRadius: radio,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: radio,
              splashColor: Colors.black.withOpacity(0.06),
              highlightColor: Colors.black.withOpacity(0.03),
              onTapDown: (_) => _marcar(true),
              onTapUp: (_) => _marcar(false),
              onTapCancel: () => _marcar(false),
              onTap: () {
                _marcar(false);
                HapticFeedback.selectionClick();
                widget.onTap();
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ]),
    );
  }
}
