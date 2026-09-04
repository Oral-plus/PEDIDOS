---
name: limpiar-codigo
description: Limpia el codigo del proyecto - elimina comentarios con un analizador lexico seguro, quita rastros de codigo generado por IA (emojis en logs, banners, menciones) y detecta hardcodeos para moverlos a variables de entorno. Usar cuando se pida limpiar comentarios, quitar emojis de logs o dejar el codigo profesional.
---

# Limpiar codigo

Proceso en cuatro pasos. Trabajar siempre sobre un arbol de git limpio para poder revisar y revertir con el diff.

## 1. Eliminar comentarios

Ejecutar el script incluido en esta skill. Analiza lexicamente cada lenguaje (Dart, JS/TS, PHP, SQL, Python), por lo que NO toca strings, URLs (`http://...`), regex ni interpolaciones; respeta los finales de linea de cada archivo (CRLF/LF) y elimina la linea completa cuando queda vacia.

```powershell
cd <raiz del repo>
git ls-files -- "*.dart" "*.js" "*.php" "*.sql" "*.py" |
  Where-Object { $_ -notmatch 'node_modules|ephemeral|\.plugin_symlinks' -and $_ -ne 'api/Datos.js' -and $_ -notmatch '^\.claude/' } |
  Out-File -Encoding utf8 lista.txt
node .claude/skills/limpiar-codigo/scripts/strip_comments.js --list lista.txt
```

- `--dry-run` muestra que cambiaria sin escribir nada.
- Exclusiones obligatorias: `node_modules`, `ephemeral`, `.plugin_symlinks`, `.claude/` y `api/Datos.js` (API SAP del proveedor: no se modifica).
- El script conserva solo (no borrar a mano): directivas `// ignore:` / `// ignore_for_file:` de Dart, directivas `eslint`/`@ts-` de JS, comentarios ejecutables `/*!` de MySQL y shebangs `#!`.

## 2. Quitar rastros de codigo generado por IA

Los comentarios ya se fueron en el paso 1; esto limpia lo que vive dentro de strings:

- Emojis en logs y mensajes: buscar con `git grep -P "[\x{2600}-\x{27BF}\x{1F300}-\x{1FAFF}]"` y eliminar el emoji junto con su espacio adyacente. Nunca dejar emojis en logs ni banners.
- Banners decorativos: `git grep -E "={6,}|-{10,}|\*{6,}"` en strings de log o PRINT de SQL; reemplazar el bloque por un unico mensaje breve y descriptivo.
- Menciones: `git grep -i -E "generad[oa] (por|con) (ia|ai)|generated (by|with)|chatgpt|openai"` y eliminar.
- Al terminar, revalidar sintaxis (paso 4).

## 3. Detectar hardcodeos

Buscar y evaluar uno por uno:

```powershell
git grep -n -E "\b(192\.168\.|10\.|172\.16\.)[0-9.]+"        # IPs de red local
git grep -n -i -E "(password|secret|api_?key)\s*[=:].?['\"]"  # credenciales
git grep -n -E "https?://[a-z0-9.-]+"                          # URLs fijas
```

Regla de correccion: mover a variable de entorno dejando el valor actual como default (`process.env.X || "valor"`), para no cambiar el comportamiento existente. En los tests de integracion las credenciales van en `PRUEBAS_USUARIO` / `PRUEBAS_CLAVE`.

No son hardcodeos (dejar como estan): la lista `_baseUrls` de descubrimiento automatico de servidor en el cliente Flutter (configuracion por diseno), defaults de scripts utilitarios que ya leen `process.env`, y usuarios/datos de prueba documentados en el README de los tests.

## 4. Verificar

- `node --check` sobre cada `.js` tocado: cero errores.
- `flutter analyze --no-pub` antes y despues: la misma cantidad de avisos (comparar ignorando numeros de linea).
- Revisar el diff: toda linea eliminada debe ser un comentario, o reaparecer entre las añadidas sin su comentario final.
- No hacer commit salvo que el usuario lo pida.
