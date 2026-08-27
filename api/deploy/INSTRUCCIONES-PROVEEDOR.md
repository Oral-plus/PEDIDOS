# Solicitud: publicar backend de pedidos en gestores-api.oral-plus.com

**De:** Oral-Plus (sistemas@oral-plus.com)
**Para:** proveedor que administra el servidor de pedidos.oral-plus.com

## Contexto

En el servidor Linux con Docker que atiende `pedidos.oral-plus.com` (el que
recibe el port-forward del puerto 443, IP LAN `192.168.2.249`) hoy corre la
API SAP (contenedor en puerto 3006). Necesitamos publicar **un segundo
servicio** para la app móvil de pedidos, esta vez en un **subdominio
dedicado** (`gestores-api.oral-plus.com`) para no interferir con las rutas de
la aplicación existente. **No hay que tocar nada de lo existente**: ni la API
SAP, ni el router.

Este paquete (ZIP) contiene todo lo necesario:

| Archivo | Qué es |
|---|---|
| `server.js` | Backend Node.js (Express), escucha en puerto 3000 |
| `modules/` | Módulos del backend (incluye control de dispositivos). **Necesario** |
| `package.json` / `package-lock.json` | Dependencias |
| `Dockerfile` / `docker-compose.yml` | Para levantarlo como contenedor |

**Además del ZIP**, Oral-Plus les envía por canal aparte el archivo `.env`
(configuración con credenciales reales — tratar como confidencial). Debe quedar
en la misma carpeta que `server.js` **antes** de construir el contenedor.
El `docker-compose.yml` lo lee con `env_file`, así que solo debe estar en la
misma carpeta al levantar el contenedor; no queda dentro de la imagen.

## Paso 1 — Crear el subdominio (DNS)

Crear el registro para `gestores-api.oral-plus.com` apuntando a la misma IP
pública que ya usa `pedidos.oral-plus.com`:

- Opción simple: **CNAME** `gestores-api` → `pedidos.oral-plus.com`
- Equivalente: registro **A** `gestores-api` → `181.205.151.221`

No se toca el router: se reutiliza el port-forward 443 → `.249` existente.

## Paso 2 — Levantar el contenedor

```bash
mkdir -p /opt/pedidos-backend
# descomprimir el ZIP ahí, y colocar también el archivo .env recibido aparte
cd /opt/pedidos-backend
docker compose up -d --build
curl http://localhost:3000/api/test
```

Respuesta esperada: `{"success":true,"message":"🚀 API SkyPagos funcionando correctamente",...}`

Requisito de red: el contenedor debe poder salir hacia `192.168.2.244:1433`
(SQL Server de la LAN de Oral-Plus). Con la red bridge por defecto de Docker
esto funciona sin configuración extra.

## Paso 3 — Publicar el subdominio en el reverse proxy

Regla pedida: **todo** el tráfico de `https://gestores-api.oral-plus.com` →
`127.0.0.1:3000` (o `192.168.2.249:3000`). Sin prefijos, sin reescrituras de
ruta — el host completo directo al puerto 3000, con certificado SSL para ese
nombre.

Según el proxy que usen:

**Caddy** — bloque nuevo (el certificado se emite solo):

```
gestores-api.oral-plus.com {
    reverse_proxy 192.168.2.249:3000
}
```

**Nginx** — server block nuevo (certificado con certbot para el nombre):

```nginx
server {
    listen 443 ssl;
    server_name gestores-api.oral-plus.com;
    # ssl_certificate / ssl_certificate_key para gestores-api.oral-plus.com

    location / {
        proxy_pass http://192.168.2.249:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

**Traefik** — labels en el servicio `pedidos-backend` del docker-compose:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.gestoresapi.rule=Host(`gestores-api.oral-plus.com`)
      - traefik.http.routers.gestoresapi.tls=true
      - traefik.http.routers.gestoresapi.tls.certresolver=letsencrypt
      - traefik.http.services.gestoresapi.loadbalancer.server.port=3000
```

Cualquier otro proxy sirve igual, mientras cumpla la regla (host completo →
puerto 3000, con TLS).

## Paso 4 — Verificación (criterio de aceptación)

Desde internet (fuera de la LAN):

```bash
# 1. Debe responder JSON con "API SkyPagos funcionando correctamente":
curl https://gestores-api.oral-plus.com/api/test

# 2. Debe responder 400 con JSON (NO una página HTML):
curl -X POST -H "Content-Type: application/json" -d "{}" \
  https://gestores-api.oral-plus.com/api/auth/login
# Esperado: {"success":false,...,"Usuario y contraseña son requeridos"...}

# 3. Lo existente debe seguir igual (API SAP):
curl https://pedidos.oral-plus.com/api/test
# Esperado: {"success":true,"status":"API SAP Business One funcionando correctamente",...}
```

Si los 3 responden así, quedó listo. Cualquier duda: sistemas@oral-plus.com.

## Actualización: catálogo de productos desde SAP

