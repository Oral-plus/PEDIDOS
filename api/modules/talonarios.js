// Talonarios de recibos de caja (dbo.TALONARIO).
//
// El prefijo del talonario es el usuario de inicio de sesión (SKVnn). Cada
// recaudo consume el consecutivo del talonario ACTIVO del usuario, dentro de
// su rango [rango_inicial, rango_final], sin repetirse.
//
// Cancelación: un talonario se cancela SOLO con una causal del catálogo; queda
// en estado CANCELADO (se conserva) y la cancelación se registra en
// dbo.talonarios_cancelaciones (talonario, causal, usuario, fecha). Un
// talonario cancelado no permite pagos. Los consecutivos se cuentan por
// talonario (recaudos.recibo_talonario_id), así que al asignar un talonario
// nuevo el rango arranca de cero aunque el cancelado haya consumido números.
//
// Caché (Redis): se cachea SOLO el estado del talonario que la app consulta al
// abrir la pantalla de pago (lectura repetida y barata de invalidar), con TTL
// corto. Se invalida en cuanto cambia el estado: al cancelar y al consumir un
// número. La asignación del consecutivo y la cancelación NUNCA leen de caché:
// van a la base con bloqueo de fila dentro de su transacción.

const cache = require("./cache")

const CAUSALES = ["Deterioro", "Daño por mal manejo"]

const CACHE_TTL_SEG = 60
const claveCache = (prefijo) => `talonario:siguiente:${prefijo.toUpperCase()}`

async function invalidarCache(prefijo) {
  if (!prefijo) return false
  return cache.invalidar(claveCache(prefijo))
}

// Usuario de la sesión -> prefijo del talonario (SKVnn para vendedores)
function prefijoDeSesion(decoded) {
  if (!decoded) return null
  if (decoded.tipo === "vendedor" && decoded.userId != null) return `SKV${decoded.userId}`.toUpperCase()
  const p = (decoded.documento || decoded.nombre || "").toString().trim().toUpperCase()
  return p || null
}

let estructurasListas = false
async function ensureEstructuras(pool) {
  if (estructurasListas) return
  await pool.request().query(`
    IF OBJECT_ID('dbo.TALONARIO') IS NOT NULL BEGIN
      IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'talonarios_cancelaciones')
      CREATE TABLE dbo.talonarios_cancelaciones (
        id INT IDENTITY(1,1) PRIMARY KEY,
        talonario_id    INT           NOT NULL,
        prefijo         NVARCHAR(20)  NULL,
        rango_inicial   BIGINT        NULL,
        rango_final     BIGINT        NULL,
        causal          NVARCHAR(100) NOT NULL,
        usuario_codigo  NVARCHAR(60)  NULL,
        usuario_nombre  NVARCHAR(255) NULL,
        estado_anterior NVARCHAR(20)  NULL,
        fecha           DATETIME      NOT NULL CONSTRAINT DF_talcanc_fecha DEFAULT (GETDATE()),
        CONSTRAINT FK_talcanc_talonario FOREIGN KEY (talonario_id) REFERENCES dbo.TALONARIO(id)
      );
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_talcanc_talonario')
        CREATE INDEX IX_talcanc_talonario ON dbo.talonarios_cancelaciones(talonario_id);
      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='recaudos' AND COLUMN_NAME='recibo_talonario_id')
        ALTER TABLE dbo.recaudos ADD recibo_talonario_id INT NULL;
    END
  `)
  // Los recibos ya asignados sin talonario_id se enlazan a su talonario por el
  // prefijo (una sola vez): así el conteo por talonario no repite números.
  await pool.request().query(`
    IF OBJECT_ID('dbo.TALONARIO') IS NOT NULL
      UPDATE r SET recibo_talonario_id = t.id
      FROM dbo.recaudos r
      JOIN dbo.TALONARIO t ON UPPER(t.prefijo) = UPPER(r.recibo_prefijo)
      WHERE r.recibo_talonario_id IS NULL AND r.recibo_caja IS NOT NULL
  `)
  await pool.request().query(`
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_recaudos_talonario' AND object_id = OBJECT_ID('dbo.recaudos'))
      CREATE INDEX IX_recaudos_talonario ON dbo.recaudos(recibo_talonario_id, recibo_caja);
  `)
  estructurasListas = true
}

