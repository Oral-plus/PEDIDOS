import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lista_precios.dart';
import '../services/api_easy_service.dart';
import '../utils/descuento.dart';
import '../utils/price_utils.dart';

/// Módulo Producto: las listas de precios que usan los clientes del gestor.
///
/// El descuento de arriba no viaja al servidor: se escribe y los precios de
/// abajo se recalculan al instante. Solo se vuelven a dibujar las celdas de
/// precio, no la tabla entera.
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

  static const double _anchoNombre = 250;
  static const double _anchoPrecio = 150;
  static const List<double> _atajos = [5, 10, 15, 20];

  final ApiEasyService _api = ApiEasyService();

  /// Lo único que cambia al teclear: escucharlo evita redibujar la tabla.
  final ValueNotifier<double> _descuento = ValueNotifier<double>(0);
  final TextEditingController _campoDescuento = TextEditingController();
  final TextEditingController _campoBusqueda = TextEditingController();

  bool _cargando = true;
  String? _error;
  CatalogoListas _catalogo = const CatalogoListas.fallo();
  String _busqueda = '';
  String? _categoria;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _descuento.dispose();
    _campoDescuento.dispose();
    _campoBusqueda.dispose();
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
    });
  }

  void _fijarDescuento(double pct) {
    final valor = Descuento.normalizar(pct);
    _descuento.value = valor;
    final texto = valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toString();
    if (_campoDescuento.text != texto) {
      _campoDescuento.text = texto;
      _campoDescuento.selection = TextSelection.collapsed(offset: texto.length);
    }
  }

  List<ProductoListas> get _visibles =>
      _catalogo.filtrar(busqueda: _busqueda, categoria: _categoria);

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
              : _catalogo.vacio
                  ? _mensaje(Icons.sell_outlined, 'Tus clientes no tienen listas de precios con productos')
                  : _contenido(),
    );
  }

  Widget _contenido() => Column(children: [
        _simulador(),
        _buscador(),
        const Divider(height: 1, color: _line),
        Expanded(child: _tabla()),
      ]);

  Widget _simulador() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 170,
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
                  ? 'Escribe un descuento y los precios de abajo lo muestran aplicado.'
                  : 'Simulando ${_pct(pct)} %: debajo de cada precio de lista va el precio con descuento.',
              style: TextStyle(
                color: pct <= 0 ? _gray : _verde,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ]),
      );

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

  Widget _buscador() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _campoBusqueda,
              style: const TextStyle(fontSize: 14, color: _ink),
              decoration: InputDecoration(
                hintText: 'Buscar producto o código',
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: _gray),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _campoBusqueda.clear();
                          setState(() => _busqueda = '');
                        },
                      ),
              ),
              onChanged: (t) => setState(() => _busqueda = t.trim()),
            ),
          ),
          if (_catalogo.categorias.length > 1) ...[
            const SizedBox(width: 10),
            DropdownButton<String?>(
              value: _categoria,
              underline: const SizedBox.shrink(),
              hint: const Text('Categoría', style: TextStyle(fontSize: 13)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas', style: TextStyle(fontSize: 13))),
                for (final c in _catalogo.categorias)
                  DropdownMenuItem<String?>(value: c, child: Text(c, style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _categoria = v),
            ),
          ],
        ]),
      );

  Widget _tabla() {
    final listas = _catalogo.listas;
    final productos = _visibles;
    if (productos.isEmpty) {
      return _mensaje(Icons.search_off_rounded, 'Ningún producto coincide con la búsqueda');
    }
    final ancho = _anchoNombre + _anchoPrecio * listas.length;

    return LayoutBuilder(
      builder: (_, limites) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: ancho > limites.maxWidth ? ancho : limites.maxWidth,
          child: Column(children: [
            _encabezado(listas),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: productos.length,
                itemBuilder: (_, i) => _fila(productos[i], listas, i.isOdd),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _encabezado(List<ListaPrecios> listas) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const SizedBox(
            width: _anchoNombre,
            child: Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text('PRODUCTO',
                  style: TextStyle(color: _gray, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            ),
          ),
          for (final l in listas)
            SizedBox(
              width: _anchoPrecio,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _inkDeep, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(l.detalle, style: const TextStyle(color: _gray, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      );

  Widget _fila(ProductoListas p, List<ListaPrecios> listas, bool alterna) => Container(
        color: alterna ? Colors.white : const Color(0xFFFAFAFB),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: _anchoNombre,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${p.codigo}${p.categoria.isEmpty ? '' : ' · ${p.categoria}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _gray, fontSize: 11)),
              ]),
            ),
          ),
          for (final l in listas) SizedBox(width: _anchoPrecio, child: _celda(p, l)),
        ]),
      );

  Widget _celda(ProductoListas p, ListaPrecios lista) {
    final base = p.precioEn(lista.id);
    if (base == null) {
      return const Text('—', style: TextStyle(color: _line, fontSize: 14, fontWeight: FontWeight.w700));
    }
    return ValueListenableBuilder<double>(
      valueListenable: _descuento,
      builder: (_, pct, __) {
        if (pct <= 0) {
          return Text('\$${PriceUtils.formatPrice(base)}',
              style: const TextStyle(color: _inkDeep, fontSize: 14, fontWeight: FontWeight.w700));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('\$${PriceUtils.formatPrice(base)}',
              style: const TextStyle(
                color: _gray,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.lineThrough,
              )),
          const SizedBox(height: 2),
          Text('\$${PriceUtils.formatPrice(Descuento.aplicar(base, pct))}',
              style: const TextStyle(color: _verde, fontSize: 14.5, fontWeight: FontWeight.w800)),
          Text('-\$${PriceUtils.formatPrice(Descuento.ahorro(base, pct))}',
              style: const TextStyle(color: _azul, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]);
      },
    );
  }

  String _pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

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
