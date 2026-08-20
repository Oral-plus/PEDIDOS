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
| `.env.example` | Plantilla de configuración (referencia, sin secretos) |

**Además del ZIP**, Oral-Plus les envía por canal aparte el archivo `.env`
(configuración con credenciales reales — tratar como confidencial). Debe quedar
en la misma carpeta que `server.js` **antes** de construir el contenedor.
El `Dockerfile` ya copia la carpeta `modules/` y el `.env`, así que basta con
que ambos estén presentes al hacer el build.

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
