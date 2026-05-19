import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'vendor_orders_screen.dart';

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
  bool _isLoadingDetalle = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _clientesFiltrados = [];
  bool _showSearch = false;

  static Color get _blue => AppTheme.primaryBlue;
  static Color get _blueLight => AppTheme.secondaryBlue;
  static Color get _bluePale => AppTheme.lightBlue;
  static Color get _bg => AppTheme.backgroundColor;
  static const Color _white = Colors.white;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textBody => AppTheme.textPrimary;
  static Color get _textMuted => AppTheme.textSecondary;
  static Color get _border => AppTheme.borderColor;
  static Color get _danger => AppTheme.errorColor;

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
    _searchController.addListener(_filtrarClientes);
    _cargarClientes();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filtrarClientes() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _clientesFiltrados = List.from(_clientes);
      } else {
        _clientesFiltrados = _clientes.where((c) {
          final id = (c['id'] ?? '').toString().toLowerCase();
          final nombre = (c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '').toString().toLowerCase();
          return id.contains(query) || nombre.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _cargarClientes() async {
    setState(() { _isLoadingClientes = true; _errorMessage = null; _clienteSeleccionado = null; _clienteDetalleSAP = null; });
    final res = await _api.getClientes();
    if (!mounted) return;
    setState(() {
      _isLoadingClientes = false;
      _clientes = (res['data'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _clientesFiltrados = List.from(_clientes);
      if (res['success'] != true) _errorMessage = res['message']?.toString() ?? 'Error al cargar clientes';
      if (_errorMessage == 'Sesión expirada') _redirectToLogin();
    });
  }

  void _redirectToLogin() {
    _api.clearSession();
    context.read<SessionProvider>().clear();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(pageBuilder: (_, __, ___) => const LoginScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 400)),
      (route) => false,
    );
  }

  Future<void> _onClienteSeleccionado(Map<String, dynamic> cliente) async {
    HapticFeedback.selectionClick();
    setState(() { _clienteSeleccionado = cliente; _clienteDetalleSAP = null; _isLoadingDetalle = true; _showSearch = false; _searchController.clear(); });
    final codigo = cliente['id']?.toString() ?? '';
    if (codigo.isEmpty) { setState(() => _isLoadingDetalle = false); return; }
    try {
      final data = await _api.getCarteraCliente(codigo);
      if (mounted) setState(() { _clienteDetalleSAP = data; _isLoadingDetalle = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingDetalle = false);
    }
  }

  void _irAComprar() {
    if (_clienteSeleccionado == null) return;
    final codigo = _clienteSeleccionado!['id']?.toString() ?? '';
    if (codigo.isEmpty) return;
    HapticFeedback.mediumImpact();

    final sap = _clienteDetalleSAP;
    final c = _clienteSeleccionado!;
    context.read<SessionProvider>().setClienteData(
      codigo: codigo,
      nombre: sap?['nombre']?.toString() ?? c['nombre']?.toString() ?? c['cardName']?.toString() ?? '',
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
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cerrar sesión', style: TextStyle(color: _textDark, fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text('¿Deseas salir del portal de pedidos?', style: TextStyle(color: _textBody, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _redirectToLogin(); },
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            child: const Text('Salir', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(dynamic value) {
    final n = (double.tryParse(value.toString()) ?? 0);
    final parts = n.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    int count = 0;
    for (int i = parts.length - 1; i >= 0; i--) {
      buffer.write(parts[i]);
      count++;
      if (count % 3 == 0 && i > 0 && parts[i] != '-') buffer.write('.');
    }
    return '\$${buffer.toString().split('').reversed.join()}';
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
                      const SizedBox(height: 28),
                      _buildSectionTitle(),
                      const SizedBox(height: 18),
                      _buildSearchBox(),
                      if (_errorMessage != null) ...[const SizedBox(height: 16), _buildErrorCard()],
                      if (_clienteSeleccionado != null) ...[
                        const SizedBox(height: 24),
                        _buildClienteHeader(),
                        const SizedBox(height: 18),
                        _buildActionGrid(),
                      ],
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
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Widget _buildHeader() {
    final usuario = _api.usuario;
    final nombrePersona = usuario?['nombre']?.toString() ?? '';
    final apellido = usuario?['apellido']?.toString() ?? '';
    final nombreCompleto = '$nombrePersona${apellido.isNotEmpty ? ' $apellido' : ''}'.trim();
    final nombreUsuario = _api.loginUsuario;

    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: _white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: _bluePale, borderRadius: BorderRadius.circular(12)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(padding: const EdgeInsets.all(6), child: Image.asset(AppAssets.logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.medical_services_rounded, size: 22, color: _blue))),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ORAL-PLUS', style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      Text('Portal de Pedidos', style: TextStyle(color: _blueLight.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                _headerBtn(Icons.refresh_rounded, _cargarClientes),
                const SizedBox(width: 8),
                _headerBtn(Icons.logout_rounded, _logout),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _blue.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_blue, _blueLight]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombreCompleto.isNotEmpty ? nombreCompleto : 'Vendedor',
                          style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (nombreUsuario.isNotEmpty)
                          Text(
                            'Usuario: $nombreUsuario',
                            style: TextStyle(color: _textMuted, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _verMisPedidos,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [_blue, _blueLight]),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Mis Pedidos', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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
        width: 40, height: 40,
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Icon(icon, color: _textMuted, size: 19),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selecciona un cliente', style: TextStyle(color: _textDark, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(
          _isLoadingClientes ? 'Cargando clientes disponibles...' : '${_clientes.length} clientes disponibles',
          style: TextStyle(color: _textMuted, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildSearchBox() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _showSearch ? _blueLight.withOpacity(0.5) : _border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
              if (_showSearch) BoxShadow(color: _blueLight.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _showSearch ? _blueLight.withOpacity(0.1) : _bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.search_rounded, color: _showSearch ? _blueLight : _textMuted, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: _textDark, fontSize: 15, fontWeight: FontWeight.w500),
                        onTap: () => setState(() => _showSearch = true),
                        decoration: InputDecoration(
                          hintText: _isLoadingClientes ? 'Cargando clientes...' : 'Buscar por nombre o código...',
                          hintStyle: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w400),
                          border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_isLoadingClientes)
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _blueLight))
                    else if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () { _searchController.clear(); setState(() => _showSearch = false); },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded, color: _textMuted, size: 14),
                        ),
                      ),
                  ],
                ),
              ),
              if (_showSearch && !_isLoadingClientes && _clientesFiltrados.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: _border.withOpacity(0.6)))),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _clientesFiltrados.length,
                    itemBuilder: (_, i) {
                      final c = _clientesFiltrados[i];
                      final isSelected = _clienteSeleccionado != null && _clienteSeleccionado!['id'] == c['id'];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _onClienteSeleccionado(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? _bluePale.withOpacity(0.5) : Colors.transparent,
                              border: Border(bottom: BorderSide(color: _border.withOpacity(0.3))),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: isSelected ? _blueLight.withOpacity(0.12) : _bg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isSelected ? _blueLight.withOpacity(0.3) : _border.withOpacity(0.5)),
                                  ),
                                  child: Icon(isSelected ? Icons.check_circle_rounded : Icons.storefront_rounded, color: isSelected ? _blueLight : _textMuted, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? 'Cliente',
                                        style: TextStyle(color: _textDark, fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text('${c['id'] ?? '—'}', style: TextStyle(color: isSelected ? _blueLight : _textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: _blueLight.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Icon(Icons.check_rounded, color: _blueLight, size: 16),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_showSearch && !_isLoadingClientes && _clientesFiltrados.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(children: [
                    Icon(Icons.search_off_rounded, color: _textMuted.withOpacity(0.3), size: 40),
                    const SizedBox(height: 10),
                    Text('Sin resultados', style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500)),
                  ]),
                ),
            ],
          ),
        ),
      ],
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

  Widget _buildClienteHeader() {
    final c = _clienteSeleccionado!;
    final codigo = c['id']?.toString() ?? '';
    final nombre = (c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '—').toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_blue, _blueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _blue.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              nombre,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                codigo,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
          ]),
        ),
        if (_isLoadingDetalle)
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        else
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ),
      ]),
    );
  }

  Widget _buildActionGrid() {
    return Column(children: [
      Row(children: [
        Expanded(child: _actionBox(
          icon: Icons.business_center_rounded,
          color: _blue,
          title: 'Socio Negocio',
          subtitle: 'Datos del cliente',
          onTap: _showSocioNegocio,
        )),
        const SizedBox(width: 12),
        Expanded(child: _actionBox(
          icon: Icons.shopping_bag_rounded,
          color: AppTheme.successColor,
          title: 'Comprar Catálogo',
          subtitle: 'Crear pedido',
          onTap: _irAComprar,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _actionBox(
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.accentColor,
          title: 'Cartera',
          subtitle: _isLoadingDetalle
              ? 'Cargando...'
              : (_clienteDetalleSAP != null
                  ? '${_clienteDetalleSAP!['totalFacturasAbiertas'] ?? 0} facturas'
                  : 'Sin datos'),
          onTap: _showCartera,
        )),
        const SizedBox(width: 12),
        Expanded(child: _actionBox(
          icon: Icons.chat_bubble_rounded,
          color: _blueLight,
          title: 'Comentarios',
          subtitle: 'Ver y agregar',
          onTap: _showComentarios,
        )),
      ]),
    ]);
  }

  Widget _actionBox({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border.withOpacity(0.7)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }

  void _showSocioNegocio() {
    if (_clienteSeleccionado == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SheetWrapper(
        title: 'Socio de Negocio',
        icon: Icons.business_center_rounded,
        color: _blue,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: _buildClienteInfoCard(),
        ),
      ),
    );
  }

  void _showCartera() {
    if (_clienteSeleccionado == null) return;
    final codigo = _clienteSeleccionado!['id']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CarteraSheet(
        codigo: codigo,
        api: _api,
        initialData: _clienteDetalleSAP,
        color: AppTheme.accentColor,
      ),
    );
  }

  void _showComentarios() {
    if (_clienteSeleccionado == null) return;
    final codigo = _clienteSeleccionado!['id']?.toString() ?? '';
    final nombre = (_clienteSeleccionado!['nombre'] ??
            _clienteSeleccionado!['cardName'] ??
            _clienteSeleccionado!['nombre1'] ??
            '')
        .toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ComentariosSheet(
        codigo: codigo,
        nombreCliente: nombre,
        api: _api,
        color: _blueLight,
      ),
    );
  }

  Widget _buildClienteInfoCard() {
    final c = _clienteSeleccionado!;
    final codigo = c['id']?.toString() ?? '';
    final nombre = c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '—';
    final sap = _clienteDetalleSAP;
    final telefono = sap?['telefono']?.toString() ?? '—';
    final direccion = sap?['direccion']?.toString() ?? '—';
    final ciudad = sap?['ciudad']?.toString().trim().isNotEmpty == true ? sap!['ciudad'].toString() : '—';
    final vendedor = sap?['vendedor']?.toString() ?? '—';
    final limiteCredito = sap?['limiteCredito'] ?? 0;
    final descuentoRaw = sap?['descuento'];
    final descuentoNum = (descuentoRaw is num) ? descuentoRaw.toDouble() : double.tryParse(descuentoRaw?.toString() ?? '') ?? 0.0;
    final descuento = '${descuentoNum.toStringAsFixed(descuentoNum % 1 == 0 ? 0 : 2)}%';
    final canal = (sap?['canal']?.toString().trim().isNotEmpty == true)
        ? sap!['canal'].toString()
        : (sap?['canalCodigo'] != null ? 'Grupo ${sap!['canalCodigo']}' : '—');
    final listaPrecios = (sap?['listaPrecios']?.toString().trim().isNotEmpty == true)
        ? sap!['listaPrecios'].toString()
        : (sap?['listaPreciosCodigo'] != null ? 'Lista ${sap!['listaPreciosCodigo']}' : '—');

    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: _blueLight.withOpacity(0.04), blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_blue, _blueLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre.toString(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
                child: Text(codigo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
            ])),
            if (_isLoadingDetalle)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            else
              Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 20)),
          ]),
        ),
        if (sap != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(child: _statCard(Icons.credit_score_rounded, 'Límite crédito', _formatCurrency(limiteCredito), _blue)),
              const SizedBox(width: 10),
              Expanded(child: _statCard(Icons.percent_rounded, 'Descuento', descuento, AppTheme.successColor)),
            ]),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(children: [
            _detailRow(Icons.phone_rounded, 'Teléfono', telefono),
            const SizedBox(height: 8),
            _detailRow(Icons.location_on_rounded, 'Dirección', direccion),
            const SizedBox(height: 8),
            _detailRow(Icons.location_city_rounded, 'Ciudad', ciudad),
            if (sap != null) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.badge_rounded, 'Vendedor', vendedor),
              const SizedBox(height: 8),
              _detailRow(Icons.hub_rounded, 'Canal', canal),
              const SizedBox(height: 8),
              _detailRow(Icons.price_change_rounded, 'Lista de precios', listaPrecios),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.7), size: 15),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: TextStyle(color: color.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border.withOpacity(0.5))),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: _bluePale.withOpacity(0.6), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: _blueLight, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value.length > 45 ? '${value.substring(0, 45)}...' : value, style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  Widget _buildGoButton() {
    return GestureDetector(
      onTap: _irAComprar,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_blue, _blueLight], begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          const Text('IR A COMPRAR', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
          ),
        ]),
      ),
    );
  }
}

