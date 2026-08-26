import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_easy_service.dart';
import '../utils/theme.dart';

/// Hoja modal profesional para agregar una RUTA EXTRA (visita de urgencia).
/// El vendedor debe: 1) elegir el cliente, 2) indicar el motivo (por qué
/// visita) y 3) escribir una observación. Devuelve `true` si se creó.
Future<bool> showRutaExtraSheet(BuildContext context) async {
  final creado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (_) => const _RutaExtraSheet(),
  );
  return creado ?? false;
}

// Rojo de urgencia (el resto de la app es monocromática; el rojo se reserva
// exclusivamente para esta acción de excepción).
const Color _red = Color(0xFFDC2626);
const Color _redDark = Color(0xFFB91C1C);

/// Motivos frecuentes de una visita adicional (todos >= 5 caracteres, que es
/// lo que valida el backend).
const List<String> _motivos = [
  'Urgencia del cliente',
  'Recaudo de cartera vencida',
  'Pedido adicional',
  'Reclamo / PQR',
  'Reposición de producto',
  'Cliente nuevo / reactivación',
  'Otro motivo',
];

class _RutaExtraSheet extends StatefulWidget {
  const _RutaExtraSheet();

  @override
  State<_RutaExtraSheet> createState() => _RutaExtraSheetState();
}

class _RutaExtraSheetState extends State<_RutaExtraSheet> {
  final ApiEasyService _api = ApiEasyService();
  final TextEditingController _buscar = TextEditingController();
  final TextEditingController _obs = TextEditingController();

  List<Map<String, dynamic>> _clientes = [];
  bool _cargandoClientes = true;
  bool _enviando = false;

  Map<String, dynamic>? _clienteSel;
  String? _motivoSel;

  static Color get _bg => AppTheme.backgroundColor;
  static Color get _border => AppTheme.borderColor;
  static Color get _textDark => AppTheme.darkBlue;
  static Color get _textMuted => AppTheme.textSecondary;

  @override
  void initState() {
    super.initState();
    _buscar.addListener(_programarFiltro);
    _cargarClientes();
  }

  // La lista filtrada se recalcula al escribir (con una pausa corta), no en
  // cada rebuild ni por cada fila.
  List<Map<String, dynamic>> _clientesFiltrados = [];
  Timer? _debounce;

