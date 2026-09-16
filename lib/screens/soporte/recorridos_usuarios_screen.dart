import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_easy_service.dart';
import '../recorrido_screen.dart';

class RecorridosUsuariosScreen extends StatefulWidget {
  const RecorridosUsuariosScreen({super.key});

  @override
  State<RecorridosUsuariosScreen> createState() => _RecorridosUsuariosScreenState();
}

class _RecorridosUsuariosScreenState extends State<RecorridosUsuariosScreen> {
  static const Color _ink = Color(0xFF111827);
  static const Color _gray = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _surface = Color(0xFFF0F4F8);
  static const Color _azul = Color(0xFF1A56DB);
  static const Color _verde = Color(0xFF16A34A);
  static const Color _rojo = Color(0xFFDC2626);

  final ApiEasyService _api = ApiEasyService();
  DateTime _fecha = DateTime.now();
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _api.getUsuariosRecorrido(fecha: RecorridoScreen.fechaTexto(_fecha));
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res['success'] == true) {
        _usuarios = ((res['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _usuarios = [];
        _error = res['message']?.toString() ?? 'No se pudieron cargar los usuarios';
      }
    });
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (elegida == null || !mounted) return;
    setState(() => _fecha = elegida);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final conAlerta = _usuarios.where((u) => ((u['simuladas'] as num?) ?? 0) > 0).length;
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text('Recorridos', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Fecha', icon: const Icon(Icons.calendar_month_rounded), onPressed: _cargando ? null : _elegirFecha),
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh_rounded), onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              '${RecorridoScreen.fechaTexto(_fecha)} · ${_usuarios.length} usuario(s) con registros'
              '${conAlerta > 0 ? ' · $conAlerta con ubicación simulada' : ''}',
              style: TextStyle(color: conAlerta > 0 ? _rojo : _gray, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_cargando)
              const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _gray)),
              )
            else if (_usuarios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('Nadie ha reportado ubicación en esta fecha', textAlign: TextAlign.center, style: TextStyle(color: _gray)),
              )
            else
              ..._usuarios.map(_fila),
          ],
        ),
      ),
    );
  }

  Widget _fila(Map<String, dynamic> u) {
    final simuladas = (u['simuladas'] as num?)?.toInt() ?? 0;
    final nombre = (u['usuarioNombre'] ?? '').toString();
    final codigo = (u['usuarioCodigo'] ?? '').toString();
    final alerta = simuladas > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alerta ? _rojo.withOpacity(0.45) : _line),
      ),
      child: ListTile(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RecorridoScreen(usuarioCodigo: codigo, usuarioNombre: nombre.isEmpty ? codigo : nombre),
          ));
        },
        leading: CircleAvatar(
          backgroundColor: (alerta ? _rojo : _azul).withOpacity(0.12),
          child: Icon(alerta ? Icons.gps_off_rounded : Icons.person_pin_circle_rounded, color: alerta ? _rojo : _azul),
        ),
        title: Text(nombre.isEmpty ? codigo : nombre, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${u['puntos'] ?? 0} registros · ${u['enCliente'] ?? 0} en cliente · '
          '${RecorridoScreen.horaDe(u['primera']?.toString())} a ${RecorridoScreen.horaDe(u['ultima']?.toString())}',
          style: const TextStyle(color: _gray, fontSize: 12),
        ),
        trailing: alerta
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _rojo.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text('$simuladas simulada(s)', style: const TextStyle(color: _rojo, fontSize: 11, fontWeight: FontWeight.w900)),
              )
            : const Icon(Icons.chevron_right_rounded, color: _verde),
      ),
    );
  }
}
