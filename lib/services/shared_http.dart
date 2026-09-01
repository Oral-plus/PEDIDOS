import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SharedHttp {
  SharedHttp._();

  static final http.Client client = IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 6,
  );
}
