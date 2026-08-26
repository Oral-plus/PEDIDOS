import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/api_easy_service.dart';
import '../../services/catalogo_service.dart';
import '../../widgets/producto_imagen.dart';
import '../login_screen.dart';

/// Plataforma de mantenimiento (Soporte TI).
/// Dispositivos: lista los dispositivos con la persona asociada y permite
/// activarlos, desactivarlos o eliminarlos por su ID de servicio.
/// Usuarios: quiénes pueden entrar a la app (vendedores SAP y usuarios
/// registrados), si son soporte y qué dispositivos tienen.
/// Productos: el catálogo que viene de SAP; aquí se sube la foto de cada
/// referencia y se ajusta cómo se presenta en la app.
class MantenimientoScreen extends StatefulWidget {
  const MantenimientoScreen({super.key});

  @override
  State<MantenimientoScreen> createState() => _MantenimientoScreenState();
}

class _MantenimientoScreenState extends State<MantenimientoScreen>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF1A56DB);
  static const Color _bg = Color(0xFFF0F4F8);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _ambar = Color(0xFFD97706);

  final ApiEasyService _api = ApiEasyService();
  late final TabController _tabs;

  // Dispositivos
  final _buscarDispositivos = TextEditingController();
  bool _loadingDispositivos = true;
  String? _errorDispositivos;
  List<Map<String, dynamic>> _dispositivos = [];

  // Usuarios
  final _buscarUsuarios = TextEditingController();
  bool _loadingUsuarios = false;
  bool _usuariosCargados = false;
  String? _errorUsuarios;
  List<Map<String, dynamic>> _usuarios = [];
  List<String> _avisosUsuarios = [];

  // Productos
  final _buscarProductos = TextEditingController();
  bool _loadingProductos = false;
  bool _productosCargados = false;
  String? _errorProductos;
  List<Map<String, dynamic>> _productos = [];
  List<String> _categoriasProductos = [];
  String _fuenteCatalogo = '';
  bool _soloSinImagen = false;
  String? _codigoSubiendo;
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    // Cada pestaña se carga la primera vez que se abre
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_usuariosCargados && !_loadingUsuarios) _cargarUsuarios();
      if (_tabs.index == 2 && !_productosCargados && !_loadingProductos) _cargarProductos();
    });
    _buscarProductos.addListener(() => setState(() {}));
    _cargarDispositivos();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscarDispositivos.dispose();
    _buscarUsuarios.dispose();
    _buscarProductos.dispose();
    super.dispose();
  }

  bool _sesionExpirada(Map<String, dynamic> res) =>
      (res['message']?.toString().toLowerCase() ?? '').contains('expirada');

  // Dispositivos

  Future<void> _cargarDispositivos() async {
    setState(() {
      _loadingDispositivos = true;
      _errorDispositivos = null;
    });
    final res = await _api.getDispositivos(buscar: _buscarDispositivos.text);
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    setState(() {
      _loadingDispositivos = false;
      if (res['success'] == true) {
        _dispositivos = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _errorDispositivos = res['message']?.toString() ?? 'Error al cargar';
        _dispositivos = [];
      }
    });
  }

  Future<void> _cambiarEstado(Map<String, dynamic> disp, String nuevo) async {
    final id = disp['id_servicio']?.toString() ?? '';
    final res = await _api.setDispositivoEstado(id, nuevo);
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    final ok = res['success'] == true;
    if (ok) {
      // Actualización optimista: refleja el estado al instante en la lista, sin
      // depender de una recarga completa (robusto ante caídas del túnel/red).
      setState(() {
        final i = _dispositivos.indexWhere((d) => d['id_servicio']?.toString() == id);
        if (i != -1) {
          _dispositivos[i]['estado'] = res['estado']?.toString() ?? nuevo;
          if (nuevo == 'ACTIVO') {
            _dispositivos[i]['activado_por'] = _api.usuario?['nombre']?.toString();
            _dispositivos[i]['fecha_activacion'] = DateTime.now().toIso8601String();
          }
        }
      });
      // Los conteos de la pestaña de usuarios cambian
      _usuariosCargados = false;
    }
    _snack(
      ok
          ? 'Dispositivo ${nuevo == 'ACTIVO' ? 'activado' : 'desactivado'}: $id'
          : (res['message']?.toString() ?? 'No se pudo actualizar'),
      ok,
    );
  }

  Future<void> _eliminar(Map<String, dynamic> disp) async {
    final id = disp['id_servicio']?.toString() ?? '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar dispositivo'),
        content: Text(
            '¿Eliminar el dispositivo $id del registro?\n\nSi el vendedor vuelve a abrir la app, se registrará de nuevo como pendiente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _rojo, foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final res = await _api.deleteDispositivo(id);
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    final ok = res['success'] == true;
    if (ok) {
      setState(() => _dispositivos.removeWhere((d) => d['id_servicio']?.toString() == id));
      _usuariosCargados = false;
    }
    _snack(ok ? 'Dispositivo eliminado: $id' : (res['message']?.toString() ?? 'No se pudo eliminar'), ok);
  }

  // Usuarios

  Future<void> _cargarUsuarios() async {
    setState(() {
      _loadingUsuarios = true;
      _errorUsuarios = null;
    });
    final res = await _api.getUsuarios(buscar: _buscarUsuarios.text);
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    setState(() {
      _loadingUsuarios = false;
      _usuariosCargados = true;
      if (res['success'] == true) {
        _usuarios = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _avisosUsuarios = (res['avisos'] as List<String>?) ?? [];
      } else {
        _errorUsuarios = res['message']?.toString() ?? 'Error al cargar';
        _usuarios = [];
      }
    });
  }

  /// Desde un usuario: ver sus dispositivos en la otra pestaña
  void _verDispositivosDe(Map<String, dynamic> u) {
    _buscarDispositivos.text = (u['nombre'] ?? '').toString();
    _tabs.animateTo(0);
    _cargarDispositivos();
  }

  // Productos

  Future<void> _cargarProductos() async {
    setState(() {
      _loadingProductos = true;
      _errorProductos = null;
    });
    _baseUrl = await _api.baseUrl();
    final res = await _api.getProductosAdmin();
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    setState(() {
      _loadingProductos = false;
      _productosCargados = true;
      if (res['success'] == true) {
        _productos = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _categoriasProductos = (res['categorias'] as List<String>?) ?? [];
        _fuenteCatalogo = (res['fuente'] ?? '').toString();
      } else {
        _errorProductos = res['message']?.toString() ?? 'Error al cargar';
        _productos = [];
      }
    });
  }

  List<Map<String, dynamic>> get _productosFiltrados {
    final q = _buscarProductos.text.trim().toLowerCase();
    return _productos.where((p) {
      if (_soloSinImagen && (p['imagenUrl'] ?? '').toString().isNotEmpty) return false;
      if (q.isEmpty) return true;
      return [p['nombre'], p['codigo'], p['categoria'], p['grupoSap']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
  }

  String _urlImagen(Map<String, dynamic> p) {
    final rel = (p['imagenUrl'] ?? '').toString();
    return rel.isEmpty ? '' : '$_baseUrl$rel';
  }

  Future<void> _subirFoto(Map<String, dynamic> p) async {
    final codigo = (p['codigo'] ?? '').toString();
    final fuente = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Text('Foto para ${p['nombre']}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: _textPrimary)),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: _accent),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: _accent),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (fuente == null) return;
    XFile? archivo;
    try {
      archivo = await ImagePicker().pickImage(source: fuente, maxWidth: 1200, maxHeight: 1200, imageQuality: 90);
    } catch (_) {
      if (mounted) _snack('No se pudo abrir ${fuente == ImageSource.camera ? 'la cámara' : 'la galería'}', false);
      return;
    }
    if (archivo == null || !mounted) return;

    setState(() => _codigoSubiendo = codigo);
    final res = await _api.subirImagenProducto(codigo, archivo.path);
    if (!mounted) return;
    setState(() => _codigoSubiendo = null);
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    final ok = res['success'] == true;
    if (ok) {
      setState(() => p['imagenUrl'] = res['imagenUrl']);
      CatalogoService().invalidar();
    }
    _snack(ok ? 'Foto guardada para $codigo' : (res['message']?.toString() ?? 'No se pudo subir la foto'), ok);
  }

  Future<void> _quitarFoto(Map<String, dynamic> p) async {
    final codigo = (p['codigo'] ?? '').toString();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Quitar foto'),
        content: Text('¿Quitar la foto de ${p['nombre']} ($codigo)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _rojo, foregroundColor: Colors.white),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final res = await _api.eliminarImagenProducto(codigo);
    if (!mounted) return;
    final ok = res['success'] == true;
    if (ok) {
      setState(() => p['imagenUrl'] = null);
      CatalogoService().invalidar();
    }
    _snack(ok ? 'Foto retirada de $codigo' : (res['message']?.toString() ?? 'No se pudo quitar'), ok);
  }

  Future<void> _editarProducto(Map<String, dynamic> p) async {
    final codigo = (p['codigo'] ?? '').toString();
    final cambios = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditarProductoDialog(
        producto: p,
        categorias: _categoriasProductos,
      ),
    );
    if (cambios == null || cambios.isEmpty) return;
    final res = await _api.guardarConfigProducto(codigo, cambios);
    if (!mounted) return;
    if (res['success'] != true && _sesionExpirada(res)) return _volverAlLogin();
    final ok = res['success'] == true;
    if (ok) {
      setState(() {
        if (cambios.containsKey('categoriaApp')) {
          p['categoriaApp'] = cambios['categoriaApp'];
          p['categoria'] = (cambios['categoriaApp'] ?? '').toString().isEmpty
              ? p['categoria']
              : cambios['categoriaApp'];
        }
        if (cambios.containsKey('visible')) p['visible'] = cambios['visible'];
        if (cambios.containsKey('varianteDe')) p['varianteDe'] = cambios['varianteDe'];
        if (cambios.containsKey('textura')) p['textura'] = cambios['textura'];
        if (cambios.containsKey('descripcion')) p['descripcion'] = cambios['descripcion'] ?? '';
      });
      CatalogoService().invalidar();
    }
    _snack(ok ? 'Producto $codigo actualizado' : (res['message']?.toString() ?? 'No se pudo guardar'), ok);
  }

  Future<void> _refrescarSap() async {
    _snack('Leyendo SAP...', true);
    final res = await _api.refrescarCatalogo();
    if (!mounted) return;
    if (res['success'] == true) {
      CatalogoService().invalidar();
      await _cargarProductos();
      if (mounted) _snack('Catálogo actualizado: ${res['articulos']} artículos (${res['fuente']})', true);
    } else {
      _snack(res['message']?.toString() ?? 'No se pudo refrescar', false);
    }
  }

  // Comunes

  void _snack(String texto, bool ok) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), backgroundColor: ok ? _verde : _rojo));
  }

  void _copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('ID copiado al portapapeles'),
      duration: Duration(seconds: 1),
    ));
  }

  Future<void> _cerrarSesion() async {
    await _api.clearSession();
    if (!mounted) return;
    _volverAlLogin();
  }

  void _volverAlLogin() {
    // Mantenimiento es la ruta raíz tras los pushReplacement de splash/login,
    // por eso se limpia toda la pila.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  static final DateFormat _fmtFecha = DateFormat('dd/MM/yyyy HH:mm');

  String _fecha(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (d == null) return s;
    return _fmtFecha.format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Mantenimiento', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _cerrarSesion,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: _accent,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: _accent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          tabs: const [
            Tab(icon: Icon(Icons.devices_rounded, size: 20), text: 'Dispositivos'),
            Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'Usuarios'),
            Tab(icon: Icon(Icons.inventory_2_rounded, size: 20), text: 'Productos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          Column(children: [
            _buscador(_buscarDispositivos, 'Pega o escribe el ID de servicio o el nombre', _cargarDispositivos),
            Expanded(child: _listaDispositivos()),
          ]),
          Column(children: [
            _buscador(_buscarUsuarios, 'Nombre, código SKV o documento', _cargarUsuarios),
            Expanded(child: _listaUsuarios()),
          ]),
          Column(children: [
            _buscador(_buscarProductos, 'Nombre, código o categoría', () => setState(() {})),
            _filtrosProductos(),
            Expanded(child: _listaProductos()),
          ]),
        ],
      ),
    );
  }

  Widget _buscador(TextEditingController controller, String hint, VoidCallback onBuscar) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onBuscar(),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded, color: _accent),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onBuscar();
                      },
                    ),
              filled: true,
              fillColor: _bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: onBuscar,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ]),
    );
  }

  Widget _mensajeCentro(IconData icon, String texto, Color color) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: color.withOpacity(0.6)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(texto, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 14)),
        ),
      ]),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _linea(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
      ]),
    );
  }

  // Dispositivos: lista

  Widget _listaDispositivos() {
    if (_loadingDispositivos) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_errorDispositivos != null) {
      return _mensajeCentro(Icons.error_outline_rounded, _errorDispositivos!, _rojo);
    }
    if (_dispositivos.isEmpty) {
      return _mensajeCentro(Icons.devices_other_rounded, 'No hay dispositivos registrados', Colors.grey);
    }
    return RefreshIndicator(
      onRefresh: _cargarDispositivos,
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _dispositivos.length,
        itemBuilder: (_, i) => _cardDispositivo(_dispositivos[i]),
      ),
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'ACTIVO':
        return _verde;
      case 'DESACTIVADO':
        return _rojo;
      default:
        return _ambar;
    }
  }

  Widget _cardDispositivo(Map<String, dynamic> d) {
    final estado = (d['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
    final id = d['id_servicio']?.toString() ?? '';
    final nombre = d['usuario_nombre']?.toString();
    final documento = d['usuario_documento']?.toString();
    final codigo = d['usuario_codigo']?.toString();
    final telefono = d['usuario_telefono']?.toString();
    final plataforma = d['plataforma']?.toString() ?? '';
    final ultimoAcceso = _fecha(d['fecha_ultimo_acceso']);
    final activadoPor = d['activado_por']?.toString() ?? '';
    final fechaActivacion = _fecha(d['fecha_activacion']);
    final activo = estado == 'ACTIVO';
    final colorEstado = _colorEstado(estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _copiar(id),
              child: Row(children: [
                Flexible(
                  child: Text(id,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: _textPrimary, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 15, color: _accent),
              ]),
            ),
          ),
          _chip(estado, colorEstado),
        ]),
        const Divider(height: 20),
        if (nombre != null && nombre.isNotEmpty) ...[
          _linea(Icons.person_outline_rounded, nombre),
          if (codigo != null && codigo.isNotEmpty) _linea(Icons.badge_outlined, 'Código: $codigo'),
          if (documento != null && documento.isNotEmpty) _linea(Icons.credit_card_outlined, 'Documento: $documento'),
          if (telefono != null && telefono.isNotEmpty) _linea(Icons.phone_outlined, telefono),
        ] else
          _linea(Icons.help_outline_rounded, 'Sin persona asociada aún'),
        if (plataforma.isNotEmpty || ultimoAcceso.isNotEmpty)
          _linea(
            Icons.phone_android_rounded,
            [if (plataforma.isNotEmpty) plataforma, if (ultimoAcceso.isNotEmpty) 'último acceso $ultimoAcceso']
                .join(' · '),
          ),
        if (activo && (activadoPor.isNotEmpty || fechaActivacion.isNotEmpty))
          _linea(
            Icons.verified_user_outlined,
            'Activado${activadoPor.isNotEmpty ? ' por $activadoPor' : ''}${fechaActivacion.isNotEmpty ? ' el $fechaActivacion' : ''}',
          ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: activo ? null : () => _cambiarEstado(d, 'ACTIVO'),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: _verde,
                side: BorderSide(color: _verde.withOpacity(activo ? 0.2 : 1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              label: const Text('Activar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: !activo ? null : () => _cambiarEstado(d, 'DESACTIVADO'),
              icon: const Icon(Icons.block_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: _rojo,
                side: BorderSide(color: _rojo.withOpacity(!activo ? 0.2 : 1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              label: const Text('Desactivar'),
            ),
          ),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _eliminar(d),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
            label: const Text('Eliminar'),
          ),
        ),
      ]),
    );
  }

  // Usuarios: lista

  Widget _listaUsuarios() {
    if (_loadingUsuarios || (!_usuariosCargados && _errorUsuarios == null)) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_errorUsuarios != null) {
      return _mensajeCentro(Icons.error_outline_rounded, _errorUsuarios!, _rojo);
    }
    if (_usuarios.isEmpty) {
      return _mensajeCentro(Icons.person_off_rounded, 'No hay usuarios para mostrar', Colors.grey);
    }
    final soporte = _usuarios.where((u) => u['esSoporte'] == true).length;
    final conDispositivo = _usuarios.where((u) => ((u['dispositivos'] as List?)?.isNotEmpty ?? false)).length;
    return RefreshIndicator(
      onRefresh: _cargarUsuarios,
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _usuarios.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _resumenUsuarios(soporte, conDispositivo);
          return _cardUsuario(_usuarios[i - 1]);
        },
      ),
    );
  }

  Widget _resumenUsuarios(int soporte, int conDispositivo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${_usuarios.length} usuarios · $soporte de soporte · $conDispositivo con dispositivo',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        for (final aviso in _avisosUsuarios)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(aviso, style: const TextStyle(color: _ambar, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _cardUsuario(Map<String, dynamic> u) {
    final nombre = (u['nombre'] ?? '').toString();
    final codigo = (u['codigo'] ?? '').toString();
    final tipo = (u['tipo'] ?? '').toString();
    final esVendedor = tipo == 'vendedor';
    final activo = u['activo'] != false;
    final esSoporte = u['esSoporte'] == true;
    final telefono = (u['telefono'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final dispositivos = (u['dispositivos'] as List<dynamic>?) ?? [];
    final activos = (u['dispositivosActivos'] as num?)?.toInt() ?? 0;

    final String textoDisp;
    final Color colorDisp;
    if (dispositivos.isEmpty) {
      textoDisp = 'Sin dispositivo';
      colorDisp = Colors.grey.shade600;
    } else if (activos > 0) {
      textoDisp = '${dispositivos.length} dispositivo(s), $activos activo(s)';
      colorDisp = _verde;
    } else {
      textoDisp = '${dispositivos.length} dispositivo(s), ninguno activo';
      colorDisp = _ambar;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (esSoporte ? _accent : (esVendedor ? _verde : _ambar)).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              esSoporte ? Icons.admin_panel_settings_rounded : (esVendedor ? Icons.storefront_rounded : Icons.person_rounded),
              color: esSoporte ? _accent : (esVendedor ? _verde : _ambar),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre.isEmpty ? codigo : nombre,
                  style: const TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '$codigo · ${esVendedor ? 'Vendedor SAP' : 'Usuario registrado'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (esSoporte) _chip('SOPORTE TI', _accent),
          if (!activo) _chip('INACTIVO', _rojo),
          _chip(textoDisp, colorDisp),
        ]),
        if (telefono.isNotEmpty || email.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (telefono.isNotEmpty) _linea(Icons.phone_outlined, telefono),
          if (email.isNotEmpty) _linea(Icons.mail_outline_rounded, email),
        ],
        if (dispositivos.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final raw in dispositivos)
            _linea(
              Icons.phone_android_rounded,
              _descripcionDispositivo(Map<String, dynamic>.from(raw as Map)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _verDispositivosDe(u),
              icon: const Icon(Icons.devices_rounded, size: 16),
              label: const Text('Ver dispositivos'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
        ],
      ]),
    );
  }

  String _descripcionDispositivo(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString();
    final id = (d['idServicio'] ?? '').toString();
    final acceso = _fecha(d['ultimoAcceso']);
    return '$id · $estado${acceso.isNotEmpty ? ' · $acceso' : ''}';
  }

  // Productos: lista

  Widget _filtrosProductos() {
    final sinImagen = _productos.where((p) => (p['imagenUrl'] ?? '').toString().isEmpty).length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(children: [
        FilterChip(
          label: Text('Sin foto ($sinImagen)'),
          selected: _soloSinImagen,
          onSelected: (v) => setState(() => _soloSinImagen = v),
          selectedColor: _ambar.withOpacity(0.15),
          checkmarkColor: _ambar,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _soloSinImagen ? _ambar : Colors.grey.shade700),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        const Spacer(),
        if (_fuenteCatalogo.isNotEmpty)
          Text('SAP vía $_fuenteCatalogo', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        IconButton(
          tooltip: 'Volver a leer SAP',
          onPressed: _loadingProductos ? null : _refrescarSap,
          icon: const Icon(Icons.sync_rounded, color: _accent, size: 20),
        ),
      ]),
    );
  }

  Widget _listaProductos() {
    if (_loadingProductos || (!_productosCargados && _errorProductos == null)) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_errorProductos != null) {
      return _mensajeCentro(Icons.error_outline_rounded, _errorProductos!, _rojo);
    }
    final lista = _productosFiltrados;
    if (lista.isEmpty) {
      return _mensajeCentro(Icons.inventory_2_outlined, 'No hay productos para mostrar', Colors.grey);
    }
    return RefreshIndicator(
      onRefresh: _cargarProductos,
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lista.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${lista.length} de ${_productos.length} artículos',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            );
          }
          return _cardProducto(lista[i - 1]);
        },
      ),
    );
  }

  Widget _cardProducto(Map<String, dynamic> p) {
    final codigo = (p['codigo'] ?? '').toString();
    final nombre = (p['nombre'] ?? '').toString();
    final categoria = (p['categoria'] ?? '').toString();
    final grupo = (p['grupoSap'] ?? '').toString();
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final visible = p['visible'] != false;
    final varianteDe = (p['varianteDe'] ?? '').toString();
    final textura = (p['textura'] ?? '').toString();
    final descripcion = (p['descripcion'] ?? '').toString();
    final url = _urlImagen(p);
    final subiendo = _codigoSubiendo == codigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: subiendo ? null : () => _subirFoto(p),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: url.isEmpty ? _ambar.withOpacity(0.6) : Colors.grey.shade200),
              ),
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(4),
              child: subiendo
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : ProductoImagen(url: url, cacheWidth: 200, icon: Icons.add_a_photo_outlined, iconColor: _ambar, iconSize: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => _copiar(codigo),
                child: Text('$codigo · $grupo',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(categoria, _accent),
                _chip(stock > 0 ? 'Stock $stock' : 'Sin stock', stock > 0 ? _verde : Colors.grey.shade600),
                if (!visible) _chip('OCULTO', _rojo),
                if (varianteDe.isNotEmpty) _chip('Variante ${textura.isNotEmpty ? textura : ''} de $varianteDe'.trim(), _ambar),
                if (url.isEmpty) _chip('SIN FOTO', _ambar),
              ]),
            ]),
          ),
        ]),
        if (descripcion.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(descripcion, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            onPressed: subiendo ? null : () => _subirFoto(p),
            icon: const Icon(Icons.photo_camera_rounded, size: 16),
            label: Text(url.isEmpty ? 'Subir foto' : 'Cambiar foto'),
            style: TextButton.styleFrom(foregroundColor: _accent),
          ),
          if (url.isNotEmpty)
            TextButton.icon(
              onPressed: subiendo ? null : () => _quitarFoto(p),
              icon: const Icon(Icons.hide_image_outlined, size: 16),
              label: const Text('Quitar'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
            ),
          TextButton.icon(
            onPressed: () => _editarProducto(p),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Editar'),
            style: TextButton.styleFrom(foregroundColor: _textPrimary),
          ),
        ]),
      ]),
    );
  }
}