  void _programarFiltro() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _clientesFiltrados = _calcularFiltrados());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscar.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    final res = await _api.getClientes();
    if (!mounted) return;
    setState(() {
      _cargandoClientes = false;
      if (res['success'] == true) {
        _clientes = (res['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      _clientesFiltrados = _calcularFiltrados();
    });
  }

  List<Map<String, dynamic>> _calcularFiltrados() {
    final q = _buscar.text.trim().toLowerCase();
    if (q.isEmpty) return _clientes;
    return _clientes.where((c) {
      final nombre = (c['nombre'] ?? '').toString().toLowerCase();
      final id = (c['id'] ?? '').toString().toLowerCase();
      return nombre.contains(q) || id.contains(q);
    }).toList();
  }

  bool get _valido =>
      _clienteSel != null &&
      _motivoSel != null &&
      _obs.text.trim().length >= 5 &&
      !_enviando;

  Future<void> _enviar() async {
    if (!_valido) return;
    setState(() => _enviando = true);
    HapticFeedback.mediumImpact();

    final res = await _api.crearRutaExtra(
      clienteId: (_clienteSel!['id'] ?? '').toString(),
      clienteNombre: (_clienteSel!['nombre'] ?? '').toString(),
      ciudad: (_clienteSel!['ciudad'] ?? '').toString(),
      motivo: _motivoSel!,
      observacion: _obs.text.trim(),
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (res['success'] == true) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(true);
    } else {
      final msg = (res['message'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isEmpty ? 'No se pudo crear la ruta extra' : msg),
          backgroundColor: _redDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
                    children: [
                      _label('1', 'Cliente a visitar'),
                      const SizedBox(height: 8),
                      _selectorCliente(),
                      const SizedBox(height: 20),
                      _label('2', '¿Por qué vas a visitarlo?'),
                      const SizedBox(height: 8),
                      _motivosWrap(),
                      const SizedBox(height: 20),
                      _label('3', 'Observación (obligatoria)'),
                      const SizedBox(height: 8),
                      _campoObservacion(),
                    ],
                  ),
                ),
                _footer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_red, _redDark]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: _red.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.add_road_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ruta Extra',
                style: TextStyle(color: _textDark, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            const SizedBox(height: 1),
            Text('Visita adicional de urgencia',
                style: TextStyle(color: _red, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(false),
          icon: Icon(Icons.close_rounded, color: _textMuted),
        ),
      ]),
    );
  }

  Widget _label(String n, String text) {
    return Row(children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: _textDark, borderRadius: BorderRadius.circular(6)),
        child: Center(
          child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
        ),
      ),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: _textDark, fontSize: 13.5, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _selectorCliente() {
    if (_clienteSel != null) {
      final c = _clienteSel!;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withOpacity(0.4)),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: _red.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.storefront_rounded, color: _red, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((c['nombre'] ?? '').toString(),
                style: TextStyle(color: _textDark, fontSize: 13, fontWeight: FontWeight.w800),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${c['id']}${(c['ciudad'] ?? '').toString().isNotEmpty ? ' · ${c['ciudad']}' : ''}',
                style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          ])),
          TextButton(
            onPressed: () => setState(() => _clienteSel = null),
            child: const Text('Cambiar', style: TextStyle(color: _red, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
      );
    }

    return Column(children: [
      TextField(
        controller: _buscar,
        style: TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Buscar cliente por nombre o código…',
          hintStyle: TextStyle(color: _textMuted, fontSize: 13.5),
          prefixIcon: Icon(Icons.search_rounded, color: _textMuted, size: 20),
          filled: true,
          fillColor: _bg,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _red, width: 1.4)),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _cargandoClientes
            ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
            : (_clientesFiltrados.isEmpty
                ? Center(child: Text('Sin resultados', style: TextStyle(color: _textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _clientesFiltrados.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: _border.withOpacity(0.6)),
                    itemBuilder: (_, i) {
                      final c = _clientesFiltrados[i];
                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          FocusScope.of(context).unfocus();
                          setState(() => _clienteSel = c);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((c['nombre'] ?? '').toString(),
                                  style: TextStyle(color: _textDark, fontSize: 12.5, fontWeight: FontWeight.w700),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('${c['id']}${(c['ciudad'] ?? '').toString().isNotEmpty ? ' · ${c['ciudad']}' : ''}',
                                  style: TextStyle(color: _textMuted, fontSize: 10.5, fontWeight: FontWeight.w600)),
                            ])),
                            Icon(Icons.chevron_right_rounded, color: _textMuted, size: 18),
                          ]),
                        ),
                      );
                    },
                  )),
      ),
    ]);
  }

  Widget _motivosWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _motivos.map((m) {
        final sel = _motivoSel == m;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _motivoSel = m);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? _red : _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? _red : _border),
            ),
            child: Text(m,
                style: TextStyle(
                  color: sel ? Colors.white : _textDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _campoObservacion() {
    return TextField(
      controller: _obs,
      maxLines: 3,
      minLines: 3,
      maxLength: 500,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: _textDark, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Describe el motivo específico de esta visita de urgencia…',
        hintStyle: TextStyle(color: _textMuted, fontSize: 13),
        filled: true,
        fillColor: _bg,
        contentPadding: const EdgeInsets.all(14),
        counterStyle: TextStyle(color: _textMuted, fontSize: 10.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _red, width: 1.4)),
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.of(context).padding.bottom),
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
            onTap: _valido ? _enviar : null,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _valido ? const LinearGradient(colors: [_red, _redDark]) : null,
                color: _valido ? null : _border,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _enviando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_road_rounded, color: _valido ? Colors.white : _textMuted, size: 20),
                        const SizedBox(width: 8),
                        Text('Agregar ruta extra',
                            style: TextStyle(
                              color: _valido ? Colors.white : _textMuted,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            )),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
