import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../providers/cart_provider.dart';
import '../services/product_data_service.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/product_preview_dialog.dart';
import '../widgets/texture_selection_dialog.dart';
import '../widgets/codigo_cliente_dialog.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/price_utils.dart';
import '../services/Sap_service.dart' as sap;

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> with TickerProviderStateMixin {
  // Paleta monocromática elegante (blanco / negro / gris)
  static const Color _ink = Color(0xFF111827); // negro suave
  static const Color _inkSoft = Color(0xFF1F2937); // gris oscuro
  static const Color _gray = Color(0xFF6B7280); // gris medio
  static const Color _surface = Color(0xFFF3F4F6); // gris muy claro
  static const Color _line = Color(0xFFECECEE); // línea sutil

  late TabController _tabController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  final TextEditingController _searchTextController = TextEditingController();
  String _searchQuery = '';
  String? _lastAddedProduct;
  Offset _bannerOffset = const Offset(0, -1);
  bool _isSearching = false;
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  // SAP and User variables
  String _codigoClienteActual = '';
  Map<String, Map<String, dynamic>> _preciosSAP = {};
  Map<String, Map<String, dynamic>> _estadosSAP = {};
  bool _cargandoPrecios = false;
  bool _cargandoEstados = false;

  @override
  void initState() {
    super.initState();
    _allProducts = ProductDataService.getAllProducts();
    _tabController = TabController(length: 7, vsync: this);

    _fadeController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack));

    _startAnimations();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<SessionProvider>();
      if (session.codigoCliente.isNotEmpty) {
        setState(() => _codigoClienteActual = session.codigoCliente);
        _cargarDatosSAP();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      _fadeController.forward();
      _slideController.forward();
      _scaleController.forward();
    }
  }

  Future<void> _cargarDatosSAP() async {
    if (_codigoClienteActual.isEmpty) return;

    final codigosSAP = <String>{};
    for (final product in _allProducts) {
      codigosSAP.add(product['codigoSap'] ?? '');
      if (product['codigoSapSuave'] != null) codigosSAP.add(product['codigoSapSuave']!);
      if (product['codigoSapAlternativo'] != null) codigosSAP.add(product['codigoSapAlternativo']!);
    }

    final codigosLista = codigosSAP.where((codigo) => codigo.isNotEmpty).toList();
    if (codigosLista.isEmpty) return;

    await Future.wait([
      _cargarPreciosSAP(codigosLista),
      _cargarEstadosSAP(codigosLista),
    ]);
  }

  Future<void> _cargarPreciosSAP(List<String> codigos) async {
    if (_codigoClienteActual.isEmpty) return;
    setState(() => _cargandoPrecios = true);

    try {
      final resultado = await sap.InvoiceService1.obtenerPreciosSAP(codigos, _codigoClienteActual);
      if (resultado['success'] == true && resultado['precios'] != null) {
        setState(() {
          _preciosSAP = Map<String, Map<String, dynamic>>.from(resultado['precios']);
        });
        _actualizarPreciosEnTiempoReal();
      }
    } catch (e) {
      debugPrint('Error loading SAP prices: $e');
    } finally {
      if (mounted) setState(() => _cargandoPrecios = false);
    }
  }

  Future<void> _cargarEstadosSAP(List<String> codigos) async {
    if (mounted) setState(() => _cargandoEstados = true);
    try {
      final resultado = await sap.InvoiceService1.obtenerEstadosProductosSAP(codigos, _codigoClienteActual.isNotEmpty ? _codigoClienteActual : 'DEFAULT');
      if (resultado['success'] == true && resultado['productos'] != null) {
        setState(() {
          _estadosSAP = Map<String, Map<String, dynamic>>.from(resultado['productos']);
        });
      }
    } catch (e) {
      debugPrint('Error loading SAP states: $e');
    } finally {
      if (mounted) setState(() => _cargandoEstados = false);
    }
  }

  void _actualizarPreciosEnTiempoReal() {
    setState(() {
      for (int i = 0; i < _allProducts.length; i++) {
        final codigoSap = _allProducts[i]['codigoSap'] ?? '';
        if (codigoSap.isNotEmpty && _preciosSAP.containsKey(codigoSap)) {
          final precio = _preciosSAP[codigoSap]!['precio'];
          final formatted = sap.InvoiceService1.formatearPrecioSAP(precio);
          if (formatted != 'Precio no disponible') {
            _allProducts[i]['price'] = PriceUtils.formatPriceDisplay(formatted);
          }
        }
      }
      if (_isSearching) _filterAllProducts();
    });
  }

  void _filterAllProducts() {
    if (_searchQuery.isEmpty) {
      setState(() => _filteredProducts = []);
      return;
    }
    setState(() {
      _filteredProducts = _allProducts.where((product) {
        final query = _searchQuery.toLowerCase();
        return (product['title']?.toString().toLowerCase().contains(query) ?? false) ||
               (product['codigoSap']?.toString().toLowerCase().contains(query) ?? false) ||
               (product['category']?.toString().toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  void _addToCart(Map<String, dynamic> product) {
    context.read<CartProvider>().addItem(product);
    HapticFeedback.mediumImpact();
    setState(() {
      _lastAddedProduct = product['title'];
      _bannerOffset = Offset.zero;
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _bannerOffset = const Offset(0, -1));
    });
  }

  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CartBottomSheet(),
    );
  }

  void _showProductPreview(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => ProductPreviewDialog(
        product: product,
        preciosSAP: _preciosSAP,
        estadosSAP: _estadosSAP,
        onAddToCart: _addToCart,
        onShowTextureSelection: _showTextureSelection,
      ),
    );
  }

  void _showTextureSelection(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => TextureSelectionDialog(
        product: product,
        preciosSAP: _preciosSAP,
        estadosSAP: _estadosSAP,
        onAddToCart: _addToCart,
      ),
    );
  }

  Future<void> _confirmarCodigo() async {
    final controller = TextEditingController(text: _codigoClienteActual);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => CodigoClienteDialog(controller: controller),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _codigoClienteActual = result);
      context.read<SessionProvider>().setCodigoCliente(result);
      _cargarDatosSAP();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildEnhancedSearchBar(),
                if (!_isSearching) _buildTabs(),
                Expanded(
                  child: _isSearching ? _buildSearchResults() : _buildTabContent(),
                ),
              ],
            ),
          ),
          if (_lastAddedProduct != null) _buildAddedProductBanner(),
          Positioned(
            bottom: 24,
            right: 24,
            child: _buildFloatingCartButton(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final session = context.watch<SessionProvider>();
    final lista = session.listaPrecios;
    final listaCod = session.listaPreciosCodigo;
    final tieneLista = lista.isNotEmpty || listaCod != null;
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AppAssets.logo, height: 34),
          if (tieneLista) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _ink.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _ink.withOpacity(0.12)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.price_change_rounded, size: 12, color: _inkSoft),
                const SizedBox(width: 5),
                Text(
                  lista.isNotEmpty ? lista : 'Lista $listaCod',
                  style: const TextStyle(
                    color: _inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
      centerTitle: true,
      actions: [
        if (_cargandoPrecios || _cargandoEstados)
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _inkSoft),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.person_pin_rounded, color: _codigoClienteActual.isNotEmpty ? _inkSoft : _gray),
          onPressed: _confirmarCodigo,
        ),
      ],
    );
  }

  Widget _buildEnhancedSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchTextController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
            _isSearching = val.isNotEmpty;
          });
          _filterAllProducts();
        },
        cursorColor: _ink,
        style: const TextStyle(fontSize: 14, color: _ink, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: const TextStyle(color: _gray, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: _gray),
          suffixIcon: _isSearching ? IconButton(icon: const Icon(Icons.clear_rounded, color: _gray), onPressed: () {
            _searchTextController.clear();
            setState(() {
              _isSearching = false;
              _searchQuery = '';
            });
          }) : null,
          filled: true,
          fillColor: _surface,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _ink, width: 1.4)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicator: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(30),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(30),
        labelColor: Colors.white,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.2),
        unselectedLabelColor: _gray,
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: const [
          _PillTab(text: 'Todos'),
          _PillTab(text: 'Cepillos'),
          _PillTab(text: 'Cremas'),
          _PillTab(text: 'Enjuagues'),
          _PillTab(text: 'Sedas'),
          _PillTab(text: 'Niños'),
          _PillTab(text: 'Kits'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildProductGrid('Todos'),
        _buildProductGrid('Cepillos'),
        _buildProductGrid('Cremas'),
        _buildProductGrid('Enjuagues'),
        _buildProductGrid('Sedas'),
        _buildProductGrid('Universo Nios'),
        _buildProductGrid('Kits'),
      ],
    );
  }

  Widget _buildProductGrid(String category) {
    final products = category == 'SearchResult' 
        ? _filteredProducts
        : (category == 'Todos' 
            ? _allProducts 
            : _allProducts.where((p) => p['category'] == category).toList());

    if (products.isEmpty && category == 'SearchResult') {
      return _buildEmptySearchResults();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: context.isTablet ? 3 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.65,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ProductCard(
              product: product,
              themeColor: _ink,
              preciosSAP: _preciosSAP,
              estadosSAP: _estadosSAP,
              onTap: () => _showProductPreview(product),
              onAddToCart: () {
                if (product['hasTextureOptions'] == true) {
                  _showTextureSelection(product);
                } else {
                  _addToCart(product);
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return _buildProductGrid('SearchResult');
  }

  Widget _buildEmptySearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'No se encontraron productos para "$_searchQuery"',
            style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAddedProductBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _bannerOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: _ink.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¡Agregado: $_lastAddedProduct!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingCartButton() {
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        if (cart.itemCount == 0) return const SizedBox.shrink();
        
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: FloatingActionButton.extended(
                onPressed: _showCart,
                backgroundColor: _ink,
                elevation: 6,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_rounded, color: Colors.white),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _ink, width: 1.5),
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '${cart.itemCount}',
                          style: const TextStyle(color: _ink, fontSize: 9, fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                label: Text(
                  cart.formattedTotal,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Pestaña con forma de píldora (padding interno para el indicador redondeado).
class _PillTab extends StatelessWidget {
  final String text;
  const _PillTab({required this.text});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(text),
      ),
    );
  }
}
