import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';
import '../widgets/app_dialog.dart';
import '../services/sesion.dart';
import 'vendor_orders_screen.dart';
import 'socio_negocio_screen.dart';
import 'rutero_screen.dart';
import 'mis_rutas_screen.dart';

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
                      const SizedBox(height: 12),
                      _buildMisRutasTile(),
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
                  GestureDetector(
                    onTap: _verMisPedidos,
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
    return GestureDetector(
      onTap: onTap,
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
    return Row(children: [
      Expanded(child: _menuTile(
        icon: Icons.business_center_rounded,
        title: 'Socio de Negocio',
        subtitle: hayCliente ? 'Cliente activo' : 'Elige un cliente',
        color: _blue,
        active: true,
        onTap: _showSocioNegocio,
      )),
      if (hayCliente) ...[
        const SizedBox(width: 12),
        Expanded(child: _menuTile(
          icon: Icons.alt_route_rounded,
          title: 'Rutero',
          subtitle: 'Ver Catálogo',
          color: _blueLight,
          active: true,
          onTap: _abrirRutero,
        )),
      ],
    ]);
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? color.withOpacity(0.12) : _border),
          boxShadow: _softShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(colors: [color, color.withOpacity(0.78)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: active ? null : _bg,
                borderRadius: BorderRadius.circular(13),
                boxShadow: active
                    ? [BoxShadow(color: color.withOpacity(0.28), blurRadius: 10, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Icon(icon, color: active ? Colors.white : _textMuted, size: 22),
            ),
            const Spacer(),
            Container(
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
            ),
          ]),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(color: _textDark, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.3),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(subtitle,
              style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _buildMisRutasTile() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
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
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: _softShadow,
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_blueLight, _blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: _blue.withOpacity(0.28), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.route_rounded, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mis Rutas',
                  style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              const SizedBox(height: 2),
              Text('Hoy · Semana · Mes · Todas',
                  style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.arrow_forward_rounded, color: _blue, size: 17),
          ),
        ]),
      ),
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

    return GestureDetector(
      onTap: _showSocioNegocio,
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
    HapticFeedback.selectionClick();
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
        GestureDetector(
          onTap: _cargarClientes,
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
