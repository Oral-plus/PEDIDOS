# Pruebas de integración del backend

Se corren contra un backend en marcha y las bases de datos reales que indique
`api/.env` (Pedidos, Ruta, SkyPagos y lectura de SAP). No usan simulaciones:
verifican lo mismo que vería la app.

## Cómo correrlas

```bash
cd api
node server.js            # en otra terminal, o el backend que ya esté arriba
npm run test:integracion  # las tres suites, en orden
```

Contra otro servidor (por ejemplo el túnel de pruebas o producción):

```bash
API_URL=https://mi-tunel.trycloudflare.com npm run test:integracion
node test/integracion/seguridad.js   # una sola suite
```

## Qué verifica cada suite

- `seguridad.js`: las 32 rutas de datos responden 401 sin sesión; `/api/test` y
  `/api/health` siguen abiertas; el login sin ID de servicio se rechaza; un
  dispositivo nuevo queda pendiente y uno activado entra; `/api/auth/register`
  solo para Soporte; al desactivar el dispositivo la sesión cae.
- `sesion.js`: credenciales incorrectas (401 con mensaje); token con registro
  (jti) y vencimiento de 12 h; catálogo exige cliente (400) y cliente inexistente
  (404); precios solo por la lista del cliente (lista 6 vs 43, sin respaldo a la
  lista 1); sin stock sigue disponible; logout revoca el token; tokens sin
  registro, vencidos o inventados reciben 401.
- `catalogo.js`: catálogo desde el Service Layer (usuario `manager`), más de 200
  artículos, categorías, ETag/304, imágenes desde la BD con caché larga, subida de
  foto por Soporte con paridad byte a byte frente a la migración, y limpieza.

## Lo que escriben en la base de datos

Filas temporales que cada suite borra al terminar: dispositivos
`SVC-PRUEBA-SEGURIDAD`, `SVC-PRUEBA-SESION` y `SVC-PRUEBA-CATALOGO`, sesiones del
vendedor `SKV18` (quedan cerradas con motivo `prueba`/`logout`) y la foto de
prueba del artículo `50360269`. No crean pedidos, recaudos ni visitas.

Usuario de prueba: `SKV18` (vendedor). La suite de catálogo necesita además un
usuario de Soporte TI: toma el primero de `SOPORTE_USUARIOS` del `.env`.