// Talonario vigente del prefijo (el ACTIVO más reciente o, si no hay, el
// último CANCELADO con su causal). hacerRequest decide el contexto: con una
// request de transacción, el UPDLOCK serializa asignaciones y cancelaciones.
async function talonarioVigente(hacerRequest, sql, prefijo) {
  const r = await hacerRequest()
    .input("p", sql.NVarChar, prefijo)
    .query(`
      SELECT TOP 1 t.id, t.prefijo, t.tipo_recibo, t.rango_inicial, t.rango_final, t.estado,
        (SELECT MAX(recibo_caja) FROM dbo.recaudos WHERE recibo_talonario_id = t.id) AS ultimo,
        (SELECT TOP 1 c.causal FROM dbo.talonarios_cancelaciones c WHERE c.talonario_id = t.id ORDER BY c.id DESC) AS causal
      FROM dbo.TALONARIO t WITH (UPDLOCK, HOLDLOCK)
      WHERE UPPER(t.prefijo) = @p AND t.estado IN ('ACTIVO', 'CANCELADO')
      ORDER BY CASE WHEN t.estado = 'ACTIVO' THEN 0 ELSE 1 END, t.id DESC
    `)
  return r.recordset[0] || null
}

function proyectar(t) {
  const ini = Number(t.rango_inicial) || 0
  const fin = Number(t.rango_final) || 0
  const ultimo = t.ultimo == null ? null : Number(t.ultimo)
  const siguiente = ultimo == null || ultimo < ini ? ini : ultimo + 1
  const cancelado = t.estado === "CANCELADO"
  const agotado = !cancelado && siguiente > fin
  return {
    talonarioId: t.id,
    prefijo: (t.prefijo || "").toString().trim(),
    tipoRecibo: (t.tipo_recibo || "RECIBO DE CAJA").toString().trim(),
    estado: t.estado,
    rangoInicial: ini,
    rangoFinal: fin,
    siguiente: cancelado || agotado ? null : siguiente,
    agotado,
    cancelado,
    causalCancelacion: cancelado ? (t.causal || "").toString() : null,
    disponibles: cancelado || agotado ? 0 : fin - siguiente + 1,
  }
}

// Solo se cachea el camino feliz: talonario ACTIVO con número disponible. Los
// estados que bloquean (cancelado, agotado, sin talonario) NO se cachean, porque
// Sistemas asigna los talonarios directamente en la base y un estado viejo
// dejaría al gestor sin poder cobrar hasta que venza el TTL.
const cacheable = (data) => Boolean(data && !data.sinTalonario && !data.cancelado && !data.agotado && data.siguiente != null)

// Estado + siguiente número para el usuario. Lectura cacheada en Redis; si
// Redis no está disponible se consulta la base igual (solo se pierde el acierto).
async function consultarSiguiente(getPool, sql, prefijo) {
  const k = claveCache(prefijo)
  const enCache = await cache.obtener(k)
  if (enCache) return { ...enCache, deCache: true }
  const t = await talonarioVigente(() => getPool().request(), sql, prefijo)
  const data = t ? proyectar(t) : { sinTalonario: true }
  if (cacheable(data)) await cache.guardar(k, data, CACHE_TTL_SEG)
  return data
}

// Asignación del recibo dentro de la transacción del recaudo (sin caché).
// Lanza { pagoBloqueado } si el talonario del usuario está CANCELADO.
async function asignar(hacerRequestTx, sql, decoded) {
  const prefijo = prefijoDeSesion(decoded)
  if (!prefijo) return { reciboCaja: null, reciboPrefijo: null, talonarioId: null }
  const t = await talonarioVigente(hacerRequestTx, sql, prefijo)
  if (!t) return { reciboCaja: null, reciboPrefijo: null, talonarioId: null, prefijo }
  const p = proyectar(t)
  if (p.cancelado) {
    const err = new Error(`El talonario ${p.prefijo} está cancelado (${p.causalCancelacion || "sin causal registrada"}): no se pueden registrar pagos`)
    err.pagoBloqueado = true
    err.causal = p.causalCancelacion
    throw err
  }
  if (p.siguiente == null) return { reciboCaja: null, reciboPrefijo: null, talonarioId: p.talonarioId, prefijo }
  return { reciboCaja: p.siguiente, reciboPrefijo: p.prefijo, talonarioId: p.talonarioId, prefijo }
}

