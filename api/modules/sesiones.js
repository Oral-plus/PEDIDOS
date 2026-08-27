// Sesiones emitidas por el login. Cada token lleva un identificador (jti)
// registrado en dbo.sesiones (BD Pedidos); cerrar sesión marca la fila y el
// token deja de servir aunque no haya vencido. La duración máxima es de 12
// horas. Las dependencias (sql, jwt, pool) las inyecta server.js.

const crypto = require("crypto")

const HORAS_MAX = 12
const SEGUNDOS_MAX = HORAS_MAX * 3600

// "30m", "12h", "2d" o un número de segundos; null si no se entiende
function aSegundos(valor) {
  if (valor == null) return null
  const m = String(valor).trim().toLowerCase().match(/^(\d+)\s*(s|m|h|d)?$/)
  if (!m) return null
  const factor = { s: 1, m: 60, h: 3600, d: 86400 }[m[2] || "s"]
  return Number(m[1]) * factor
}

// Duración de la sesión en segundos: SESSION_TIMEOUT del .env sin pasar de 12 h
function duracionSesion(env) {
  const pedida = aSegundos(env.SESSION_TIMEOUT)
  if (!pedida || pedida <= 0) return SEGUNDOS_MAX
  return Math.min(pedida, SEGUNDOS_MAX)
}

async function ensureTabla(pool) {
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'sesiones')
    CREATE TABLE dbo.sesiones (
      id             INT IDENTITY(1,1) PRIMARY KEY,
      jti            NVARCHAR(40)  NOT NULL UNIQUE,
      usuario_codigo NVARCHAR(60)  NULL,
      usuario_nombre NVARCHAR(200) NULL,
      tipo           NVARCHAR(20)  NULL,
      rol            NVARCHAR(20)  NULL,
      id_servicio    NVARCHAR(60)  NULL,
      plataforma     NVARCHAR(40)  NULL,
      emitida        DATETIME NOT NULL CONSTRAINT DF_ses_emitida DEFAULT (GETDATE()),
      expira         DATETIME NOT NULL,
      cerrada        DATETIME NULL,
      cierre_motivo  NVARCHAR(40)  NULL
    );
  `)
  // Limpieza: sesiones vencidas hace más de 7 días
  await pool.request().query("DELETE FROM dbo.sesiones WHERE expira < DATEADD(day, -7, GETDATE())")
}

// Registra la sesión y devuelve el jti que debe viajar en el token
async function registrar(pool, sql, datos) {
  const jti = crypto.randomUUID()
  await pool
    .request()
    .input("jti", sql.NVarChar, jti)
    .input("cod", sql.NVarChar, datos.usuarioCodigo || null)
    .input("nom", sql.NVarChar, datos.usuarioNombre || null)
    .input("tipo", sql.NVarChar, datos.tipo || null)
    .input("rol", sql.NVarChar, datos.rol || null)
    .input("disp", sql.NVarChar, datos.idServicio || null)
    .input("plat", sql.NVarChar, datos.plataforma || null)
    .input("seg", sql.Int, datos.duracionSeg)
    .query(`
      INSERT INTO dbo.sesiones (jti, usuario_codigo, usuario_nombre, tipo, rol, id_servicio, plataforma, expira)
      VALUES (@jti, @cod, @nom, @tipo, @rol, @disp, @plat, DATEADD(second, @seg, GETDATE()))
    `)
  return jti
}

// Estado en caché un minuto: cerrar sesión corta el acceso casi de inmediato
// sin consultar la BD en cada petición
const ESTADO_TTL_MS = 60 * 1000
const CACHE_MAX = 5000
const cache = new Map()

async function estaActiva(pool, sql, jti) {
  const c = cache.get(jti)
  if (c && Date.now() < c.vence) return c.activa
  const r = await pool
    .request()
    .input("jti", sql.NVarChar, jti)
    .query("SELECT TOP 1 cerrada FROM dbo.sesiones WHERE jti = @jti")
  const activa = r.recordset.length > 0 && r.recordset[0].cerrada == null
  if (cache.size >= CACHE_MAX) cache.clear()
  cache.set(jti, { activa, vence: Date.now() + ESTADO_TTL_MS })
  return activa
}

async function cerrar(pool, sql, jti, motivo) {
  const r = await pool
    .request()
    .input("jti", sql.NVarChar, jti)
    .input("motivo", sql.NVarChar, motivo || "logout")
    .query("UPDATE dbo.sesiones SET cerrada = GETDATE(), cierre_motivo = @motivo WHERE jti = @jti AND cerrada IS NULL")
  cache.delete(jti)
  return r.rowsAffected[0] > 0
}

// Rechaza tokens de sesiones cerradas y tokens sin registro (emitidos por una
// versión anterior del servidor). Sin token pasa de largo: cada ruta decide.
function middleware(jwt, JWT_SECRET, getPool, sql, log) {
  return async (req, res, next) => {
    const h = req.headers.authorization
    if (!h || !h.startsWith("Bearer ")) return next()
    let decoded
    try {
      decoded = jwt.verify(h.slice(7), JWT_SECRET)
    } catch (_) {
      return next()
    }
    if (!decoded.jti) {
      return res.status(401).json({ success: false, sesionCerrada: true, message: "Sesión expirada: inicia sesión de nuevo" })
    }
    try {
      if (!(await estaActiva(getPool(), sql, decoded.jti))) {
        return res.status(401).json({ success: false, sesionCerrada: true, message: "Sesión cerrada: inicia sesión de nuevo" })
      }
    } catch (e) {
      // Sin BD no se bloquea: el token sigue firmado y con vencimiento
      if (log) log.error("No se pudo verificar la sesión:", e.message)
    }
    next()
  }
}

module.exports = { HORAS_MAX, aSegundos, duracionSesion, ensureTabla, registrar, estaActiva, cerrar, middleware }
