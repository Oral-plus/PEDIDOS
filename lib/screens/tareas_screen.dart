import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tarea.dart';
import '../services/api_easy_service.dart';
import '../widgets/responder_tarea.dart';
import '../widgets/tarea_card.dart';

class TareasScreen extends StatefulWidget {
  const TareasScreen({super.key});

  @override
  State<TareasScreen> createState() => _TareasScreenState();
}

class _TareasScreenState extends State<TareasScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _inkDeep = Color(0xFF0B1220);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF3F4F6);
  static const Color _rojo = Color(0xFFDC2626);
  static const Color _ambar = Color(0xFFD97706);
  static const Color _verde = Color(0xFF16A34A);

  final ApiEasyService _api = ApiEasyService();
  bool _cargando = true;
  String? _error;
  List<Tarea> _tareas = [];
  ResumenTareas _resumen = const ResumenTareas();
  bool _soloPendientes = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _api.getTareas(forzar: forzar);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _tareas = res.tareas;
      _resumen = res.resumen;
      _error = res.exito ? null : 'No se pudieron cargar las tareas';
    });
  }

  List<Tarea> get _visibles => _soloPendientes ? _tareas.where((t) => t.pendiente).toList() : _tareas;

  Future<void> _responder(Tarea tarea) async {
    final respuesta = await ResponderTarea.mostrar(context, api: _api, tarea: tarea);
    if (respuesta != null) await _cargar(forzar: true);
  }

  @override
  Widget build(BuildContext context) {
    final vencidas = _resumen.vencidas;
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
        title: const Text('Tareas',
            style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded, color: _ink),
            onPressed: _cargando ? null : () => _cargar(forzar: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _cargar(forzar: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Row(children: [
              Expanded(child: _stat('Pendientes', '${_resumen.pendientes}', _inkDeep)),
              const SizedBox(width: 8),
              Expanded(child: _stat('Vencidas', '$vencidas', vencidas > 0 ? _rojo : _gray)),
              const SizedBox(width: 8),
              Expanded(child: _stat('Por vencer', '${_resumen.porVencer}', _ambar)),
              const SizedBox(width: 8),
              Expanded(child: _stat('Terminadas', '${_resumen.terminadas}', _verde)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _filtro('Pendientes', _soloPendientes, () => setState(() => _soloPendientes = true)),
              const SizedBox(width: 8),
              _filtro('Todas', !_soloPendientes, () => setState(() => _soloPendientes = false)),
            ]),
            const SizedBox(height: 12),
            if (_cargando)
              const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _mensaje(Icons.cloud_off_rounded, _error!)
            else if (_visibles.isEmpty)
              _mensaje(Icons.task_alt_rounded,
                  _soloPendientes ? 'No tienes tareas pendientes' : 'No tienes tareas asignadas')
            else
              ..._visibles.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TareaCard(tarea: t, onResponder: () => _responder(t)),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _stat(String etiqueta, String valor, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Column(children: [
          Text(valor, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(etiqueta, textAlign: TextAlign.center, style: const TextStyle(color: _gray, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _filtro(String texto, bool activo, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: activo ? _inkDeep : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: activo ? _inkDeep : _line),
          ),
          child: Text(texto,
              style: TextStyle(
                color: activo ? Colors.white : _gray,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              )),
        ),
      );

  Widget _mensaje(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icono, size: 44, color: _gray),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: _gray, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );
}
