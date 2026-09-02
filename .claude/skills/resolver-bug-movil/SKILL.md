---
name: resolver-bug-movil
description: Resuelve bugs en la app movil Flutter/Dart de forma profesional - reproduce, localiza la causa raiz, aplica el arreglo minimo, lo valida con tests y verifica el build. Cubre fugas de memoria, disciplina de dispose, cache acotado con LRU/TTL, isolates para trabajo pesado, y validacion en modo profile. Usar cuando se reporte un bug, se pida arreglar un fallo, o se ataque rendimiento/memoria/cache en lib/*.dart.
---

# Resolver bugs en la app movil (Flutter/Dart)

Metodologia profesional para arreglar fallos en esta app sin introducir regresiones. Basada en practicas de skills reputadas de Flutter (ver Fuentes) y adaptada a este proyecto.

## Metodo (en orden, no saltarse pasos)

1. **Reproducir y acotar.** Antes de tocar codigo, entender el sintoma exacto: pantalla, accion, dato de entrada, mensaje. Si hay captura o log, leerlo literal. Un sintoma que "se parece" a un bug conocido puede tener otra causa.
2. **Localizar.** Buscar el punto exacto con Grep/Glob (widget, servicio, provider). No leer el repo entero: ir al archivo y metodo responsables.
3. **Causa raiz, no el sintoma.** Preguntar por que ocurre. Ejemplos tipicos en esta app: un `catch (_) {}` que traga el error; una respuesta no-JSON que revienta `jsonDecode` (el proxy convierte errores en HTML); un orden de flujo que persiste un campo antes de tener el dato; un objeto no liberado en `dispose()`.
4. **Arreglo minimo y local.** Cambiar lo justo. Que el codigo lea como el de alrededor (mismo estilo, mismos idioms). No refactorizar de paso.
5. **Validar SIEMPRE.** Cada cambio se valida: `dart analyze` sin errores en los archivos tocados, y test unitario nuevo o existente que cubra el caso. Los tests de logica pura (cache, carrito, parseo, formato) corren sin backend ni BD con `flutter test`.
6. **Verificar el build.** Para un cambio que va al APK, recompilar release y confirmar el binario: `grep -a` de las cadenas nuevas en `.dart_tool/flutter_build/*/app.dill` (el `libapp.so` no es fiable para esto). Un build de Gradle de ~30 s es reuso de cache; uno real tarda minutos. Tras un build interrumpido, `flutter clean`.

## Reglas de memoria y fugas (Flutter)

- **Disponer todo lo disponible en `dispose()`**: `AnimationController`, `TextEditingController`, `StreamSubscription`, `Timer`, `FocusNode`. Una suscripcion sin cancelar es la fuga de produccion mas comun.
- **Imagenes al tamano de display**, no a resolucion fuente: `cacheWidth`/`cacheHeight`; bajar fotos antes de subir (`image_picker` maxWidth/maxHeight).
- **Trabajo pesado (parseo JSON grande, cripto, imagenes) fuera del hilo de UI** con `compute()` / `Isolate.run()`. Solo vale la pena para trabajo de decenas de ms o mas. Los argumentos/resultados deben ser serializables.
- **Perfilar en modo profile en dispositivo fisico** (`flutter run --profile`); el modo debug da tiempos enganosos. DevTools (Memory snapshots, retaining paths, Timeline) es la herramienta autoritativa, no la intuicion.

## Reglas de cache (esta app usa CacheService + disco+ETag)

- **Todo cache en memoria debe estar acotado**: sin tope, un cache crece hasta OOM. Usar `LinkedHashMap` con expulsion LRU (al leer un hit, remove+re-put; al exceder el tope, quitar el primero) y barrido de vencidas.
- **El tope se dimensiona a los recursos**, no un magico fijo: derivarlo de RAM o de `Platform.numberOfProcessors`, acotado con un `clamp` generoso.
- **El TTL debe cumplirse en TODAS las capas.** Si un valor se persiste en disco/SharedPreferences, guardar su marca de tiempo y comprobarla al leer; si no, el "TTL" solo existe en memoria y el valor vive para siempre.
- **Los archivos de cache en disco se limpian**: una rutina de mantenimiento en background que borra por edad y por cantidad maxima, sin bloquear la UI.
- **Cada escritura invalida sus lecturas**: al guardar (pedido, recaudo, visita, datos de cliente) invalidar las claves/prefijos que quedan stale. Verificar el mapa clave->invalidacion.

## Convenciones del proyecto (obligatorias)

- Archivos `.dart` en CRLF. Sin emojis en logs ni banners; comentarios sin aspecto de IA (ver skill `limpiar-codigo`).
- No cachear `null` ni respuestas con `success != true`.
- Validar `Content-Type`/status antes de `jsonDecode` (el proxy publica errores como HTML).
- Los tests de integracion del backend (`api/test/integracion/`) necesitan servidor + BD real en la LAN 192.168.2.x. Los unitarios Flutter no.
- Subir version en `pubspec.yaml` en cada APK entregable; dejar el APK en `Desktop\PROYECTO VENTAS\PEDIDOS-vX.Y.Z.apk`.

## Checklist de cierre

- [ ] Causa raiz identificada (no solo el sintoma)
- [ ] Arreglo minimo, mismo estilo del entorno
- [ ] `dart analyze` sin errores nuevos
- [ ] Test que cubre el caso (unitario si es logica pura)
- [ ] Build release verificado en `app.dill` si va al APK
- [ ] Invalidaciones de cache revisadas si se toco estado

## Fuentes

- Arcturus91/claude-flutter-skill (metodologia y guia de rendimiento/memoria): https://github.com/Arcturus91/claude-flutter-skill
- Harishwarrior/flutter-claude-skills: https://github.com/Harishwarrior/flutter-claude-skills
- LRU con LinkedHashMap en Dart (patron de expulsion): https://pub.dev/packages/lru_cache
