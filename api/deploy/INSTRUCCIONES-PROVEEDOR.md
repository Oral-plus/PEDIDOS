# Solicitud: publicar backend de pedidos en pedidos.oral-plus.com/pedidos-api

**De:** Oral-Plus (sistemas@oral-plus.com)
**Para:** proveedor que administra el servidor de pedidos.oral-plus.com

## Contexto

En el servidor Linux con Docker que atiende `pedidos.oral-plus.com` (el que
recibe el port-forward del puerto 443, IP LAN `192.168.2.249`) hoy corre la
API SAP (contenedor en puerto 3006). Necesitamos publicar **un segundo
servicio** en ese mismo dominio, bajo el prefijo `/pedidos-api`, para que la
app móvil de pedidos funcione fuera de la red de la oficina. **No hay que
tocar nada de lo existente**: ni la API SAP, ni el DNS, ni el router.

Este paquete (ZIP) contiene todo lo necesario:

| Archivo | Qué es |
|---|---|
| `server.js` | Backend Node.js (Express), escucha en puerto 3000 |
| `modules/` | Módulos del backend (incluye control de dispositivos). **Necesario** |
| `package.json` / `package-lock.json` | Dependencias |
| `Dockerfile` / `docker-compose.yml` | Para levantarlo como contenedor |
| `.env.example` | Plantilla de configuración (referencia, sin secretos) |

**Además del ZIP**, Oral-Plus les envía por canal aparte el archivo `.env`
(configuración con credenciales reales — tratar como confidencial). Debe quedar
en la misma carpeta que `server.js` **antes** de construir el contenedor.
El `Dockerfile` ya copia la carpeta `modules/` y el `.env`, así que basta con
que ambos estén presentes al hacer el build.

## Paso 1 — Levantar el contenedor

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

## Paso 2 — Agregar la ruta en el reverse proxy

Regla pedida: `https://pedidos.oral-plus.com/pedidos-api/*` → `127.0.0.1:3000`
(o `192.168.2.249:3000`), **quitando el prefijo `/pedidos-api`** antes de
reenviar. Ejemplo: `/pedidos-api/api/auth/login` debe llegar al backend como
`/api/auth/login`.

Según el proxy que usen:

**Caddy** — dentro del bloque del sitio `pedidos.oral-plus.com`, antes de la
ruta general:

```
handle_path /pedidos-api/* {
    reverse_proxy 192.168.2.249:3000
}
```

**Nginx** — en el server block del dominio:

```nginx
location /pedidos-api/ {
    proxy_pass http://192.168.2.249:3000/;   # la barra final quita el prefijo
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

**Traefik** — labels en el servicio `pedidos-backend` del docker-compose:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.pedidosapi.rule=Host(`pedidos.oral-plus.com`) && PathPrefix(`/pedidos-api`)
      - traefik.http.routers.pedidosapi.tls=true
      - traefik.http.middlewares.pedidosstrip.stripprefix.prefixes=/pedidos-api
      - traefik.http.routers.pedidosapi.middlewares=pedidosstrip
      - traefik.http.services.pedidosapi.loadbalancer.server.port=3000
```

Cualquier otro proxy sirve igual, mientras cumpla la regla (prefijo
`/pedidos-api` → puerto 3000, con strip del prefijo).

## Paso 3 — Verificación (criterio de aceptación)

Desde internet (fuera de la LAN):

```bash
# 1. Debe responder JSON con "API SkyPagos funcionando correctamente":
curl https://pedidos.oral-plus.com/pedidos-api/api/test

# 2. Debe responder 400 con JSON (NO una página HTML):
curl -X POST -H "Content-Type: application/json" -d "{}" \
  https://pedidos.oral-plus.com/pedidos-api/api/auth/login
# Esperado: {"success":false,...,"Usuario y contraseña son requeridos"...}

# 3. Lo existente debe seguir igual (API SAP):
curl https://pedidos.oral-plus.com/api/test
# Esperado: {"success":true,"status":"API SAP Business One funcionando correctamente",...}
```

Si los 3 responden así, quedó listo. Cualquier duda: sistemas@oral-plus.com.
