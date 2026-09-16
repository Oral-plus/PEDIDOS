import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import 'claves_rastreo.dart';
import 'punto_ubicacion.dart';

class SesionRastreo {
  final String usuario;
  final String? token;
  final bool vencida;
  final String baseUrl;
  final String? idServicio;

  const SesionRastreo({
    required this.usuario,
    required this.token,
    required this.vencida,
    required this.baseUrl,
    this.idServicio,
  });

  bool get puedeEnviar => token != null && token!.isNotEmpty && !vencida;

  static SesionRastreo? desdePreferencias(SharedPreferences prefs, {DateTime? ahora}) {
    final usuario = (prefs.getString(ClavesRastreo.usuario) ?? '').trim();
    if (usuario.isEmpty) return null;
    final token = prefs.getString(ClavesRastreo.token);
    final login = (prefs.getString(ClavesRastreo.loginUsuario) ?? '').trim();
    final expiraMs = prefs.getInt(ClavesRastreo.expira);
    final momento = (ahora ?? DateTime.now()).millisecondsSinceEpoch;
    final vencida = token == null || token.isEmpty || expiraMs == null || expiraMs <= momento ||
        (login.isNotEmpty && login.toUpperCase() != usuario.toUpperCase());
    final guardada = (prefs.getString(ClavesRastreo.baseUrl) ?? '').trim();
    return SesionRastreo(
      usuario: usuario,
      token: token,
      vencida: vencida,
      baseUrl: guardada.isNotEmpty ? guardada : AppConfig.apiUrls.first,
      idServicio: prefs.getString(ClavesRastreo.idServicio),
    );
  }

  Map<String, String> get encabezados => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };
}

enum ResultadoEnvio { enviado, sesionInvalida, fallo }

class EnvioUbicaciones {
  EnvioUbicaciones._();

  static Future<ResultadoEnvio> enviar(SesionRastreo sesion, List<PuntoUbicacion> puntos, {http.Client? cliente}) async {
    if (puntos.isEmpty) return ResultadoEnvio.enviado;
    if (!sesion.puedeEnviar) return ResultadoEnvio.sesionInvalida;
    final c = cliente ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse('${sesion.baseUrl}/api/ubicaciones'),
            headers: sesion.encabezados,
            body: jsonEncode({
              'puntos': puntos.map((p) => p.paraServidor()).toList(),
              if (sesion.idServicio != null) 'idServicio': sesion.idServicio,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 401 || res.statusCode == 403) return ResultadoEnvio.sesionInvalida;
      if (res.statusCode != 200) return ResultadoEnvio.fallo;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['success'] == true ? ResultadoEnvio.enviado : ResultadoEnvio.fallo;
    } catch (_) {
      return ResultadoEnvio.fallo;
    } finally {
      if (cliente == null) c.close();
    }
  }

  static Future<int?> pulsoVisita(SesionRastreo sesion, String cliente, int visitaId, int duracionSegundos) async {
    if (!sesion.puedeEnviar) return null;
    final c = http.Client();
    try {
      final res = await c
          .put(
            Uri.parse('${sesion.baseUrl}/api/clientes/${Uri.encodeComponent(cliente)}/visita/$visitaId/actividad'),
            headers: sesion.encabezados,
            body: jsonEncode({'duracionSegundos': duracionSegundos}),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode;
    } catch (_) {
      return null;
    } finally {
      c.close();
    }
  }
}
