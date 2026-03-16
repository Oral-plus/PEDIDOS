import 'package:flutter/material.dart';

class SessionProvider extends ChangeNotifier {
  String _codigoCliente = '';
  String _nombreCliente = '';
  String _direccion = '';
  String _telefono = '';
  String _correo = '';
  String _vendedor = '';
  String _ciudad = '';
  double _balance = 0;

  String get codigoCliente => _codigoCliente;
  String get nombreCliente => _nombreCliente;
  String get direccion => _direccion;
  String get telefono => _telefono;
  String get correo => _correo;
  String get vendedor => _vendedor;
  String get ciudad => _ciudad;
  double get balance => _balance;

  bool get hasCode => _codigoCliente.isNotEmpty;

  void setCodigoCliente(String codigo) {
    _codigoCliente = codigo.trim();
    notifyListeners();
  }

  void setClienteData({
    required String codigo,
    String nombre = '',
    String direccion = '',
    String telefono = '',
    String correo = '',
    String vendedor = '',
    String ciudad = '',
    double balance = 0,
  }) {
    _codigoCliente = codigo.trim();
    _nombreCliente = nombre.trim();
    _direccion = direccion.trim();
    _telefono = telefono.trim();
    _correo = correo.trim();
    _vendedor = vendedor.trim();
    _ciudad = ciudad.trim();
    _balance = balance;
    notifyListeners();
  }

  void clear() {
    _codigoCliente = '';
    _nombreCliente = '';
    _direccion = '';
    _telefono = '';
    _correo = '';
    _vendedor = '';
    _ciudad = '';
    _balance = 0;
    notifyListeners();
  }
}
