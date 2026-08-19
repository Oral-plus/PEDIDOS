import 'dart:async';
import 'package:flutter/foundation.dart';

/// Estado global de la visita en curso. Alimenta el cronómetro flotante que
/// se muestra por encima de toda la app mientras haya una visita abierta.
class VisitaActivaProvider extends ChangeNotifier {
  Map<String, dynamic>? cliente;
  Map<String, dynamic>? ruta;
  DateTime? _inicio;
  Timer? _timer;
  Duration transcurrido = Duration.zero;

  /// True mientras el usuario está dentro de la pantalla de la visita
  /// (ahí no se muestra el flotante porque ya ve el cronómetro grande).
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
    this.cliente = cliente;
    this.ruta = ruta;
    _inicio = inicio;
    transcurrido = DateTime.now().difference(inicio);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_inicio == null) return;
      transcurrido = DateTime.now().difference(_inicio!);
      notifyListeners();
    });
    notifyListeners();
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
