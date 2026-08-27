import 'package:flutter/material.dart';

/// Navegador raíz de la app. Permite cambiar de pantalla desde servicios que
/// no tienen BuildContext (por ejemplo al vencer o cerrarse la sesión).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
