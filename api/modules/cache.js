
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

async function obtener(k) {
  if (!listo()) return null
  try {
    const v = await cliente.get(clave(k))
    return v ? JSON.parse(v) : null
  } catch (_) {
    return null
  }
}

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
