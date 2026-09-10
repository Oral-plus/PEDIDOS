import 'package:flutter_test/flutter_test.dart';
import 'package:skypagos/config/app_config.dart';

void main() {
  test('sin parametro de compilacion la app apunta al servidor de produccion', () {
    expect(AppConfig.apiUrls, isNotEmpty);
    expect(AppConfig.apiUrls.first, AppConfig.apiUrlProduccion);
    expect(AppConfig.personalizada, isFalse);
  });

  test('el servidor de produccion es una direccion https valida', () {
    final uri = Uri.parse(AppConfig.apiUrlProduccion);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
    expect(AppConfig.apiUrlProduccion.endsWith('/'), isFalse);
  });

  test('programacion apunta al rutero web y es https valido', () {
    expect(AppConfig.urlProgramacion, AppConfig.urlProgramacionPorDefecto);
    final uri = Uri.parse(AppConfig.urlProgramacion);
    expect(uri.scheme, 'https');
    expect(uri.host, 'oral-plus.com');
    expect(uri.path, '/RUTERO/login.php');
  });
}
