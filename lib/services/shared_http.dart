import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Cliente HTTP único para toda la app. Reutiliza las conexiones abiertas
/// (keep-alive), así cada petición no vuelve a negociar TCP y TLS.
class SharedHttp {
  SharedHttp._();

  static final http.Client client = IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 6,
  );
}
