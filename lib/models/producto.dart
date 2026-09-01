import '../utils/price_utils.dart';

class VarianteProducto {
  final String codigo;
  final String textura;
  final double precio;
  final int stock;

  final bool habilitado;

  const VarianteProducto({
    required this.codigo,
    required this.textura,
    required this.precio,
    required this.stock,
    required this.habilitado,
  });

  bool get disponible => habilitado;
  bool get sinStock => stock <= 0;

  factory VarianteProducto.fromJson(Map<String, dynamic> j) => VarianteProducto(
        codigo: (j['codigo'] ?? '').toString(),
        textura: (j['textura'] ?? '').toString(),
        precio: (j['precio'] as num?)?.toDouble() ?? 0,
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        habilitado: (j['habilitado'] ?? j['disponible']) == true,
      );
}

class CategoriaProducto {
  final String id;
  final String nombre;
  final int orden;

  const CategoriaProducto({required this.id, required this.nombre, required this.orden});

  factory CategoriaProducto.fromJson(Map<String, dynamic> j) => CategoriaProducto(
        id: (j['id'] ?? j['nombre'] ?? '').toString(),
        nombre: (j['nombre'] ?? j['id'] ?? '').toString(),
        orden: (j['orden'] as num?)?.toInt() ?? 0,
      );
}

class Producto {
  final String codigo;
  final String nombre;
  final String categoria;
  final String grupoSap;
  final double precio;
  final int stock;

  final bool habilitado;
  final String mensajeEstado;
  final String descripcion;
  final String? textura;
  final String? imagenUrl;
  final List<VarianteProducto> variantes;

  const Producto({
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.grupoSap,
    required this.precio,
    required this.stock,
    required this.habilitado,
    required this.mensajeEstado,
    required this.descripcion,
    required this.textura,
    required this.imagenUrl,
    required this.variantes,
  });

  factory Producto.fromJson(Map<String, dynamic> j, {required String baseUrl}) {
    final relativa = j['imagenUrl']?.toString();
    return Producto(
      codigo: (j['codigo'] ?? '').toString(),
      nombre: (j['nombre'] ?? '').toString(),
      categoria: (j['categoria'] ?? 'Otros').toString(),
      grupoSap: (j['grupoSap'] ?? '').toString(),
      precio: (j['precio'] as num?)?.toDouble() ?? 0,
      stock: (j['stock'] as num?)?.toInt() ?? 0,
      habilitado: (j['habilitado'] ?? j['disponible']) == true,
      mensajeEstado: (j['mensajeEstado'] ?? '').toString(),
      descripcion: (j['descripcion'] ?? '').toString(),
      textura: j['textura']?.toString(),
      imagenUrl: (relativa == null || relativa.isEmpty) ? null : '$baseUrl$relativa',
      variantes: ((j['variantes'] as List<dynamic>?) ?? [])
          .map((v) => VarianteProducto.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList(),
    );
  }

  bool get tieneVariantes => variantes.isNotEmpty;
  bool get disponible => habilitado;
  bool get sinStock => stock <= 0;

  Map<String, dynamic> toMapUi() {
    final m = <String, dynamic>{
      'title': nombre,
      'price': habilitado ? PriceUtils.formatPriceDisplay(precio) : 'Sin precio',
      'image': imagenUrl ?? '',
      'description': descripcion,
      'codigoSap': codigo,
      'category': categoria,
      'disponible': habilitado,
      'habilitado': habilitado,
      'sinStock': sinStock,
      'mensajeEstado': mensajeEstado,
      'hasTextureOptions': tieneVariantes,
    };
    if (textura != null && textura!.isNotEmpty) m['textura'] = textura;

    if (tieneVariantes) {
      if (categoria == 'Cepillos') {
        final suave = variantes.firstWhere(
          (v) => v.textura.toLowerCase() == 'suave',
          orElse: () => variantes.first,
        );
        m['codigoSapSuave'] = suave.codigo;
        m.putIfAbsent('textura', () => 'Media');
      } else {
        m['codigoSapAlternativo'] = variantes.first.codigo;
        m['texturaAlternativa'] = variantes.first.textura;
        m.putIfAbsent('textura', () => 'Original');
      }
    }
    return m;
  }
}

class Catalogo {
  final String version;
  final String fuente;
  final int listaPrecios;
  final DateTime? actualizado;
  final List<CategoriaProducto> categorias;
  final List<Producto> productos;

  const Catalogo({
    required this.version,
    required this.fuente,
    required this.listaPrecios,
    required this.actualizado,
    required this.categorias,
    required this.productos,
  });

  factory Catalogo.fromJson(Map<String, dynamic> j, {required String baseUrl}) => Catalogo(
        version: (j['version'] ?? '').toString(),
        fuente: (j['fuente'] ?? '').toString(),
        listaPrecios: (j['listaPrecios'] as num?)?.toInt() ?? 1,
        actualizado: DateTime.tryParse(j['actualizado']?.toString() ?? ''),
        categorias: ((j['categorias'] as List<dynamic>?) ?? [])
            .map((c) => CategoriaProducto.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList()
          ..sort((a, b) => a.orden.compareTo(b.orden)),
        productos: ((j['productos'] as List<dynamic>?) ?? [])
            .map((p) => Producto.fromJson(Map<String, dynamic>.from(p as Map), baseUrl: baseUrl))
            .where((p) => p.habilitado && p.precio > 0)
            .toList(),
      );

  Map<String, Map<String, dynamic>> get preciosPorCodigo {
    final m = <String, Map<String, dynamic>>{};
    for (final p in productos) {
      m[p.codigo] = {'precio': p.precio};
      for (final v in p.variantes) {
        m[v.codigo] = {'precio': v.precio};
      }
    }
    return m;
  }

  Map<String, Map<String, dynamic>> get estadosPorCodigo {
    Map<String, dynamic> estado(bool habilitado, int stock, String mensaje) => {
          'estado': habilitado ? 'DISPONIBLE' : 'NO_DISPONIBLE',
          'disponible': habilitado,
          'habilitado': habilitado,
          'stock': stock,
          'mensaje': mensaje,
        };
    String mensajeVariante(VarianteProducto v) {
      if (!v.habilitado) return 'No disponible para este cliente';
      return v.sinStock ? 'Sin stock en bodega' : 'Producto disponible';
    }
    final m = <String, Map<String, dynamic>>{};
    for (final p in productos) {
      m[p.codigo] = estado(p.habilitado, p.stock, p.mensajeEstado);
      for (final v in p.variantes) {
        m[v.codigo] = estado(v.habilitado, v.stock, mensajeVariante(v));
      }
    }
    return m;
  }
}
