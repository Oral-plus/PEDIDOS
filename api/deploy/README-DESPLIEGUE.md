# Despliegue del backend PEDIDOS en el servidor 192.168.2.249

Objetivo: que `https://pedidos.oral-plus.com/pedidos-api/*` llegue al backend
de la app (server.js, puerto 3000) para que el login funcione desde cualquier
red. El proxy del .249 ya tiene el certificado HTTPS del dominio; solo hay que
agregarle una ruta y levantar el backend como contenedor.

> Todos los comandos del PC se ejecutan en PowerShell o Git Bash desde
> `c:\Users\skyen\Desktop\PEDIDOS\api`. Reemplaza `USUARIO` por el usuario SSH
> real del servidor 192.168.2.249.

## Paso 1 — Copiar los archivos al servidor (desde este PC)

```bash
ssh USUARIO@192.168.2.249 "mkdir -p /opt/pedidos-backend"
scp server.js package.json package-lock.json .env deploy/Dockerfile deploy/docker-compose.yml USUARIO@192.168.2.249:/opt/pedidos-backend/
```

(Si no existe `package-lock.json`, omítelo del comando.)

## Paso 2 — Construir y levantar el contenedor (por SSH)

```bash
ssh USUARIO@192.168.2.249
cd /opt/pedidos-backend
docker compose up -d --build     # si falla, probar: docker-compose up -d --build
curl http://localhost:3000/api/test
```

Debe responder: `{"success":true,"message":"🚀 API SkyPagos funcionando correctamente",...}`

Verificar también desde el PC: `http://192.168.2.249:3000/api/test`

## Paso 3 — Identificar el reverse proxy del servidor

```bash
docker ps
```

Buscar un contenedor tipo `caddy`, `nginx`, `nginx-proxy-manager`, `traefik`
o `pangolin`. Según cuál sea, aplicar UNA de las secciones siguientes.

### Si es Caddy

Editar el Caddyfile (suele estar montado como volumen; verlo con
`docker inspect <contenedor> | grep -A5 Mounts`). Dentro del bloque del sitio
`pedidos.oral-plus.com` agregar ANTES de las demás rutas:

```
handle_path /pedidos-api/* {
    reverse_proxy 192.168.2.249:3000
}
```

Recargar: `docker exec <contenedor> caddy reload --config /etc/caddy/Caddyfile`

### Si es Nginx (o Nginx Proxy Manager)

En el server block de `pedidos.oral-plus.com` agregar:

```nginx
location /pedidos-api/ {
    proxy_pass http://192.168.2.249:3000/;   # la barra final quita el prefijo
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

En NPM: Hosts → pedidos.oral-plus.com → pestaña "Custom locations" no quita
prefijos, así que usar la pestaña "Advanced" y pegar el bloque de arriba.
Recargar: `docker exec <contenedor> nginx -s reload`

### Si es Traefik

Agregar al contenedor `pedidos-backend` (en su docker-compose.yml) estas
labels y conectarlo a la red de Traefik:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.pedidosapi.rule=Host(`pedidos.oral-plus.com`) && PathPrefix(`/pedidos-api`)
      - traefik.http.routers.pedidosapi.tls=true
      - traefik.http.middlewares.pedidosstrip.stripprefix.prefixes=/pedidos-api
      - traefik.http.routers.pedidosapi.middlewares=pedidosstrip
      - traefik.http.services.pedidosapi.loadbalancer.server.port=3000
```

Luego `docker compose up -d` de nuevo.

## Paso 4 — Prueba final desde internet

Desde cualquier red (o con datos móviles):

```bash
curl https://pedidos.oral-plus.com/pedidos-api/api/test
```

Debe responder el JSON de "API SkyPagos". Si responde 404 HTML, la ruta del
proxy no quedó bien.

## Paso 5 — Instalar el APK nuevo en los teléfonos

El APK recompilado (con la URL pública de primera en la lista) queda en:
`build\app\outputs\flutter-apk\app-release.apk`

La app prueba las URLs en este orden:
1. `https://pedidos.oral-plus.com/pedidos-api` (funciona en cualquier red)
2. `http://192.168.2.249:3000` (LAN directa, por si se cae el internet)
3. `http://192.168.2.73:3000` (PC de desarrollo, fallback temporal)

## Notas

- El contenedor se conecta al SQL Server de `192.168.2.244:1433` (bases
  SkyPagos y Pedidos); desde el .249 hay acceso directo por LAN.
- `restart: always` hace que el backend arranque solo si se reinicia el
  servidor.
- No se tocó ni el router ni el DNS: se reutiliza el port-forward 443 → .249
  que ya existía para la API SAP.
- Cuando el contenedor esté estable, el `node server.js` del PC de desarrollo
  ya no es necesario para producción.