// =============================================================
//  Reusable bottom-sheet wrapper for the action boxes
// =============================================================
class _SheetWrapper extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const _SheetWrapper({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.85;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.darkBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppTheme.textSecondary,
                ),
              ]),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

// =============================================================
//  Cartera bottom sheet — facturas y saldo del cliente
// =============================================================
class _CarteraSheet extends StatefulWidget {
  final String codigo;
  final ApiEasyService api;
  final Map<String, dynamic>? initialData;
  final Color color;

  const _CarteraSheet({
    required this.codigo,
    required this.api,
    required this.initialData,
    required this.color,
  });

  @override
  State<_CarteraSheet> createState() => _CarteraSheetState();
}

class _CarteraSheetState extends State<_CarteraSheet> {
  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    if (_data == null) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final res = await widget.api.getCarteraCliente(widget.codigo);
    if (mounted) setState(() { _data = res; _loading = false; });
  }

  String _formatMoney(dynamic v) {
    final n = (double.tryParse(v.toString()) ?? 0);
    final parts = n.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    int count = 0;
    for (int i = parts.length - 1; i >= 0; i--) {
      buffer.write(parts[i]);
      count++;
      if (count % 3 == 0 && i > 0 && parts[i] != '-') buffer.write('.');
    }
    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return v.toString().split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final facturas = (d?['facturas'] as List<dynamic>?) ?? [];
    final balance = d?['balance'] ?? 0;
    final saldo = d?['saldoFacturas'] ?? 0;
    final totalAbiertas = d?['totalFacturasAbiertas'] ?? 0;
    final vencidas = d?['facturasVencidas'] ?? 0;

    return _SheetWrapper(
      title: 'Cartera',
      icon: Icons.account_balance_wallet_rounded,
      color: widget.color,
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : (d == null
              ? Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(Icons.error_outline_rounded, color: AppTheme.textSecondary, size: 40),
                    const SizedBox(height: 10),
                    Text('No se pudo cargar la cartera',
                        style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _cargar,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
                      child: const Text('Reintentar'),
                    ),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: _stat('Saldo SAP', _formatMoney(balance), AppTheme.errorColor, Icons.account_balance_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Saldo facturas', _formatMoney(saldo), AppTheme.accentColor, Icons.receipt_long_rounded)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat('Abiertas', '$totalAbiertas', AppTheme.primaryBlue, Icons.folder_open_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Vencidas', '$vencidas',
                          vencidas is int && vencidas > 0 ? AppTheme.errorColor : AppTheme.successColor,
                          Icons.warning_amber_rounded)),
                    ]),
                    const SizedBox(height: 18),
                    Text('Facturas pendientes',
                        style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    if (facturas.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded, color: AppTheme.successColor),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Sin facturas pendientes',
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
                        ]),
                      )
                    else
                      ...facturas.map((raw) {
                        final f = Map<String, dynamic>.from(raw as Map);
                        final venc = f['vencida'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: venc ? AppTheme.errorColor.withOpacity(0.3) : AppTheme.borderColor,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: (venc ? AppTheme.errorColor : AppTheme.primaryBlue).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                venc ? Icons.warning_amber_rounded : Icons.receipt_rounded,
                                color: venc ? AppTheme.errorColor : AppTheme.primaryBlue,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('#${f['numero'] ?? '—'}',
                                  style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('Vence: ${_formatDate(f['vencimiento'])}',
                                  style: TextStyle(
                                    color: venc ? AppTheme.errorColor : AppTheme.textSecondary,
                                    fontWeight: FontWeight.w500, fontSize: 12,
                                  )),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(_formatMoney(f['saldo']),
                                  style: TextStyle(color: AppTheme.darkBlue, fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text('Total: ${_formatMoney(f['total'])}',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            ]),
                          ]),
                        );
                      }),
                  ]),
                )),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color.withOpacity(0.7), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label.toUpperCase(),
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// =============================================================
//  Comentarios bottom sheet — listar y agregar
// =============================================================
class _ComentariosSheet extends StatefulWidget {
  final String codigo;
  final String nombreCliente;
  final ApiEasyService api;
  final Color color;

