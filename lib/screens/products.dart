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
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
       scrolledUnderElevation: 0,
      title: Image.asset(AppAssets.logo, height: 40),
      centerTitle: true,
      actions: [
        if (_cargandoPrecios || _cargandoEstados)
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.person_pin_rounded, color: _codigoClienteActual.isNotEmpty ? AppTheme.primaryBlue : Colors.grey),
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
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _isSearching ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
            _searchTextController.clear();
            setState(() {
              _isSearching = false;
              _searchQuery = '';
            });
          }) : null,
          filled: true,
          fillColor: AppTheme.lightBlue,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppTheme.accentColor,
        indicatorWeight: 3,
        labelColor: AppTheme.primaryBlue,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(text: 'Todos'),
          Tab(text: 'Cepillos'),
          Tab(text: 'Cremas'),
          Tab(text: 'Enjuagues'),
          Tab(text: 'Sedas'),
          Tab(text: 'Niños'),
          Tab(text: 'Kits'),
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
              themeColor: AppTheme.primaryBlue,
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
            color: AppTheme.successColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: AppTheme.successColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
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
                backgroundColor: AppTheme.primaryBlue,
                elevation: 8,
                icon: Stack(
                  children: [
                    const Icon(Icons.shopping_cart, color: Colors.white),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '${cart.itemCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
