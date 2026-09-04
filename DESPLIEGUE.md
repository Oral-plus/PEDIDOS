# Despliegue

Proyecto PEDIDOS de Oral-Plus: backend Node.js (Express + SQL Server) y app
Flutter para la fuerza de ventas.

La configuración del backend vive en `api/.env`, que no se versiona y viaja con
el paquete de entrega. La app recibe la dirección del backend al compilar.

## 1. Backend

### Requisitos

- Docker y Docker Compose, o Node.js 18+ para instalarlo sin contenedor.
- Salida de red desde el servidor hacia SQL Server y hacia el Service Layer de
  SAP si se usa el catálogo por Service Layer.
- Bases de datos de pagos, pedidos, rutas y lectura de la base de SAP.

### Configuración

`api/.env` trae los valores del entorno. Estas son las variables que lee el
servicio:

| Variable | Para qué |
|---|---|
| `PORT` | Puerto del servicio |
| `NODE_ENV` | `production` en el servidor |
| `LOG_LEVEL` | `warn` en producción, `info` para diagnóstico |
| `JWT_SECRET` | Secreto para firmar los tokens de sesión |
| `SESSION_TIMEOUT` | Duración de la sesión; el servidor no la deja pasar de 12 h |
| `BCRYPT_ROUNDS` | Costo del cifrado de los PIN |
| `REQUIRE_DEVICE_ID` | `true` exige dispositivo activado por Soporte TI |
| `DB_SERVER`, `DB_PORT`, `DB_USER`, `DB_PASSWORD` | Conexión a SQL Server |
| `DB_NAME`, `PEDIDOS_DB_NAME`, `SAP_DB_NAME`, `RUTA_DB_NAME` | Nombres de las bases |
| `SOPORTE_USUARIOS` | Códigos con rol de Soporte TI, separados por coma |
| `CLAVE_MAESTRA` | Clave que entra con cualquier usuario; vacía la deshabilita |
| `PREFIJO_CLAVE_VENDEDOR` | Prefijo con el que los gestores arman su clave |
| `SL_URL`, `SL_COMPANY_DB`, `SL_USER`, `SL_PASSWORD` | Service Layer de SAP |
| `SL_TLS_INSECURE` | `true` si el Service Layer usa certificado propio |
| `SL_TIMEOUT_MS`, `SL_PAGE_SIZE` | Tiempo de espera y tamaño de página del catálogo |
| `SAP_BODEGA`, `SAP_GRUPOS_PT` | Bodega y grupos de artículos del catálogo |
| `CATALOGO_FUENTE` | `auto`, `sl` o `sql` |
| `CATALOGO_TTL_MIN` | Minutos que el catálogo permanece en memoria |
| `REDIS_URL` | Caché de lecturas; vacío la deshabilita sin afectar el servicio |
| `REDIS_PREFIJO` | Prefijo de las claves en Redis |
| `GOOGLE_MAPS_API_KEY`, `ANTHROPIC_API_KEY` | Servicios externos; vacío los deshabilita |
| `GEOCODING_USER_AGENT` | Identificación en las consultas de geocodificación |

### Instalación con Docker

```bash
cd api
docker compose up -d --build
curl http://localhost:3000/api/test
```

El compose levanta el backend y el Redis de la caché, y define `REDIS_URL`
hacia el contenedor de Redis. Si no se quiere Redis, se elimina ese servicio y
se deja `REDIS_URL` vacío en el `.env`.

Al arrancar, el servicio crea por sí mismo las tablas que necesita en la base de
pedidos: dispositivos, sesiones, pedidos, recaudos, evidencias, comentarios,
encuestas, configuración e imágenes de productos y cancelaciones de talonario.

### Instalación sin Docker

```bash
cd api
npm ci --omit=dev
node server.js
```

### Reverse proxy

Todo el tráfico del dominio público va directo al puerto del backend, sin
prefijos ni reescrituras de ruta, con su certificado TLS. El proxy no debe
transformar las respuestas: la app espera JSON, no páginas de error HTML.

Caddy:

```
DOMINIO_PUBLICO {
    reverse_proxy HOST_BACKEND:3000
}
```

Nginx:

```nginx
location / {
    proxy_pass http://HOST_BACKEND:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

### Verificación

```bash
curl https://DOMINIO_PUBLICO/api/test
curl -X POST -H "Content-Type: application/json" -d "{}" https://DOMINIO_PUBLICO/api/auth/login
curl -i https://DOMINIO_PUBLICO/api/clientes
```

La primera responde el estado del servicio; la segunda debe devolver JSON con el
mensaje de campos requeridos, no una página HTML; la tercera, 401 sin sesión.

Pruebas de aceptación contra el servicio instalado:

```bash
docker compose exec pedidos-backend node test/integracion/run.js
```

Debe terminar en `TODAS LAS SUITES OK`. Crean y borran sus propios registros.

## 2. Aplicación

### Compilación

La app toma la dirección del backend al compilar:

```bash
flutter build apk --release --dart-define=API_URLS=https://DOMINIO_PUBLICO
```

`API_URLS` admite varias direcciones separadas por coma; la app usa la primera
que responda y recuerda la última que funcionó, de modo que sirve para dejar el
servidor de la red local como respaldo:

```bash
flutter build apk --release \
  --dart-define=API_URLS=https://DOMINIO_PUBLICO,http://HOST_LAN:3000
```

`API_BASE_URL` se acepta como alias de una sola dirección.

### Firma

Para firmar con la clave de la empresa se crea `android/key.properties`, que no
se versiona, con `storeFile`, `storePassword`, `keyAlias` y `keyPassword`. Sin
ese archivo el APK se firma con la clave de depuración, que sirve para pruebas
pero no para distribución.

### Versión

`pubspec.yaml` lleva la versión y el número de compilación (`version: x.y.z+n`).
Subir el número de compilación en cada entrega para que el dispositivo la
reconozca como actualización.

## 3. Operación

- **Talonarios**: cada pago de cartera consume una unidad del talonario del
  gestor. Sistemas asigna los talonarios en la tabla `TALONARIO` con el prefijo
  del usuario del gestor y el rango de números. Sin unidades disponibles la app
  no permite registrar pagos.
- **Dispositivos**: con `REQUIRE_DEVICE_ID=true` cada equipo nuevo queda
  pendiente hasta que Soporte TI lo activa desde la app.
- **Sesiones**: duran como máximo 12 horas y se pueden cerrar desde el servidor.
- **Catálogo**: se lee del Service Layer de SAP y, si no responde, de SQL. Las
  imágenes de los productos viven en la base de datos.
