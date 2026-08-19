import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_easy_service.dart';
import '../login_screen.dart';

/// Plataforma de mantenimiento (Soporte TI): lista los dispositivos con la
/// persona asociada y permite activarlos o desactivarlos por su ID de servicio.
class MantenimientoScreen extends StatefulWidget {
  const MantenimientoScreen({super.key});

  @override
  State<MantenimientoScreen> createState() => _MantenimientoScreenState();
}

class _MantenimientoScreenState extends State<MantenimientoScreen> {
  static const Color _accent = Color(0xFF1A56DB);
  static const Color _bg = Color(0xFFF0F4F8);
  static const Color _textPrimary = Color(0xFF111827);

  final ApiEasyService _api = ApiEasyService();
  final _buscarController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _dispositivos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getDispositivos(buscar: _buscarController.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _dispositivos = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _error = res['message']?.toString() ?? 'Error al cargar';
        _dispositivos = [];
      }
    });
  }

  Future<void> _cambiarEstado(Map<String, dynamic> disp, String nuevo) async {
    final id = disp['id_servicio']?.toString() ?? '';
    final res = await _api.setDispositivoEstado(id, nuevo);
    if (!mounted) return;
    final ok = res['success'] == true;
    if (ok) {
      // Actualización optimista: refleja el estado al instante en la lista, sin
      // depender de una recarga completa (robusto ante caídas del túnel/red).
      setState(() {
        final i = _dispositivos
            .indexWhere((d) => d['id_servicio']?.toString() == id);
        if (i != -1) {
          _dispositivos[i]['estado'] = res['estado']?.toString() ?? nuevo;
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Dispositivo ${nuevo == 'ACTIVO' ? 'activado' : 'desactivado'}: $id'
          : (res['message']?.toString() ?? 'No se pudo actualizar')),
      backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
    ));
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final res = await _api.deleteDispositivo(id);
    if (!mounted) return;
    final ok = res['success'] == true;
    if (ok) {
      setState(() => _dispositivos
          .removeWhere((d) => d['id_servicio']?.toString() == id));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Dispositivo eliminado: $id'
          : (res['message']?.toString() ?? 'No se pudo eliminar')),
      backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
    ));
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
    // Volver al login limpiando toda la pila (mantenimiento es la ruta raíz
    // tras los pushReplacement de splash/login, por eso no basta con pop).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text('Mantenimiento · Dispositivos',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _cerrarSesion,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBuscador(),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildBuscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _buscarController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(),
              decoration: InputDecoration(
                hintText: 'Pega o escribe el ID de servicio…',
                prefixIcon: const Icon(Icons.search_rounded, color: _accent),
                filled: true,
                fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _cargar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error != null) {
      return _mensajeCentro(Icons.error_outline_rounded, _error!, const Color(0xFFDC2626));
    }
    if (_dispositivos.isEmpty) {
      return _mensajeCentro(
          Icons.devices_other_rounded, 'No hay dispositivos registrados', Colors.grey);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      color: _accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _dispositivos.length,
        itemBuilder: (_, i) => _buildCard(_dispositivos[i]),
      ),
    );
  }

  Widget _mensajeCentro(IconData icon, String texto, Color color) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color.withOpacity(0.6)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> d) {
    final estado = (d['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
    final id = d['id_servicio']?.toString() ?? '';
    final nombre = d['usuario_nombre']?.toString();
    final documento = d['usuario_documento']?.toString();
    final codigo = d['usuario_codigo']?.toString();
    final telefono = d['usuario_telefono']?.toString();
    final activo = estado == 'ACTIVO';

    final colorEstado = activo
        ? const Color(0xFF16A34A)
        : (estado == 'DESACTIVADO' ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ID + estado
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _copiar(id),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(id,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 15, color: _accent),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(estado,
                    style: TextStyle(
                        color: colorEstado,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const Divider(height: 20),
          // Persona asociada
          if (nombre != null && nombre.isNotEmpty) ...[
            _linea(Icons.person_outline_rounded, nombre),
            if (codigo != null && codigo.isNotEmpty)
              _linea(Icons.badge_outlined, 'Código: $codigo'),
            if (documento != null && documento.isNotEmpty)
              _linea(Icons.credit_card_outlined, 'Documento: $documento'),
            if (telefono != null && telefono.isNotEmpty)
              _linea(Icons.phone_outlined, telefono),
          ] else
            _linea(Icons.help_outline_rounded, 'Sin persona asociada aún'),
          const SizedBox(height: 14),
          // Acción activar/desactivar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: activo ? null : () => _cambiarEstado(d, 'ACTIVO'),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    side: BorderSide(
                        color: const Color(0xFF16A34A).withOpacity(activo ? 0.2 : 1)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                    foregroundColor: const Color(0xFFDC2626),
                    side: BorderSide(
                        color: const Color(0xFFDC2626).withOpacity(!activo ? 0.2 : 1)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  label: const Text('Desactivar'),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _eliminar(d),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              label: const Text('Eliminar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
