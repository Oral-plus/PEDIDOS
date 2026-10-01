import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lista_precios.dart';
import '../services/api_easy_service.dart';
import '../utils/descuento.dart';
import '../utils/price_utils.dart';

/// Módulo Producto: se busca un producto arriba y abajo salen sus precios en
/// cada lista de precios que usan los clientes del gestor.
///
/// El descuento no viaja al servidor: se escribe y los precios se recalculan al
/// instante. Solo se vuelven a dibujar los precios, no la pantalla.
class ListasPreciosScreen extends StatefulWidget {
  const ListasPreciosScreen({super.key});

  @override
  State<ListasPreciosScreen> createState() => _ListasPreciosScreenState();
}

class _ListasPreciosScreenState extends State<ListasPreciosScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _azul = Color(0xFF1A56DB);

  static const List<double> _atajos = [5, 10, 15, 20];

  final ApiEasyService _api = ApiEasyService();

  /// Lo único que cambia al teclear el descuento: escucharlo evita redibujar
  /// la pantalla entera.
  final ValueNotifier<double> _descuento = ValueNotifier<double>(0);
  final TextEditingController _campoDescuento = TextEditingController();

  bool _cargando = true;
  String? _error;
  CatalogoListas _catalogo = const CatalogoListas.fallo();
  String? _codigo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _descuento.dispose();
    _campoDescuento.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final datos = await _api.getListasPrecios(forzar: forzar);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _catalogo = datos;
      _error = datos.exito ? null : 'No se pudieron cargar las listas de precios';
      _codigo = datos.productos.isEmpty ? null : datos.productos.first.codigo;
    });
  }

  ProductoListas? get _producto => _catalogo.productoPorCodigo(_codigo);

  void _fijarDescuento(double pct) {
    final valor = Descuento.normalizar(pct);
    _descuento.value = valor;
    final texto = valor == 0 ? '' : (valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : '$valor');
    if (_campoDescuento.text != texto) {
      _campoDescuento.text = texto;
      _campoDescuento.selection = TextSelection.collapsed(offset: texto.length);
    }
  }

  Future<void> _elegirProducto() async {
    HapticFeedback.selectionClick();
    final elegido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _SelectorProductos(catalogo: _catalogo, actual: _codigo),
    );
    if (elegido == null || !mounted) return;
    setState(() => _codigo = elegido);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const Text('Producto',
            style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded, color: _ink),
            onPressed: _cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _mensaje(Icons.cloud_off_rounded, _error!)
              : _catalogo.vacio || _producto == null
                  ? _mensaje(Icons.sell_outlined, 'Tus clientes no tienen listas de precios con productos')
                  : _contenido(),
    );
  }

  Widget _contenido() => Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: [
            _selectorProducto(),
            const SizedBox(height: 12),
            _simulador(),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Expanded(child: _listados()),
      ]);

  Widget _selectorProducto() => InkWell(
        onTap: _elegirProducto,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, size: 20, color: _azul),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PRODUCTO',
                    style: TextStyle(color: _gray, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(_producto!.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _inkDeep, fontSize: 15.5, fontWeight: FontWeight.w800)),
                Text(_detalleProducto(_producto!),
                    style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.unfold_more_rounded, color: _gray),
          ]),
        ),
      );

  static String _detalleProducto(ProductoListas p) =>
      p.categoria.isEmpty ? p.codigo : '${p.codigo} · ${p.categoria}';

  Widget _simulador() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 150,
            child: TextField(
              controller: _campoDescuento,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _inkDeep),
              decoration: InputDecoration(
                labelText: 'Descuento',
                suffixText: '%',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (t) => _descuento.value = Descuento.desdeTexto(t),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in _atajos) _atajo(p),
              _atajo(0, etiqueta: 'Sin descuento'),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        ValueListenableBuilder<double>(
          valueListenable: _descuento,
          builder: (_, pct, __) => Text(
            pct <= 0
                ? 'Escribe un descuento y cada lista muestra cómo quedaría este producto.'
                : 'Simulando ${_pct(pct)} % sobre el precio de cada lista.',
            style: TextStyle(
              color: pct <= 0 ? _gray : _verde,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ]);

  Widget _atajo(double pct, {String? etiqueta}) => ValueListenableBuilder<double>(
        valueListenable: _descuento,
        builder: (_, actual, __) {
          final activo = actual == pct;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _fijarDescuento(pct);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: activo ? _inkDeep : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: activo ? _inkDeep : _line),
              ),
              child: Text(
                etiqueta ?? '${pct.toStringAsFixed(0)} %',
                style: TextStyle(
                  color: activo ? Colors.white : _gray,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      );

  Widget _listados() {
    final listas = _catalogo.listas;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Text('${listas.length} lista(s) de precios',
              style: const TextStyle(color: _gray, fontSize: 11.5, fontWeight: FontWeight.w700)),
          const Spacer(),
          const Text('PRECIO',
              style: TextStyle(color: _gray, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: listas.length,
          itemBuilder: (_, i) => _fila(listas[i], i.isOdd),
        ),
      ),
    ]);
  }

  Widget _fila(ListaPrecios lista, bool alterna) => Container(
        color: alterna ? const Color(0xFFFAFAFB) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lista.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(lista.detalle, style: const TextStyle(color: _gray, fontSize: 11.5)),
            ]),
          ),
          const SizedBox(width: 12),
          _precio(lista),
        ]),
      );

  Widget _precio(ListaPrecios lista) {
    final base = _producto!.precioEn(lista.id);
    if (base == null) {
      return const Text('Sin precio en esta lista',
          style: TextStyle(color: _gray, fontSize: 12, fontWeight: FontWeight.w600));
    }
    return ValueListenableBuilder<double>(
      valueListenable: _descuento,
      builder: (_, pct, __) {
        if (pct <= 0) {
          return Text('\$${PriceUtils.formatPrice(base)}',
              style: const TextStyle(color: _inkDeep, fontSize: 16, fontWeight: FontWeight.w800));
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${PriceUtils.formatPrice(base)}',
                style: const TextStyle(
                  color: _gray,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.lineThrough,
                )),
            Text('-\$${PriceUtils.formatPrice(Descuento.ahorro(base, pct))}',
                style: const TextStyle(color: _azul, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: _gray),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text('\$${PriceUtils.formatPrice(_producto!.precioEnCon(lista.id, pct))}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: _verde, fontSize: 17, fontWeight: FontWeight.w900)),
          ),
        ]);
      },
    );
  }

  String _pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  Widget _mensaje(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icono, size: 44, color: _gray),
          const SizedBox(height: 12),
          Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gray, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Buscador de productos: el gestor escribe nombre o código y elige el suyo.
