import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_easy_service.dart';

class VisitaActivaProvider extends ChangeNotifier {
  static const Duration intervaloPulso = Duration(seconds: 60);

  Map<String, dynamic>? cliente;
  Map<String, dynamic>? ruta;
  DateTime? _inicio;
  Timer? _timer;
  Duration transcurrido = Duration.zero;
  int? _visitaId;
  String? _codigoCliente;
  DateTime? _ultimoPulso;

  int? get visitaId => _visitaId;

  bool enPantallaVisita = false;

  bool get activa => _inicio != null;
  DateTime? get inicio => _inicio;

  String get nombreCliente {
    final n = (cliente?['nombre'] ?? cliente?['cardName'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    return (ruta?['nombre'] ?? 'Cliente')
        .toString()
        .replaceFirst(RegExp(r'^visita\s+a\s+', caseSensitive: false), '');
  }

  String get textoTiempo {
    final d = transcurrido;
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  void iniciar({
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> ruta,
    required DateTime inicio,
  }) {
    if ((cliente['id'] ?? '').toString() != _codigoCliente) {
      _visitaId = null;
      _codigoCliente = null;
    }
    this.cliente = cliente;
    this.ruta = ruta;
    _inicio = inicio;
    transcurrido = DateTime.now().difference(inicio);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_inicio == null) return;
      transcurrido = DateTime.now().difference(_inicio!);
      _pulsoSiCorresponde();
      notifyListeners();
    });
    notifyListeners();
  }

  void setVisitaId(int id, String codigoCliente) {
    _visitaId = id;
    _codigoCliente = codigoCliente;
    _ultimoPulso = DateTime.now();
  }

  void _pulsoSiCorresponde() {
    final id = _visitaId;
    final codigo = _codigoCliente;
    if (id == null || codigo == null || codigo.isEmpty) return;
    final ahora = DateTime.now();
    if (_ultimoPulso != null && ahora.difference(_ultimoPulso!) < intervaloPulso) return;
    _ultimoPulso = ahora;
    ApiEasyService().pulsoVisita(codigo, id, transcurrido.inSeconds);
  }

  void setEnPantallaVisita(bool v) {
    if (enPantallaVisita == v) return;
    enPantallaVisita = v;
    notifyListeners();
  }

  void finalizar() {
    _timer?.cancel();
    _timer = null;
    _inicio = null;
    _visitaId = null;
    _codigoCliente = null;
    _ultimoPulso = null;
    cliente = null;
    ruta = null;
    transcurrido = Duration.zero;
    enPantallaVisita = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
