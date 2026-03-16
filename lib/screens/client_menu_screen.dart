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
  static Color get _success => AppTheme.successColor;
  static Color get _danger => AppTheme.errorColor;
  static const Color _dangerBg = Color(0xFFFEF2F2);

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

    Navigator.of(context).pushReplacement(
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
                        _buildClienteInfoCard(),
                        const SizedBox(height: 20),
                        _buildGoButton(),
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
      decoration: BoxDecoration(color: _dangerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _danger.withOpacity(0.15))),
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

  Widget _buildClienteInfoCard() {
    final c = _clienteSeleccionado!;
    final codigo = c['id']?.toString() ?? '';
    final nombre = c['nombre'] ?? c['cardName'] ?? c['nombre1'] ?? '—';
    final sap = _clienteDetalleSAP;
    final telefono = sap?['telefono']?.toString() ?? '—';
    final direccion = sap?['direccion']?.toString() ?? '—';
    final balance = sap?['balance'] ?? 0;
    final vendedor = sap?['vendedor']?.toString() ?? '—';
    final totalFacturas = sap?['totalFacturasAbiertas'] ?? 0;
    final facturasVencidas = sap?['facturasVencidas'] ?? 0;

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
              Expanded(child: _statCard(Icons.account_balance_wallet_rounded, 'Cartera', _formatCurrency(balance), (balance as num) > 0 ? _danger : _success)),
              const SizedBox(width: 10),
              Expanded(child: _statCard(Icons.receipt_long_rounded, 'Facturas', '$totalFacturas abiertas', _blueLight)),
            ]),
          ),
          if (facturasVencidas > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: _dangerBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _danger.withOpacity(0.12))),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: _danger.withOpacity(0.8), size: 18),
                  const SizedBox(width: 10),
                  Text('$facturasVencidas factura${facturasVencidas > 1 ? 's' : ''} vencida${facturasVencidas > 1 ? 's' : ''}',
                    style: TextStyle(color: _danger.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(children: [
            _detailRow(Icons.phone_rounded, 'Teléfono', telefono),
            const SizedBox(height: 8),
            _detailRow(Icons.location_on_rounded, 'Dirección', direccion),
            if (sap != null) ...[const SizedBox(height: 8), _detailRow(Icons.badge_rounded, 'Vendedor', vendedor)],
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
