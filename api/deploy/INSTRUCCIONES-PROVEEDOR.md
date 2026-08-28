# Backend de pedidos: instalación en gestores-api.oral-plus.com

**De:** Oral-Plus, área de Sistemas (sistemas@oral-plus.com)
**Para:** proveedor que administra el servidor de pedidos.oral-plus.com

## Contexto

En el servidor Linux con Docker que atiende `pedidos.oral-plus.com` (IP LAN
`192.168.2.249`, recibe el port-forward del puerto 443) corre hoy la API SAP
en el puerto 3006. Se necesita publicar un segundo servicio, el backend de la
app móvil de pedidos, en el subdominio dedicado `gestores-api.oral-plus.com`.
No hay que modificar la API SAP ni el router.

Si el servicio ya está instalado de una entrega anterior, esta versión lo
reemplaza: basta con descomprimir encima, revisar el `.env` y reconstruir el
contenedor (Paso 2).

## Contenido del paquete

| Archivo o carpeta | Qué es |
|---|---|
| `server.js`, `modules/` | Backend Node.js (Express), escucha en el puerto 3000 |
| `package.json`, `package-lock.json` | Dependencias (incluye `sharp`, que compila su binario de Linux durante `npm install`) |
| `Dockerfile`, `docker-compose.yml`, `.dockerignore` | Construcción y arranque del contenedor |
| `.env` | Configuración con credenciales reales. Confidencial: no subirlo a repositorios ni compartirlo. Debe quedar junto a `server.js` |
| `test/integracion/` | Pruebas de aceptación que se corren contra el servicio instalado (Paso 4) |
| `sql/` | Scripts de base de datos de referencia; no hay que ejecutarlos para instalar |
| `INSTRUCCIONES-PROVEEDOR.md` | Este documento |

Requisitos de red del contenedor: salida hacia `192.168.2.244:1433` (SQL
Server) y hacia `https://192.168.2.242:50000` (Service Layer de SAP). Con la
red bridge por defecto de Docker funciona sin configuración adicional.

## Paso 1. Subdominio (DNS)

Crear el registro `gestores-api.oral-plus.com` apuntando a la misma IP pública
que ya usa `pedidos.oral-plus.com`:

- CNAME `gestores-api` hacia `pedidos.oral-plus.com`, o
- registro A `gestores-api` hacia `181.205.151.221`

El router no cambia: se reutiliza el port-forward 443 hacia `.249`.

## Paso 2. Contenedor

```bash
mkdir -p /opt/pedidos-backend
cd /opt/pedidos-backend
# descomprimir aquí el contenido del ZIP (server.js, modules/, .env, etc.)
docker compose up -d --build
curl http://localhost:3000/api/test
```

Respuesta esperada:

```json
{"success":true,"message":"API SkyPagos funcionando correctamente","timestamp":"...","version":"1.0.0","database":"Conectada"}
```

Al arrancar, el servicio crea por sí mismo las tablas que necesita en la base
de datos Pedidos (`dispositivos`, `sesiones`, `productos_config`,
`productos_imagenes`, `comentarios_clientes`) si no existen.

## Paso 3. Reverse proxy

Regla: todo el tráfico de `https://gestores-api.oral-plus.com` va directo a
`127.0.0.1:3000` (o `192.168.2.249:3000`), sin prefijos ni reescrituras de
ruta, con certificado SSL para ese nombre.

Caddy:

```
gestores-api.oral-plus.com {
    reverse_proxy 192.168.2.249:3000
}
```

Nginx:

```nginx
server {
    listen 443 ssl;
    server_name gestores-api.oral-plus.com;
    # ssl_certificate y ssl_certificate_key de gestores-api.oral-plus.com

    location / {
        proxy_pass http://192.168.2.249:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Traefik (labels en el servicio `pedidos-backend` del `docker-compose.yml`):

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.gestoresapi.rule=Host(`gestores-api.oral-plus.com`)
      - traefik.http.routers.gestoresapi.tls=true
      - traefik.http.routers.gestoresapi.tls.certresolver=letsencrypt
      - traefik.http.services.gestoresapi.loadbalancer.server.port=3000
```

Cualquier otro proxy sirve mientras cumpla la misma regla.

## Paso 4. Verificación (criterio de aceptación)

Desde internet, fuera de la LAN:

```bash
# 1. JSON con "API SkyPagos funcionando correctamente"
curl https://gestores-api.oral-plus.com/api/test

# 2. Debe responder 400 con JSON (no una página HTML)
curl -X POST -H "Content-Type: application/json" -d "{}" \
  https://gestores-api.oral-plus.com/api/auth/login
# Esperado: {"success":false,"message":"Usuario y contraseña son requeridos"}

# 3. Sin sesión, las rutas de datos responden 401
curl -i https://gestores-api.oral-plus.com/api/clientes/cartera/C1000100148

# 4. La API SAP existente sigue igual
curl https://pedidos.oral-plus.com/api/test
```

Pruebas de aceptación completas, ejecutadas dentro del contenedor contra el
servicio instalado (tardan alrededor de dos minutos; crean y borran registros
de prueba, no crean pedidos):

```bash
cd /opt/pedidos-backend
docker compose exec pedidos-backend node test/integracion/run.js
```

Debe terminar con `TODAS LAS SUITES OK`.

## Comportamiento de esta versión

- Las claves del login no están en el código: `CLAVE_MAESTRA` (vacía = sin clave
  maestra) y `PREFIJO_CLAVE_VENDEDOR` se configuran en el `.env`.
- Comentarios del cliente (tabla `comentarios_clientes`), histórico de facturas (SAP)
  y edición del texto libre del cliente (`OCRD.Free_Text`, vía Service Layer).
- Todas las rutas de datos exigen sesión (token). Solo quedan abiertas
  `/api/test`, `/api/health`, `/api/auth/login` y `/api/dispositivos/registrar`.
- Cada sesión dura como máximo 12 horas; `SESSION_TIMEOUT` en el `.env` solo
  puede acortarla. Cerrar sesión desde la app invalida el token en el servidor.
- Con `REQUIRE_DEVICE_ID=true` (valor del `.env` entregado) solo entran
  teléfonos activados por Soporte TI desde la propia app.
- Los tokens emitidos por la versión anterior dejan de servir: tras el
  despliegue cada vendedor inicia sesión una vez.
- El catálogo de productos se lee de SAP por Service Layer (`SL_*` en el
  `.env`); si el Service Layer no responde, se usa SQL directo. Las fotos de
  los productos viven en la base de datos Pedidos, no en carpetas.

Cualquier duda: sistemas@oral-plus.com.
