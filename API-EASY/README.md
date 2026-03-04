# API-EASY

API REST en Node.js para gestión de rutas, clientes SAP y usuarios. Migrada desde la lógica PHP original del sistema de ruteros.

## Requisitos

- Node.js 18+
- SQL Server (base de datos `Ruta` y SAP)

## Instalación

```bash
npm install
```

## Configuración

Editar el archivo `.env` con los datos de conexión a tus bases de datos.

## Ejecución

```bash
# Producción
npm start

# Desarrollo (auto-reload)
npm run dev
```

## Endpoints

### Auth (público)
| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/api/auth/login` | Iniciar sesión (devuelve JWT) |
| POST | `/api/auth/register` | Registrar nuevo usuario |

### Usuarios (requiere JWT)
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/usuarios/perfil` | Obtener perfil del usuario actual |
| POST | `/api/usuarios/sync-sap` | Sincronizar nombre desde SAP |
| GET | `/api/usuarios/oslp-asociados` | Obtener vendedores OSLP asociados (solo COACH) |

### Clientes (requiere JWT)
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/clientes` | Obtener todos los clientes SAP |
| GET | `/api/clientes/no-asignados` | Clientes sin ruta activa (<15 días) |
| GET | `/api/clientes/proximos-revisitar` | Clientes entre 11-13 días desde última ruta |
| GET | `/api/clientes/:codigo` | Buscar cliente por CardCode |

### Rutas (requiere JWT)
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/rutas/dashboard` | Dashboard completo (estadísticas + datos) |
| GET | `/api/rutas/estadisticas` | Estadísticas del usuario |
| GET | `/api/rutas/activas` | Rutas activas (agrupadas por vendedor si es COACH) |
| POST | `/api/rutas/crear` | Crear nueva ruta |
| PUT | `/api/rutas/estado` | Actualizar estado de una ruta |
| GET | `/api/rutas/tareas` | Tareas pendientes |
| PUT | `/api/rutas/tareas/estado` | Actualizar estado de una tarea |

## Autenticación

Todas las rutas protegidas requieren el header:
```
Authorization: Bearer <token>
```

## Ejemplo de uso

```bash
# Login
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"usuario": "admin", "password": "123456"}'

# Obtener clientes (con token)
curl http://localhost:3000/api/clientes \
  -H "Authorization: Bearer <tu-token>"

# Dashboard completo
curl http://localhost:3000/api/rutas/dashboard \
  -H "Authorization: Bearer <tu-token>"
```
