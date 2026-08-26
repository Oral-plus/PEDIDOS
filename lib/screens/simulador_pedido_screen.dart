import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cart_item.dart';
import '../services/catalogo_service.dart';
import '../utils/price_utils.dart';
import '../widgets/producto_imagen.dart';
import '../widgets/app_header.dart';
import '../widgets/app_dialog.dart';

/// Simulador de pedido - cotiza un pedido SIN necesidad de entrar a una
/// visita ni seleccionar cliente. No genera pedido real ni toca el carrito:
/// es una calculadora comercial con los precios del catálogo.
///
/// Muestra siempre los precios con y sin IVA (19%).
class SimuladorPedidoScreen extends StatefulWidget {
  const SimuladorPedidoScreen({super.key});

  @override
  State<SimuladorPedidoScreen> createState() => _SimuladorPedidoScreenState();
}

class _SimuladorPedidoScreenState extends State<SimuladorPedidoScreen> {
  // Paleta monocromática
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);

  final TextEditingController _search = TextEditingController();
  // Catálogo con precios de la lista base (el simulador no tiene cliente)
  List<Map<String, dynamic>> _productos = [];
  bool _cargando = true;

  /// Cantidades simuladas por producto (clave: codigoSap o título).
  final Map<String, int> _cantidades = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(_programarFiltro);
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    final catalogo = await CatalogoService().obtener('');
    if (!mounted) return;
    setState(() {
      _productos = catalogo?.productos.map((p) => p.toMapUi()).toList() ?? [];
      _cargando = false;
    });
  }

  // Se filtra cuando el vendedor deja de escribir, no en cada tecla
  Timer? _debounce;
  void _programarFiltro() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _keyDe(Map<String, dynamic> p) =>
      (p['codigoSap']?.toString().isNotEmpty == true)
          ? p['codigoSap'].toString()
          : (p['title']?.toString() ?? '');

  double _precioDe(Map<String, dynamic> p) => CartItem.parsePrice(p['price']);

  List<Map<String, dynamic>> get _filtrados {
    final q = _search.text.toLowerCase().trim();
    if (q.isEmpty) return _productos;
    return _productos.where((p) {
      return (p['title']?.toString().toLowerCase().contains(q) ?? false) ||
          (p['codigoSap']?.toString().toLowerCase().contains(q) ?? false) ||
          (p['category']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  // Totales de la simulación (precio catálogo = c/IVA)
  int get _totalUnidades => _cantidades.values.fold(0, (a, b) => a + b);
  int get _totalProductos => _cantidades.entries.where((e) => e.value > 0).length;

  double get _totalConIva {
    double t = 0;
    for (final p in _productos) {
      final q = _cantidades[_keyDe(p)] ?? 0;
      if (q > 0) t += _precioDe(p) * q;
    }
    return t;
  }

  double get _totalSinIva => _totalConIva / 1.19;
  double get _totalIva => _totalConIva - _totalSinIva;

  void _cambiar(Map<String, dynamic> p, int delta) {
    HapticFeedback.selectionClick();
    final k = _keyDe(p);
    setState(() {
      final n = (_cantidades[k] ?? 0) + delta;
      if (n <= 0) {
        _cantidades.remove(k);
      } else {
        _cantidades[k] = n.clamp(0, 999999);
      }
    });
  }

  Future<void> _editarCantidad(Map<String, dynamic> p) async {
    final k = _keyDe(p);
    final actual = _cantidades[k] ?? 0;
    final valor = await showAppInput(
      context,
      title: 'Cantidad',
      hint: 'Ej: 12',
      initialValue: actual > 0 ? '$actual' : '',
      icon: Icons.calculate_rounded,
      confirmText: 'Aplicar',
      keyboardType: TextInputType.number,
      numeric: true,
    );
    if (valor == null) return;
    final n = int.tryParse(valor) ?? 0;
    setState(() {
      if (n <= 0) {
        _cantidades.remove(k);
      } else {
        _cantidades[k] = n.clamp(1, 999999);
      }
    });
  }

  Future<void> _limpiar() async {
    if (_cantidades.isEmpty) return;
    final ok = await showAppConfirm(
      context,
      title: 'Limpiar simulación',
      message: '¿Quieres quitar todos los productos de la simulación?',
      confirmText: 'Limpiar',
      icon: Icons.restart_alt_rounded,
    );
    if (ok && mounted) setState(() => _cantidades.clear());
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const AppBarTitle('Simulador de pedido', subtitle: 'Cotiza sin visita'),
        actions: [
          if (_cantidades.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar simulación',
              onPressed: _limpiar,
              icon: const Icon(Icons.restart_alt_rounded, color: _gray),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _avisoSimulacion(),
          _buscador(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: _ink))
                : lista.isEmpty
                ? _sinResultados()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _productoRow(lista[i]),
                  ),
          ),
          _panelTotales(),
        ],
      ),
    );
  }

  Widget _avisoSimulacion() {
    return Container(
      width: double.infinity,
      color: _ink,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.science_rounded, color: Colors.white, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Modo simulación · no genera pedido ni afecta el carrito',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _search,
        cursorColor: _ink,
        style: const TextStyle(fontSize: 14, color: _ink, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Buscar producto, código o categoría...',
          hintStyle: const TextStyle(color: _gray, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: _gray),
          suffixIcon: _search.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: _gray),
                  onPressed: () => _search.clear(),
                )
              : null,
          filled: true,
          fillColor: _surface,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _ink, width: 1.4)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _sinResultados() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off_rounded, size: 60, color: _gray.withOpacity(0.4)),
        const SizedBox(height: 12),
        const Text('Sin resultados',
            style: TextStyle(color: _gray, fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _productoRow(Map<String, dynamic> p) {
    final precio = _precioDe(p);
    final sinIva = precio / 1.19;
    final k = _keyDe(p);
    final q = _cantidades[k] ?? 0;
    final activo = q > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: activo ? _ink.withOpacity(0.45) : _line, width: activo ? 1.3 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        // Imagen
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 52, height: 52,
            color: _surface,
            padding: const EdgeInsets.all(4),
            child: ProductoImagen(
              url: p['image']?.toString(),
              cacheWidth: 160,
              iconSize: 22,
              iconColor: _gray,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Título + precios c/ y sin IVA
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['title']?.toString() ?? 'Producto',
                style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${PriceUtils.formatPriceDisplay(precio)} c/IVA',
              style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            Text(
              '${PriceUtils.formatPriceDisplay(sinIva)} sin IVA',
              style: const TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        // Stepper − n +
        Container(
          decoration: BoxDecoration(
            color: activo ? _ink : _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? _ink : _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _stepBtn(Icons.remove_rounded, activo, () => _cambiar(p, -1)),
            GestureDetector(
              onTap: () => _editarCantidad(p),
              child: Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                alignment: Alignment.center,
                child: Text('$q',
                    style: TextStyle(
                      color: activo ? Colors.white : _gray,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ),
            _stepBtn(Icons.add_rounded, activo, () => _cambiar(p, 1)),
          ]),
        ),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, bool activo, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 32, height: 34,
        alignment: Alignment.center,
        child: Icon(icon, color: activo ? Colors.white : _ink, size: 17),
      ),
    );
  }

  Widget _panelTotales() {
    final vacio = _totalUnidades == 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 20, offset: const Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: vacio
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calculate_rounded, color: _gray, size: 18),
                    SizedBox(width: 8),
                    Text('Agrega productos para simular el pedido',
                        style: TextStyle(color: _gray, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                )
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: _line),
                      ),
                      child: Text('$_totalProductos producto(s) · $_totalUnidades unidad(es)',
                          style: const TextStyle(color: _ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _limpiar,
                      child: const Text('Limpiar',
                          style: TextStyle(
                              color: _gray,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _filaTotal('Subtotal (sin IVA)', PriceUtils.formatPriceDisplay(_totalSinIva), false),
                  const SizedBox(height: 5),
                  _filaTotal('IVA (19%)', PriceUtils.formatPriceDisplay(_totalIva), false),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 9),
                    child: Divider(height: 1, color: _line),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total simulado (c/IVA)',
                          style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(colors: [_ink, _inkDeep]).createShader(r),
                        child: Text(PriceUtils.formatPriceDisplay(_totalConIva),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      ),
                    ],
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _filaTotal(String label, String valor, bool bold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: bold ? _ink : _gray,
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        Text(valor,
            style: TextStyle(
                color: bold ? _ink : _gray,
                fontSize: bold ? 16 : 12.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
      ],
    );
  }
}
