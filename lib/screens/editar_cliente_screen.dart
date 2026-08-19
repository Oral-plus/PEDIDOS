import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';
import '../widgets/app_header.dart';
import 'ruta_detalle_screen.dart';

/// Pantalla para revisar y corregir los datos de contacto de un cliente
/// cuya información está desactualizada. Los cambios se guardan en nuestra
/// base (no en SAP). Devuelve por Navigator.pop la nueva fecha de
/// actualización (String ISO) si se guardó, o null si se canceló.
class EditarClienteScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final int? rutaId;
  final int? diasSinActualizar;

  const EditarClienteScreen({
    super.key,
    required this.cliente,
    this.rutaId,
    this.diasSinActualizar,
  });

  @override
  State<EditarClienteScreen> createState() => _EditarClienteScreenState();
}

class _EditarClienteScreenState extends State<EditarClienteScreen> {
  final ApiEasyService _api = ApiEasyService();

  final _nombre = TextEditingController();
  final _direccion = TextEditingController();
  final _telefono = TextEditingController();
  final _correo = TextEditingController();
  final _ciudad = TextEditingController();

  // Valores originales (para registrar el "antes" y detectar cambios).
  Map<String, String> _originales = {};

  bool _cargando = true;
  bool _guardando = false;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;
  static const Color _ink = Color(0xFF1F2937);

  String get _codigo => (widget.cliente['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    for (final c in [_nombre, _direccion, _telefono, _correo, _ciudad]) {
      c.addListener(() => setState(() {}));
    }
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _direccion.dispose();
    _telefono.dispose();
    _correo.dispose();
    _ciudad.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    // Prefill con lo que ya venga en el mapa cliente…
    _aplicar({
      'nombre': widget.cliente['nombre'],
      'direccion': widget.cliente['direccion'],
      'telefono': widget.cliente['telefono'],
      'correo': widget.cliente['correo'],
      'ciudad': widget.cliente['ciudad'],
    });
    // …y luego refresca con el detalle actual del servidor.
    final detalle = await _api.getClientePorCodigo(_codigo);
    if (!mounted) return;
    if (detalle != null) _aplicar(detalle);
    setState(() => _cargando = false);
  }

  void _aplicar(Map<String, dynamic> d) {
    String v(String k) => (d[k] ?? '').toString().trim();
    if (v('nombre').isNotEmpty) _nombre.text = v('nombre');
    if (v('direccion').isNotEmpty) _direccion.text = v('direccion');
    if (v('telefono').isNotEmpty) _telefono.text = v('telefono');
    if (v('correo').isNotEmpty) _correo.text = v('correo');
    if (v('ciudad').isNotEmpty) _ciudad.text = v('ciudad');
    _originales = {
      'nombre': _nombre.text,
      'direccion': _direccion.text,
      'telefono': _telefono.text,
      'correo': _correo.text,
      'ciudad': _ciudad.text,
    };
  }

  bool get _hayCambios =>
      _nombre.text.trim() != (_originales['nombre'] ?? '') ||
      _direccion.text.trim() != (_originales['direccion'] ?? '') ||
      _telefono.text.trim() != (_originales['telefono'] ?? '') ||
      _correo.text.trim() != (_originales['correo'] ?? '') ||
      _ciudad.text.trim() != (_originales['ciudad'] ?? '');

  String? get _errorCorreo {
    final c = _correo.text.trim();
    if (c.isEmpty) return null;
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(c);
    return ok ? null : 'Correo no válido';
  }

  bool get _puedeGuardar =>
      !_guardando && !_cargando && _hayCambios && _errorCorreo == null;

  Future<void> _guardar() async {
    if (!_puedeGuardar) return;
    FocusScope.of(context).unfocus();
    setState(() => _guardando = true);
    HapticFeedback.mediumImpact();

    final res = await _api.actualizarDatosCliente(
      _codigo,
      nombre: _nombre.text.trim(),
      direccion: _direccion.text.trim(),
      telefono: _telefono.text.trim(),
      correo: _correo.text.trim(),
      ciudad: _ciudad.text.trim(),
      rutaId: widget.rutaId,
      anteriores: _originales,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    if (res['success'] == true) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(res['fechaActualizacion'] ?? DateTime.now().toIso8601String());
    } else {
      final msg = (res['message'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isEmpty ? 'No se pudieron guardar los cambios' : msg),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dias = widget.diasSinActualizar;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: _textDark,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: const AppBarTitle('Actualizar datos', subtitle: 'Corrección en la visita'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _encabezadoCliente(dias),
                    const SizedBox(height: 18),
                    _campo(
                      label: 'Nombre / Razón social',
                      controller: _nombre,
                      icon: Icons.badge_rounded,
                      capitalize: true,
                    ),
                    _campo(
                      label: 'Dirección',
                      controller: _direccion,
                      icon: Icons.location_on_rounded,
                      capitalize: true,
                      maxLines: 2,
                    ),
                    _campo(
                      label: 'Teléfono',
                      controller: _telefono,
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    _campo(
                      label: 'Correo electrónico',
                      controller: _correo,
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _errorCorreo,
                    ),
                    _campo(
                      label: 'Ciudad',
                      controller: _ciudad,
                      icon: Icons.location_city_rounded,
                      capitalize: true,
                    ),
                  ],
                ),
              ),
              _footer(),
            ]),
    );
  }

  Widget _encabezadoCliente(int? dias) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((widget.cliente['nombre'] ?? 'Cliente').toString(),
              style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            _codigo + (dias != null ? '  ·  sin actualizar ${formatAntiguedadDias(dias)}' : ''),
            style: TextStyle(color: _textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ])),
      ]),
    );
  }

  Widget _campo({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool capitalize = false,
    int maxLines = 1,
    String? errorText,
  }) {
    final cambiado = controller.text.trim() != (_originales[_keyOf(controller)] ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: TextStyle(color: _textDark, fontSize: 12.5, fontWeight: FontWeight.w800)),
          if (cambiado) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: _ink.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text('editado', style: TextStyle(color: _ink, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          minLines: 1,
          textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
          style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _textMuted, size: 19),
            errorText: errorText,
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink, width: 1.5)),
          ),
        ),
      ]),
    );
  }

  String _keyOf(TextEditingController c) {
    if (c == _nombre) return 'nombre';
    if (c == _direccion) return 'direccion';
    if (c == _telefono) return 'telefono';
    if (c == _correo) return 'correo';
    return 'ciudad';
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _puedeGuardar ? _guardar : null,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _puedeGuardar ? const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]) : null,
                color: _puedeGuardar ? null : _border,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _guardando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.save_rounded, color: _puedeGuardar ? Colors.white : _textMuted, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _hayCambios ? 'Guardar cambios' : 'Sin cambios',
                          style: TextStyle(
                            color: _puedeGuardar ? Colors.white : _textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
