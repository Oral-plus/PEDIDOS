// Caché compartida del backend sobre Redis.
//
// Se usa SOLO para lecturas repetidas y caras cuyo dato tolera unos segundos de
// desfase (hoy: el estado del talonario, que la app consulta cada vez que abre
// la pantalla de pago). Nunca se cachean importes, documentos ni el consecutivo
// que se asigna: eso va siempre a la base dentro de la transacción.
//
// Degradación elegante: si Redis no está configurado o no responde, el backend
// sigue trabajando contra la base (la caché simplemente no acierta). Así el
// despliegue del proveedor no depende de Redis para funcionar.

// La configuración se lee al iniciar, no al cargar el módulo: server.js hace
// dotenv.config() después de sus require, así que aquí aún no estaría cargada.
const url = () => (process.env.REDIS_URL || "").trim()
const prefijo = () => (process.env.REDIS_PREFIJO || "pedidos:").trim()

let cliente = null
let estado = "sin iniciar"
let avisado = false
const log = console

function iniciar() {
  const REDIS_URL = url()
  if (!REDIS_URL) {
    estado = "deshabilitado"
    return null
  }
  if (cliente) return cliente
  try {
    const { createClient } = require("redis")
    cliente = createClient({
      url: REDIS_URL,
      socket: {
        connectTimeout: 3000,
        // Tres reintentos con espera creciente; después se deja de insistir
        // para no llenar el log ni gastar recursos si Redis no está.
        reconnectStrategy: (intentos) => (intentos > 3 ? false : Math.min(intentos * 500, 2000)),
      },
    })
    cliente.on("error", (e) => {
      estado = "sin conexión"
      if (!avisado) {
        log.error("Redis no disponible, se sigue sin caché:", e.message)
        avisado = true
      }
    })
    cliente.on("ready", () => {
      estado = "conectado"
      avisado = false
      log.log(`Redis conectado (${REDIS_URL})`)
    })
    cliente.connect().catch(() => {})
  } catch (e) {
    estado = "sin cliente"
    log.error("No se pudo iniciar Redis:", e.message)
    cliente = null
  }
  return cliente
}

const listo = () => Boolean(cliente && cliente.isReady)
const clave = (k) => `${prefijo()}${k}`

// Devuelve el valor cacheado o null. Un fallo de Redis nunca rompe la petición.
async function obtener(k) {
  if (!listo()) return null
  try {
    const v = await cliente.get(clave(k))
    return v ? JSON.parse(v) : null
  } catch (_) {
    return null
  }
}

// Guarda con TTL en segundos (obligatorio: nada se queda para siempre).
async function guardar(k, valor, ttlSegundos) {
  if (!listo() || !(ttlSegundos > 0)) return false
  try {
    await cliente.set(clave(k), JSON.stringify(valor), { EX: Math.ceil(ttlSegundos) })
    return true
  } catch (_) {
    return false
  }
}

async function invalidar(k) {
  if (!listo()) return false
  try {
    await cliente.del(clave(k))
    return true
  } catch (_) {
    return false
  }
}

async function cerrar() {
  if (!cliente) return
  try { await cliente.quit() } catch (_) {}
  cliente = null
  estado = "cerrado"
}

module.exports = { iniciar, obtener, guardar, invalidar, cerrar, disponible: listo, estado: () => estado }
