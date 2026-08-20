# Despliegue del backend PEDIDOS en el servidor 192.168.2.249

Objetivo: que `https://gestores-api.oral-plus.com/*` llegue al backend de la
app (server.js, puerto 3000) para que el login funcione desde cualquier red.
Se usa un subdominio dedicado (no un prefijo de ruta) para no interferir con
las rutas de la aplicación existente en `pedidos.oral-plus.com`.

> Todos los comandos del PC se ejecutan en PowerShell o Git Bash desde
> `c:\Users\skyen\Desktop\PROYECTO VENTAS\PEDIDOS\api`. Reemplaza `USUARIO`
> por el usuario SSH real del servidor 192.168.2.249.

## Paso 0 — Crear el subdominio (DNS)

En el panel del DNS de `oral-plus.com` (nameservers de mi.com.co):

- **CNAME** `gestores-api` → `pedidos.oral-plus.com` (opción simple), o
- **A** `gestores-api` → `181.205.151.221`

No se toca el router: se reutiliza el port-forward 443 → `.249` existente.

## Paso 1 — Copiar los archivos al servidor (desde este PC)

```bash
ssh USUARIO@192.168.2.249 "mkdir -p /opt/pedidos-backend"
scp server.js package.json package-lock.json .env deploy/Dockerfile deploy/docker-compose.yml USUARIO@192.168.2.249:/opt/pedidos-backend/
scp -r modules USUARIO@192.168.2.249:/opt/pedidos-backend/
```

## Paso 2 — Construir y levantar el contenedor (por SSH)

```bash
ssh USUARIO@192.168.2.249
cd /opt/pedidos-backend
docker compose up -d --build     # si falla, probar: docker-compose up -d --build
curl http://localhost:3000/api/test
```

Debe responder: `{"success":true,"message":"🚀 API SkyPagos funcionando correctamente",...}`

Verificar también desde el PC: `http://192.168.2.249:3000/api/test`

## Paso 3 — Publicar el subdominio en el reverse proxy

```bash
docker ps
```

Buscar un contenedor tipo `caddy`, `nginx`, `nginx-proxy-manager`, `traefik`
o `pangolin`. Según cuál sea, aplicar UNA de las secciones siguientes. La
regla siempre es la misma: **todo** el host `gestores-api.oral-plus.com` →
puerto 3000, sin prefijos ni reescrituras, con certificado SSL para el nombre.

### Si es Caddy

Agregar un bloque nuevo al Caddyfile (el certificado se emite solo):

```
gestores-api.oral-plus.com {
    reverse_proxy 192.168.2.249:3000
}
```

Recargar: `docker exec <contenedor> caddy reload --config /etc/caddy/Caddyfile`

### Si es Nginx (o Nginx Proxy Manager)

Server block nuevo para `gestores-api.oral-plus.com` con su certificado
(certbot) y:

```nginx
location / {
    proxy_pass http://192.168.2.249:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

En NPM: Hosts → "Add Proxy Host" con dominio `gestores-api.oral-plus.com`,
destino `192.168.2.249:3000`, y SSL con "Request a new certificate".

### Si es Traefik

Agregar al contenedor `pedidos-backend` (en su docker-compose.yml) estas
labels y conectarlo a la red de Traefik:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.gestoresapi.rule=Host(`gestores-api.oral-plus.com`)
      - traefik.http.routers.gestoresapi.tls=true
      - traefik.http.routers.gestoresapi.tls.certresolver=letsencrypt
      - traefik.http.services.gestoresapi.loadbalancer.server.port=3000
```

Luego `docker compose up -d` de nuevo.

## Paso 4 — Prueba final desde internet

Desde cualquier red (o con datos móviles):

```bash
curl https://gestores-api.oral-plus.com/api/test
```

Debe responder el JSON de "API SkyPagos". Si responde 404 HTML, la regla del
proxy no quedó bien; si el certificado falla, el DNS aún no propaga o falta
emitirlo.

## Paso 5 — Instalar el APK nuevo en los teléfonos

El APK recompilado (con el subdominio de primera en la lista) queda en:
`build\app\outputs\flutter-apk\app-release.apk`
(copia de entrega: `Desktop\PROYECTO VENTAS\PEDIDOS-app-release.apk`)

La app prueba las URLs en este orden:
1. `https://gestores-api.oral-plus.com` (funciona en cualquier red)
2. `http://192.168.2.249:3000` (LAN directa, por si se cae el internet)
3. `http://192.168.2.73:3000` (PC de desarrollo, fallback temporal)

## Notas

- El contenedor se conecta al SQL Server de `192.168.2.244:1433` (bases
  SkyPagos y Pedidos); desde el .249 hay acceso directo por LAN.
- `restart: always` hace que el backend arranque solo si se reinicia el
  servidor.
- No se tocó ni el router: se reutiliza el port-forward 443 → .249 que ya
  existía. Lo único nuevo en DNS es el registro del subdominio.
- La API SAP existente (`pedidos.oral-plus.com/api`) no se toca en absoluto.
- Cuando el contenedor esté estable, el `node server.js` del PC de desarrollo
  ya no es necesario para producción.