class _SelectorProductos extends StatefulWidget {
  final CatalogoListas catalogo;
  final String? actual;

  const _SelectorProductos({required this.catalogo, this.actual});

  @override
  State<_SelectorProductos> createState() => _SelectorProductosState();
}

class _SelectorProductosState extends State<_SelectorProductos> {
  final TextEditingController _busqueda = TextEditingController();
  String _texto = '';

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = widget.catalogo.filtrar(busqueda: _texto);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _ListasPreciosScreenState._line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Buscar producto',
                    style: TextStyle(
                        color: _ListasPreciosScreenState._inkDeep, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  controller: _busqueda,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nombre, código o categoría',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (t) => setState(() => _texto = t.trim()),
                ),
                const SizedBox(height: 6),
                Text('${visibles.length} producto(s)',
                    style: const TextStyle(
                        color: _ListasPreciosScreenState._gray, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: visibles.isEmpty
                  ? const Center(
                      child: Text('Ningún producto coincide',
                          style: TextStyle(
                              color: _ListasPreciosScreenState._gray, fontWeight: FontWeight.w600)),
                    )
                  : ListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (_, i) {
                        final p = visibles[i];
                        final elegido = p.codigo == widget.actual;
                        return ListTile(
                          leading: Icon(
                            elegido ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            color: elegido
                                ? _ListasPreciosScreenState._azul
                                : _ListasPreciosScreenState._gray,
                          ),
                          title: Text(p.nombre,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: elegido ? FontWeight.w800 : FontWeight.w600,
                                color: _ListasPreciosScreenState._ink,
                              )),
                          subtitle: Text(_ListasPreciosScreenState._detalleProducto(p),
                              style: const TextStyle(
                                  fontSize: 12, color: _ListasPreciosScreenState._gray)),
                          onTap: () => Navigator.of(context).pop(p.codigo),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
