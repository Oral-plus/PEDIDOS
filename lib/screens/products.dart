import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/producto.dart';
import '../providers/session_provider.dart';
import '../providers/cart_provider.dart';
import '../services/catalogo_service.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/product_preview_dialog.dart';
import '../widgets/texture_selection_dialog.dart';
import '../widgets/codigo_cliente_dialog.dart';
import '../utils/app_assets.dart';
import '../utils/theme.dart';
import '../utils/responsive_utils.dart';

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

  // Se crea cuando llega el catálogo: una pestaña por categoría del servidor
  TabController? _tabController;
  List<String> _categorias = [];
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
  // Productos agrupados por categoría una sola vez. Son los mismos mapas, así
  // que los precios SAP actualizados se ven en todas las pestañas.
  final Map<String, List<Map<String, dynamic>>> _porCategoria = {};
  Timer? _debounce;

  // Catálogo (SAP + configuración de soporte) con los precios del cliente actual
  String _codigoClienteActual = '';
  Map<String, Map<String, dynamic>> _preciosSAP = {};
  Map<String, Map<String, dynamic>> _estadosSAP = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack));

    _startAnimations();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _codigoClienteActual = context.read<SessionProvider>().codigoCliente;
      _cargarCatalogo();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController?.dispose();
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

  /// Descarga (o toma de caché) el catálogo con los precios del cliente actual.
  Future<void> _cargarCatalogo({bool forzar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final catalogo = await CatalogoService().obtener(_codigoClienteActual, forzar: forzar);
    if (!mounted) return;
    if (catalogo == null) {
      setState(() {
        _cargando = false;
        if (_allProducts.isEmpty) _error = 'No se pudo cargar el catálogo. Revisa la conexión e intenta de nuevo.';
      });
      return;
    }
    _aplicarCatalogo(catalogo);
  }

  void _aplicarCatalogo(Catalogo catalogo) {
    final productos = catalogo.productos.map((p) => p.toMapUi()).toList();
    final porCategoria = <String, List<Map<String, dynamic>>>{};
    for (final p in productos) {
      // Texto de búsqueda en minúsculas, calculado una vez
      p['_busqueda'] = '${p['title'] ?? ''} ${p['codigoSap'] ?? ''} ${p['category'] ?? ''}'.toLowerCase();
      porCategoria.putIfAbsent(p['category']?.toString() ?? '', () => []).add(p);
    }
    final categorias = catalogo.categorias.map((c) => c.nombre).toList();
    final pestanas = 1 + categorias.length;
    if (_tabController == null || _tabController!.length != pestanas) {
      _tabController?.dispose();
      _tabController = TabController(length: pestanas, vsync: this);
    }
    setState(() {
      _allProducts = productos;
      _porCategoria
        ..clear()
        ..addAll(porCategoria);
      _categorias = categorias;
      _preciosSAP = catalogo.preciosPorCodigo;
      _estadosSAP = catalogo.estadosPorCodigo;
      _cargando = false;
      _error = null;
      if (_isSearching) _filteredProducts = _calcularFiltrados();
    });
  }

  List<Map<String, dynamic>> _calcularFiltrados() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return [];
    return _allProducts
        .where((p) => (p['_busqueda'] as String? ?? '').contains(query))
        .toList();
  }

  void _filterAllProducts() {
    if (!mounted) return;
    setState(() => _filteredProducts = _calcularFiltrados());
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
      _cargarCatalogo();
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
                if (_tabController != null && !_isSearching) _buildTabs(),
                Expanded(
                  child: _tabController == null
                      ? _buildEstadoCatalogo()
                      : (_isSearching ? _buildSearchResults() : _buildTabContent()),
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
        if (_cargando)
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
          _searchQuery = val;
          final buscando = val.isNotEmpty;
          if (buscando != _isSearching) {
            // Al empezar o terminar la búsqueda se refresca de inmediato
            setState(() {
              _isSearching = buscando;
              _filteredProducts = _calcularFiltrados();
            });
          }
          // El resto se filtra cuando el vendedor deja de escribir
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 250), _filterAllProducts);
        },
        cursorColor: _ink,
        style: const TextStyle(fontSize: 14, color: _ink, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: const TextStyle(color: _gray, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: _gray),
          suffixIcon: _isSearching ? IconButton(icon: const Icon(Icons.clear_rounded, color: _gray), onPressed: () {
            _searchTextController.clear();
            _debounce?.cancel();
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _filteredProducts = [];
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
        controller: _tabController!,
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
        tabs: [
          const _PillTab(text: 'Todos'),
          for (final c in _categorias) _PillTab(text: c),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController!,
      children: [
        _buildProductGrid('Todos'),
        for (final c in _categorias) _buildProductGrid(c),
      ],
    );
  }

  /// Mientras no hay catálogo: cargando, o error con opción de reintentar
  Widget _buildEstadoCatalogo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _inkSoft));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: _gray.withOpacity(0.6)),
            const SizedBox(height: 14),
            Text(
              _error ?? 'Sin productos para mostrar',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gray, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _cargarCatalogo(forzar: true),
              style: FilledButton.styleFrom(backgroundColor: _ink),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid(String category) {
    final products = category == 'SearchResult'
        ? _filteredProducts
        : (category == 'Todos'
            ? _allProducts
            : (_porCategoria[category] ?? const <Map<String, dynamic>>[]));

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
