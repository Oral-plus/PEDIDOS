# Despliegue del backend de pedidos (notas internas)

Documento de uso interno de Sistemas. El documento que se entrega al
proveedor es `INSTRUCCIONES-PROVEEDOR.md`, en esta misma carpeta.

Objetivo: que `https://gestores-api.oral-plus.com/*` llegue al backend
(`server.js`, puerto 3000) en el servidor `192.168.2.249`, para que la app
funcione desde cualquier red. Se usa un subdominio dedicado y no un prefijo de
ruta para no interferir con la API SAP que ya corre en `pedidos.oral-plus.com`.

## Paquete para el proveedor

Desde `api/`, el ZIP debe contener:

```
server.js  modules/  package.json  package-lock.json  .env
Dockerfile  docker-compose.yml  .dockerignore
test/integracion/  sql/  INSTRUCCIONES-PROVEEDOR.md
```

No van: `node_modules/`, `scripts/` (migración ya ejecutada), `deploy/` ni
los archivos heredados de otros sistemas (`Datos.js`, `invoice*.js`,
`server1.js`, `*.php`, `vercel.json`, `iniciar_api.cmd`).

Antes de enviar: probar el paquete descomprimido en limpio (`npm install
--omit=dev`, `node server.js`, `npm run test:integracion`) o con Docker
(`docker compose up -d --build` y `docker compose exec pedidos-backend node
test/integracion/run.js`).

## Despliegue directo por SSH (si no lo hace el proveedor)

```bash
ssh USUARIO@192.168.2.249 "mkdir -p /opt/pedidos-backend"
scp server.js package.json package-lock.json .env Dockerfile docker-compose.yml .dockerignore USUARIO@192.168.2.249:/opt/pedidos-backend/
scp -r modules test sql USUARIO@192.168.2.249:/opt/pedidos-backend/
ssh USUARIO@192.168.2.249
cd /opt/pedidos-backend
docker compose up -d --build
curl http://localhost:3000/api/test
```

Reverse proxy y DNS: los mismos pasos 1 y 3 de `INSTRUCCIONES-PROVEEDOR.md`.
Para saber qué proxy corre en el servidor: `docker ps` y buscar `caddy`,
`nginx`, `nginx-proxy-manager` o `traefik`.

## Después del despliegue

1. Verificar desde datos móviles: `curl https://gestores-api.oral-plus.com/api/test`.
2. Instalar el APK (`Desktop\PROYECTO VENTAS\PEDIDOS-app-release.apk`) en
   los teléfonos. La app intenta primero `https://gestores-api.oral-plus.com`
   y, si no responde, `http://192.168.2.249:3000` por LAN.
3. Cada teléfono queda pendiente de activación la primera vez: se activa desde
   la cuenta de Soporte TI en Mantenimiento > Dispositivos.
4. Todos los vendedores deben iniciar sesión de nuevo una vez (los tokens de
   la versión anterior ya no sirven).

## Pendientes de seguridad

- Reemplazar la cuenta `sa` del `.env` por el usuario `pedidos_app`
  (`sql/crear_usuario_pedidos_app.sql`, ejecutar en SSMS) y enviar el `.env`
  actualizado al proveedor.
- Crear en SAP un usuario de solo lectura para el Service Layer en lugar de
  `manager` y actualizar `SL_USER` y `SL_PASSWORD`.