Esta versión del backend lee el catálogo de productos directamente de SAP y
sirve las fotos de los productos, que Soporte TI sube desde la app. Al
desplegar hay que tener en cuenta tres cosas:

1. **Imágenes en la base de datos.** Las fotos de los productos se guardan en la
   BD Pedidos (tabla `productos_imagenes`), no en carpetas: no hay volúmenes ni
   archivos que copiar. Soporte TI las sube desde la app.
2. **Variables nuevas en el `.env`** (vienen en el `.env` que envía Oral-Plus):
   `SL_URL`, `SL_COMPANY_DB`, `SL_USER`, `SL_PASSWORD`, `SL_TLS_INSECURE`,
   `SAP_BODEGA`, `SAP_GRUPOS_PT`, `CATALOGO_FUENTE`, `CATALOGO_TTL_MIN`.
   El contenedor debe poder llegar al Service Layer de SAP
   (`https://192.168.2.242:50000`); si no llega, usa SQL directo automáticamente.
3. **Dependencias nativas.** `package.json` incluye `sharp` (recorte de fotos);
   `npm install --omit=dev` dentro de `node:18-slim` descarga el binario de
   Linux sin pasos adicionales.

Comprobación:

```bash
# Debe responder success:true con el catálogo del cliente (requiere un token de vendedor)
curl -H "Authorization: Bearer <token>" "https://gestores-api.oral-plus.com/api/productos?cliente=C1000100148"
# Una foto migrada debe responder image/webp (sale de la base de datos)
curl -I https://gestores-api.oral-plus.com/api/productos/imagen/50360251
```

## Actualización: sesiones de 12 horas y cierre de sesión seguro

1. **Duración.** Cada sesión dura como máximo 12 horas desde el login; después
   la app pide iniciar sesión otra vez. `SESSION_TIMEOUT` del `.env` solo puede
   acortarla (por ejemplo `8h`); un valor mayor se recorta a 12 h.
2. **Tabla nueva `sesiones`** en la BD Pedidos: el servidor la crea solo al
   arrancar (igual que `dispositivos`). Cada token lleva un identificador
   registrado ahí; cerrar sesión desde la app (`POST /api/auth/logout`) marca la
   fila y el token deja de servir aunque no haya vencido.
3. **Tokens anteriores.** Los tokens emitidos por la versión anterior del
   servidor no tienen registro y reciben 401: al desplegar, todos los
   vendedores deben iniciar sesión de nuevo (una sola vez).
4. **Catálogo por cliente.** `GET /api/productos` exige `?cliente=<CardCode>`:
   sin cliente responde 400 y con un cliente inexistente 404. Los precios salen
   únicamente de la lista de precios del cliente (sin respaldo a otra lista).

Comprobación:

```bash
# Debe responder 401 con "Credenciales incorrectas..."
curl -X POST -H "Content-Type: application/json" \
  -d "{\"usuario\":\"SKV18\",\"password\":\"incorrecta\"}" \
  https://gestores-api.oral-plus.com/api/auth/login
# Tras un login correcto, cerrar sesión y repetir una consulta con el mismo token: debe dar 401
curl -X POST -H "Authorization: Bearer <token>" https://gestores-api.oral-plus.com/api/auth/logout
```

## Actualización: todas las rutas exigen sesión

1. **Sesión obligatoria.** Todas las rutas de datos (`/api/clientes/...`,
   `/api/orders`, `/api/recaudos`, `/api/rutas/...`, `/api/encuestas`,
   `/api/productos`, etc.) responden 401 sin un token válido. Solo quedan
   abiertas `/api/test`, `/api/health`, `/api/auth/login` y
   `/api/dispositivos/registrar` (la app la usa antes del login).
   `/api/auth/register` (heredada de SkyPagos) queda reservada a Soporte TI.
2. **Dispositivo obligatorio.** Poner `REQUIRE_DEVICE_ID=true` en el `.env`:
   un login sin ID de servicio se rechaza y solo entran teléfonos activados por
   Soporte TI desde la app. Los usuarios de Soporte no pasan por este control.
3. **Cuentas de servicio.** El `.env` de producción no debe llevar `sa`:
   ejecutar `api/sql/crear_usuario_pedidos_app.sql` (usuario `pedidos_app`
   con permisos solo sobre SkyPagos, Pedidos, Ruta y lectura de RBOSKY3) y
   usar ese usuario en `DB_USER`/`DB_PASSWORD`. Para el Service Layer conviene
   un usuario de SAP de solo lectura en lugar de `manager`.

Comprobación:

```bash
# Sin token debe responder 401 (antes respondía con los datos del cliente)
curl -i https://gestores-api.oral-plus.com/api/clientes/cartera/C1000100148
# Login sin id_servicio debe responder 400
curl -X POST -H "Content-Type: application/json" -d "{\"usuario\":\"SKV18\",\"password\":\"SKV1\"}" \
  https://gestores-api.oral-plus.com/api/auth/login
```