  const _ComentariosSheet({
    required this.codigo,
    required this.nombreCliente,
    required this.api,
    required this.color,
  });

  @override
  State<_ComentariosSheet> createState() => _ComentariosSheetState();
}

class _ComentariosSheetState extends State<_ComentariosSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final data = await widget.api.getComentariosCliente(widget.codigo);
    if (mounted) setState(() { _items = data; _loading = false; });
  }

  Future<void> _enviar() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty || _sending) return;
    setState(() => _sending = true);
    final nuevo = await widget.api.crearComentarioCliente(widget.codigo, txt);
    if (!mounted) return;
    if (nuevo != null) {
      _ctrl.clear();
      setState(() { _items = [nuevo, ..._items]; _sending = false; });
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el comentario')),
      );
    }
  }

  String _formatFecha(dynamic v) {
    if (v == null) return '';
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SheetWrapper(
        title: 'Comentarios',
        icon: Icons.chat_bubble_rounded,
        color: widget.color,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                : (_items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AppTheme.textSecondary.withOpacity(0.5)),
                            const SizedBox(height: 10),
                            Text('Sin comentarios aún',
                                style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final autor = (c['usuarioNombre'] ?? '').toString();
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: widget.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(Icons.person_rounded, color: widget.color, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    autor.isEmpty ? 'Vendedor' : autor,
                                    style: TextStyle(color: AppTheme.darkBlue, fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(_formatFecha(c['fechaCreacion']),
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                              ]),
                              const SizedBox(height: 8),
                              Text(c['comentario']?.toString() ?? '',
                                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4)),
                            ]),
                          );
                        },
                      )),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribe un comentario...',
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: widget.color, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _enviar(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : _enviar,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [widget.color, AppTheme.primaryBlue]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: widget.color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
