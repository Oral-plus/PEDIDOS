// Las listas de precios que usan los clientes del gestor, y el precio de cada
// producto en cada una.
//
// El servidor manda solo los precios de lista; el descuento se simula en la
// app, en el momento, sin volver a preguntarle.

import '../utils/descuento.dart';

String _texto(Object? v) => (v ?? '').toString().trim();
int _entero(Object? v) => (v as num?)?.toInt() ?? 0;

class ListaPrecios {
  final int id;
  final String nombre;
  final int clientes;
  final int productos;

  const ListaPrecios({
    required this.id,
    required this.nombre,
    this.clientes = 0,
    this.productos = 0,
  });

  factory ListaPrecios.fromJson(Map<String, dynamic> j) => ListaPrecios(
        id: _entero(j['id']),
        nombre: _texto(j['nombre']).isEmpty ? 'Lista ${_entero(j['id'])}' : _texto(j['nombre']),
        clientes: _entero(j['clientes']),
        productos: _entero(j['productos']),
      );

  String get detalle {
    final cli = clientes == 1 ? '1 cliente' : '$clientes clientes';
    final prod = productos == 1 ? '1 producto' : '$productos productos';
    return '$cli · $prod';
  }
}

class ProductoListas {
  final String codigo;
  final String nombre;
  final String categoria;
  final String grupoSap;
  final String? imagenUrl;

  /// Precio de lista por id de lista. Solo trae las listas donde tiene precio.
  final Map<int, double> precios;

  const ProductoListas({
    required this.codigo,
    required this.nombre,
    this.categoria = '',
    this.grupoSap = '',
    this.imagenUrl,
    this.precios = const {},
  });

  factory ProductoListas.fromJson(Map<String, dynamic> j) {
    final precios = <int, double>{};
    final crudos = j['precios'];
    if (crudos is Map) {
      crudos.forEach((clave, valor) {
        final id = int.tryParse(clave.toString());
        final precio = (valor as num?)?.toDouble() ?? 0;
        if (id != null && precio > 0) precios[id] = precio;
      });
    }
    return ProductoListas(
      codigo: _texto(j['codigo']),
      nombre: _texto(j['nombre']),
      categoria: _texto(j['categoria']),
      grupoSap: _texto(j['grupoSap']),
      imagenUrl: _texto(j['imagenUrl']).isEmpty ? null : _texto(j['imagenUrl']),
      precios: precios,
    );
  }

  double? precioEn(int lista) => precios[lista];

  /// El precio en esa lista con el descuento simulado.
  double? precioEnCon(int lista, double pct) {
    final base = precios[lista];
    return base == null ? null : Descuento.aplicar(base, pct);
  }

  bool coincideCon(String busqueda) {
    if (busqueda.isEmpty) return true;
    final q = busqueda.toLowerCase();
    return nombre.toLowerCase().contains(q) ||
        codigo.toLowerCase().contains(q) ||
        categoria.toLowerCase().contains(q);
  }
}

class CatalogoListas {
  final bool exito;
  final List<ListaPrecios> listas;
  final List<ProductoListas> productos;
  final List<String> categorias;
  final String actualizado;

  const CatalogoListas({
    required this.exito,
    this.listas = const [],
    this.productos = const [],
    this.categorias = const [],
    this.actualizado = '',
  });

  const CatalogoListas.fallo() : this(exito: false);

  factory CatalogoListas.fromJson(Map<String, dynamic> j) => CatalogoListas(
        exito: true,
        listas: (j['listas'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => ListaPrecios.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        productos: (j['productos'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => ProductoListas.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        categorias: (j['categorias'] as List<dynamic>? ?? const [])
            .map((e) => _texto(e))
            .where((e) => e.isNotEmpty)
            .toList(),
        actualizado: _texto(j['actualizado']),
      );

  bool get vacio => listas.isEmpty || productos.isEmpty;

  /// Productos que pasan la búsqueda y la categoría elegida.
  List<ProductoListas> filtrar({String busqueda = '', String? categoria}) => productos
      .where((p) => (categoria == null || p.categoria == categoria) && p.coincideCon(busqueda))
      .toList();
}
