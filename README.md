# PEDIDOS - Oral-Plus

Aplicación móvil para la fuerza de ventas: rutero, visitas a clientes, toma de
pedidos, recaudos de cartera y catálogo de productos. Incluye el backend que la
soporta.

Autor: Steven Villamizar Mendoza (Sistemas, Oral-Plus).

## Estructura

- `lib/` — Aplicación Flutter.
  - `config/` — Configuración que llega al compilar (`--dart-define`).
  - `screens/`, `widgets/` — Interfaz.
  - `services/` — Cliente del backend, sesión y caché.
  - `models/`, `providers/`, `utils/` — Dominio y utilidades.
- `api/` — Backend Node.js (Express + SQL Server).
  - `server.js` — Rutas de clientes, pedidos, recaudos, visitas y evidencias.
  - `modules/` — Talonarios, dispositivos, sesiones, catálogo, evidencias y caché.
  - `test/integracion/` — Pruebas de aceptación contra un backend en marcha.
  - `sql/` — Scripts de referencia de la base de datos.
  - `Dockerfile`, `docker-compose.yml` — Contenedor del servicio y su caché.
  - `.env` — Configuración del entorno (no se versiona; viaja con la entrega).
- `assets/` — Logos e imágenes de la aplicación.
- `DESPLIEGUE.md` — Instalación y configuración en el servidor.

## Requisitos

- Flutter 3.x / Dart 3.x
- Node.js 18 o superior
- SQL Server con las bases de pagos, pedidos, rutas y lectura de SAP
- Redis (opcional; sin él el backend funciona igual)

## Desarrollo

Backend:

```bash
cd api
npm install
node server.js
```

Aplicación:

```bash
flutter pub get
flutter run --dart-define=API_URLS=http://ip-del-backend:3000
```

## Pruebas

```bash
cd api && npm run test:integracion   # backend, contra el servicio en marcha
flutter test                         # aplicación
```

## Despliegue

Ver [DESPLIEGUE.md](DESPLIEGUE.md). Ningún valor de entorno está en el código:
el backend se configura con variables de entorno y la app con `--dart-define`.

## Licencia

Proyecto privado de Oral-Plus. Todos los derechos reservados.
