# PEDIDOS - Oral-Plus

Aplicación móvil para la fuerza de ventas de Oral-Plus: rutero, visitas a clientes,
toma de pedidos, recaudos y catálogo de productos. Incluye el backend que la soporta.

Autor: Steven Villamizar Mendoza (Sistemas, Oral-Plus).

## Estructura

- `lib/` - Aplicación Flutter (pantallas, servicios, modelos, widgets).
- `api/` - Backend Node.js (Express + SQL Server) de la app de pedidos.
  - `server.js` y `modules/` - Código del servidor.
  - `deploy/` - Dockerfile, docker-compose e instrucciones de despliegue.
  - `sql/` - Scripts de creación de las bases de datos.
  - `.env` - Configuración con credenciales (no se versiona).
- `assets/` - Imágenes del catálogo, logos y video de inicio.

## Requisitos

- Flutter 3.x / Dart 3.x
- Node.js 18 o superior (backend)
- SQL Server con las bases SkyPagos, Pedidos, RBOSKY3 (SAP) y Ruta

## Ejecutar la app

```bash
flutter pub get
flutter run
```

APK de producción:

```bash
flutter build apk --release
```

## Ejecutar el backend

```bash
cd api
npm install
node server.js
```

El servidor escucha en el puerto 3000. Prueba: `http://localhost:3000/api/test`.
En producción se publica en `https://gestores-api.oral-plus.com` (ver `api/deploy/README-DESPLIEGUE.md`).

## Licencia

Proyecto privado de Oral-Plus. Todos los derechos reservados.