// Cancela el talonario ACTIVO del usuario con su causal (obligatoria y del
// catálogo). Todo o nada: cambio de estado + registro de la cancelación.
async function cancelar(pool, sql, decoded, causal) {
  const prefijo = prefijoDeSesion(decoded)
  if (!prefijo) return { status: 400, message: "Sesión sin usuario identificable" }
  const causalLimpia = (causal || "").toString().trim()
  if (!causalLimpia) {
    return { status: 400, message: "Selecciona la causal de cancelación del talonario" }
  }
  if (!CAUSALES.some((c) => c.toLowerCase() === causalLimpia.toLowerCase())) {
    return { status: 400, message: `Causal inválida. Usa: ${CAUSALES.join(" o ")}` }
  }

  const transaction = pool.transaction()
  await transaction.begin()
  try {
    const t = await talonarioVigente(() => transaction.request(), sql, prefijo)
    if (!t) {
      await transaction.rollback()
      return { status: 404, message: "No tienes un talonario asignado" }
    }
    if (t.estado === "CANCELADO") {
      await transaction.rollback()
      return { status: 409, message: `El talonario ya está cancelado (${t.causal || "sin causal registrada"})` }
    }
    await transaction.request()
      .input("id", sql.Int, t.id)
      .query("UPDATE dbo.TALONARIO SET estado = 'CANCELADO' WHERE id = @id AND estado = 'ACTIVO'")
    await transaction.request()
      .input("tid", sql.Int, t.id)
      .input("pref", sql.NVarChar, (t.prefijo || "").toString().trim())
      .input("ini", sql.BigInt, t.rango_inicial)
      .input("fin", sql.BigInt, t.rango_final)
      .input("causal", sql.NVarChar, causalLimpia)
      .input("uc", sql.NVarChar, String(decoded.userId != null ? decoded.userId : decoded.documento || ""))
      .input("un", sql.NVarChar, (decoded.nombre || "").toString())
      .query(`
        INSERT INTO dbo.talonarios_cancelaciones
          (talonario_id, prefijo, rango_inicial, rango_final, causal, usuario_codigo, usuario_nombre, estado_anterior)
        VALUES (@tid, @pref, @ini, @fin, @causal, @uc, @un, 'ACTIVO')
      `)
    await transaction.commit()
    // El estado cambió: la caché del talonario deja de valer de inmediato
    await invalidarCache(prefijo)
    return {
      status: 200,
      data: { talonarioId: t.id, prefijo: (t.prefijo || "").toString().trim(), causal: causalLimpia, estado: "CANCELADO" },
    }
  } catch (e) {
    try { await transaction.rollback() } catch (_) {}
    throw e
  }
}

function registrarRutas(app, { requireAuth, getPedidosPool, sql, log }) {
  const logger = log || console

  // Recibo de caja que le sigue al usuario (o el estado del talonario)
  app.get("/api/talonarios/siguiente", requireAuth, async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      const prefijo = prefijoDeSesion(req.user)
      if (!prefijo) return res.json({ success: true, sinTalonario: true })
      const data = await consultarSiguiente(getPedidosPool, sql, prefijo)
      if (data.sinTalonario) return res.json({ success: true, sinTalonario: true, prefijo })
      res.json({ success: true, data, cache: cache.disponible() })
    } catch (error) {
      logger.error("Error consultando talonario:", error.message)
      res.status(500).json({ success: false, message: "No se pudo consultar el talonario" })
    }
  })

  // Catálogo de causales (el mismo que valida el servidor)
  app.get("/api/talonarios/causales", requireAuth, (req, res) => {
    res.json({ success: true, data: CAUSALES })
  })

  // Cancelación con causal obligatoria
  app.post("/api/talonarios/cancelar", requireAuth, async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      const r = await cancelar(getPedidosPool(), sql, req.user || {}, req.body && req.body.causal)
      if (r.status !== 200) return res.status(r.status).json({ success: false, message: r.message })
      logger.log(`Talonario ${r.data.prefijo} (#${r.data.talonarioId}) cancelado por ${(req.user && req.user.nombre) || "?"}: ${r.data.causal}`)
      res.json({ success: true, message: "Talonario cancelado", data: r.data })
    } catch (error) {
      logger.error("Error cancelando talonario:", error.message)
      res.status(500).json({ success: false, message: "No se pudo cancelar el talonario" })
    }
  })
}

module.exports = { CAUSALES, prefijoDeSesion, ensureEstructuras, consultarSiguiente, asignar, cancelar, invalidarCache, registrarRutas }