/// Diálogo de presentación de un producto: categoría en la app, visibilidad,
/// variante (de qué producto cuelga y con qué textura) y descripción.
/// Devuelve solo lo que cambió.
class _EditarProductoDialog extends StatefulWidget {
  final Map<String, dynamic> producto;
  final List<String> categorias;

  const _EditarProductoDialog({required this.producto, required this.categorias});

  @override
  State<_EditarProductoDialog> createState() => _EditarProductoDialogState();
}

class _EditarProductoDialogState extends State<_EditarProductoDialog> {
  static const String _segunSap = '';
  late String _categoria;
  late bool _visible;
  late final TextEditingController _varianteDe;
  late final TextEditingController _textura;
  late final TextEditingController _descripcion;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _categoria = (p['categoriaApp'] ?? _segunSap).toString();
    _visible = p['visible'] != false;
    _varianteDe = TextEditingController(text: (p['varianteDe'] ?? '').toString());
    _textura = TextEditingController(text: (p['textura'] ?? '').toString());
    _descripcion = TextEditingController(text: (p['descripcion'] ?? '').toString());
  }

  @override
  void dispose() {
    _varianteDe.dispose();
    _textura.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  void _guardar() {
    final p = widget.producto;
    final cambios = <String, dynamic>{};
    if (_categoria != (p['categoriaApp'] ?? '').toString()) cambios['categoriaApp'] = _categoria.isEmpty ? null : _categoria;
    if (_visible != (p['visible'] != false)) cambios['visible'] = _visible;
    final variante = _varianteDe.text.trim();
    if (variante != (p['varianteDe'] ?? '').toString()) cambios['varianteDe'] = variante.isEmpty ? null : variante;
    final textura = _textura.text.trim();
    if (textura != (p['textura'] ?? '').toString()) cambios['textura'] = textura.isEmpty ? null : textura;
    final descripcion = _descripcion.text.trim();
    if (descripcion != (p['descripcion'] ?? '').toString()) cambios['descripcion'] = descripcion.isEmpty ? null : descripcion;
    Navigator.pop(context, cambios);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final opciones = <String>{...widget.categorias, if (_categoria.isNotEmpty) _categoria}.toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(p['nombre']?.toString() ?? 'Producto', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['codigo']} · grupo SAP: ${p['grupoSap']}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoría en la app', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: _segunSap, child: Text('Según el grupo de SAP')),
              for (final c in opciones) DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _categoria = v ?? _segunSap),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible en el catálogo', style: TextStyle(fontSize: 14)),
            value: _visible,
            onChanged: (v) => setState(() => _visible = v),
          ),
          TextField(
            controller: _varianteDe,
            decoration: const InputDecoration(
              labelText: 'Variante de (código del producto principal)',
              helperText: 'Déjalo vacío si este producto se muestra como tarjeta propia',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textura,
            decoration: const InputDecoration(labelText: 'Textura (Media, Suave, Niño...)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descripcion,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Descripción',
              helperText: (p['descripcionSap'] ?? '').toString().isNotEmpty ? 'SAP trae una descripción; aquí se puede ajustar' : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
