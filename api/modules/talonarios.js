
const cache = require("./cache")

const CAUSALES = ["Deterioro", "Daño por mal manejo"]

const CACHE_TTL_SEG = 60
const claveCache = (prefijo) => `talonario:siguiente:${prefijo.toUpperCase()}`

async function invalidarCache(prefijo) {
  if (!prefijo) return false
  return cache.invalidar(claveCache(prefijo))
}

function prefijoDeSesion(decoded) {
  if (!decoded) return null
  if (decoded.tipo === "vendedor" && decoded.userId != null) return `SKV${decoded.userId}`.toUpperCase()
  return null
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
        numero          BIGINT        NOT NULL,
        prefijo         NVARCHAR(20)  NULL,
        rango_inicial   BIGINT        NULL,
        rango_final     BIGINT        NULL,
        causal          NVARCHAR(100) NOT NULL,
        observaciones   NVARCHAR(1000) NULL,
        usuario_codigo  NVARCHAR(60)  NULL,
        usuario_nombre  NVARCHAR(255) NULL,
        estado          NVARCHAR(20)  NOT NULL CONSTRAINT DF_talcanc_estado DEFAULT ('CANCELADO'),
        fecha           DATETIME      NOT NULL CONSTRAINT DF_talcanc_fecha DEFAULT (GETDATE()),
        CONSTRAINT FK_talcanc_talonario FOREIGN KEY (talonario_id) REFERENCES dbo.TALONARIO(id),
        CONSTRAINT UQ_talcanc_unidad UNIQUE (talonario_id, numero)
      );
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='numero' AND Object_ID=Object_ID('dbo.talonarios_cancelaciones'))
        ALTER TABLE dbo.talonarios_cancelaciones ADD numero BIGINT NULL;
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='observaciones' AND Object_ID=Object_ID('dbo.talonarios_cancelaciones'))
        ALTER TABLE dbo.talonarios_cancelaciones ADD observaciones NVARCHAR(1000) NULL;
      IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='estado' AND Object_ID=Object_ID('dbo.talonarios_cancelaciones'))
        ALTER TABLE dbo.talonarios_cancelaciones ADD estado NVARCHAR(20) NOT NULL CONSTRAINT DF_talcanc_estado DEFAULT ('CANCELADO');
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_talcanc_talonario')
        CREATE INDEX IX_talcanc_talonario ON dbo.talonarios_cancelaciones(talonario_id, numero);
      IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='recaudos' AND COLUMN_NAME='recibo_talonario_id')
        ALTER TABLE dbo.recaudos ADD recibo_talonario_id INT NULL;
      IF OBJECT_ID('dbo.evidencias_archivos') IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='cancelacion_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
        ALTER TABLE dbo.evidencias_archivos ADD cancelacion_id INT NULL;
    END
  `)
  await pool.request().query(`
    IF OBJECT_ID('dbo.talonarios_cancelaciones') IS NOT NULL BEGIN
      UPDATE c SET numero = ISNULL((SELECT MAX(r.recibo_caja) FROM dbo.recaudos r WHERE r.recibo_talonario_id = c.talonario_id), t.rango_inicial - 1) + 1
      FROM dbo.talonarios_cancelaciones c JOIN dbo.TALONARIO t ON t.id = c.talonario_id
      WHERE c.numero IS NULL;
      UPDATE t SET estado = 'ACTIVO' FROM dbo.TALONARIO t WHERE t.estado = 'CANCELADO';
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='UQ_talcanc_unidad')
         AND NOT EXISTS (SELECT talonario_id, numero FROM dbo.talonarios_cancelaciones GROUP BY talonario_id, numero HAVING COUNT(*) > 1)
        CREATE UNIQUE INDEX UQ_talcanc_unidad ON dbo.talonarios_cancelaciones(talonario_id, numero);
    END
  `)
  await pool.request().query(`
    IF OBJECT_ID('dbo.evidencias_archivos') IS NOT NULL
       AND EXISTS (SELECT 1 FROM sys.columns WHERE Name='cancelacion_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_evid_cancelacion')
      ALTER TABLE dbo.evidencias_archivos
        ADD CONSTRAINT FK_evid_cancelacion FOREIGN KEY (cancelacion_id) REFERENCES dbo.talonarios_cancelaciones(id) ON DELETE CASCADE;
  `)
  await pool.request().query(`
    IF OBJECT_ID('dbo.TALONARIO') IS NOT NULL
      UPDATE r SET recibo_talonario_id = t.id
      FROM dbo.recaudos r
      JOIN dbo.TALONARIO t ON UPPER(t.prefijo) = UPPER(r.recibo_prefijo)
      WHERE r.recibo_talonario_id IS NULL AND r.recibo_caja IS NOT NULL
        AND r.recibo_caja BETWEEN t.rango_inicial AND t.rango_final;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_recaudos_talonario' AND object_id = OBJECT_ID('dbo.recaudos'))
      CREATE INDEX IX_recaudos_talonario ON dbo.recaudos(recibo_talonario_id, recibo_caja);
  `)
  estructurasListas = true
}

async function talonariosActivos(hacerRequest, sql, prefijo) {
  const r = await hacerRequest()
    .input("p", sql.NVarChar, prefijo)
    .query(`
      SELECT t.id, t.prefijo, t.tipo_recibo, t.rango_inicial, t.rango_final, t.estado,
        (SELECT MAX(u) FROM (
           SELECT MAX(recibo_caja) AS u FROM dbo.recaudos WHERE recibo_talonario_id = t.id
           UNION ALL
           SELECT MAX(numero) FROM dbo.talonarios_cancelaciones WHERE talonario_id = t.id
        ) x) AS ultimo
      FROM dbo.TALONARIO t WITH (UPDLOCK, HOLDLOCK)
      WHERE UPPER(t.prefijo) = @p AND t.estado = 'ACTIVO'
      ORDER BY t.rango_inicial ASC, t.id ASC
    `)
  return r.recordset
}

function proyectar(t) {
  const ini = Number(t.rango_inicial) || 0
  const fin = Number(t.rango_final) || 0
  const ultimo = t.ultimo == null ? null : Number(t.ultimo)
  const siguiente = ultimo == null || ultimo < ini ? ini : ultimo + 1
  const agotado = siguiente > fin
  return {
    talonarioId: t.id,
    prefijo: (t.prefijo || "").toString().trim(),
    tipoRecibo: (t.tipo_recibo || "RECIBO DE CAJA").toString().trim(),
    rangoInicial: ini,
    rangoFinal: fin,
    unidades: fin - ini + 1,
    siguiente: agotado ? null : siguiente,
    agotado,
    disponibles: agotado ? 0 : fin - siguiente + 1,
  }
}

async function talonarioEnCurso(hacerRequest, sql, prefijo) {
  const lista = await talonariosActivos(hacerRequest, sql, prefijo)
  if (lista.length === 0) return null
  const proyectados = lista.map(proyectar)
  return proyectados.find((p) => !p.agotado) || proyectados[proyectados.length - 1]
}

const cacheable = (data) => Boolean(data && !data.sinTalonario && !data.agotado && data.siguiente != null)

async function consultarSiguiente(getPool, sql, prefijo) {
  const k = claveCache(prefijo)
  const enCache = await cache.obtener(k)
  if (enCache) return { ...enCache, deCache: true }
  const t = await talonarioEnCurso(() => getPool().request(), sql, prefijo)
  const data = t || { sinTalonario: true }
  if (cacheable(data)) await cache.guardar(k, data, CACHE_TTL_SEG)
  return data
}

async function asignar(hacerRequestTx, sql, decoded) {
  const prefijo = prefijoDeSesion(decoded)
  if (!prefijo) return { reciboCaja: null, reciboPrefijo: null, talonarioId: null }
  const t = await talonarioEnCurso(hacerRequestTx, sql, prefijo)
  if (!t || t.siguiente == null) {
    const err = new Error(t
      ? `No se puede realizar el pago: el talonario ${t.prefijo} (${t.rangoInicial}-${t.rangoFinal}) no tiene unidades disponibles. Solicita un talonario nuevo a Sistemas.`
      : "No se puede realizar el pago sin talonario asignado. Solicita un talonario a Sistemas.")
    err.sinTalonario = true
    err.agotado = Boolean(t)
    throw err
  }
  return { reciboCaja: t.siguiente, reciboPrefijo: t.prefijo, talonarioId: t.talonarioId, prefijo }
}

async function cancelarUnidad(pool, sql, decoded, { causal, observaciones, evidencia } = {}) {
  const prefijo = prefijoDeSesion(decoded)
  if (!prefijo) return { status: 400, message: "Esta sesión no maneja talonario (solo los gestores cobran cartera)" }
  const causalLimpia = (causal || "").toString().trim()
  if (!causalLimpia) {
    return { status: 400, message: "Selecciona la causal de cancelación del recibo" }
  }
  if (!CAUSALES.some((c) => c.toLowerCase() === causalLimpia.toLowerCase())) {
    return { status: 400, message: `Causal inválida. Usa: ${CAUSALES.join(" o ")}` }
  }
  const obs = (observaciones || "").toString().trim().slice(0, 1000)

  const transaction = pool.transaction()
  await transaction.begin()
  let cancelacionId = null
  let t = null
  try {
    t = await talonarioEnCurso(() => transaction.request(), sql, prefijo)
    if (!t) {
      await transaction.rollback()
      return { status: 404, message: "No tienes un talonario asignado" }
    }
    if (t.siguiente == null) {
      await transaction.rollback()
      return { status: 409, message: `El talonario ${t.prefijo} (${t.rangoInicial}-${t.rangoFinal}) no tiene unidades disponibles para cancelar` }
    }
    const ins = await transaction.request()
      .input("tid", sql.Int, t.talonarioId)
      .input("num", sql.BigInt, t.siguiente)
      .input("pref", sql.NVarChar, t.prefijo)
      .input("ini", sql.BigInt, t.rangoInicial)
      .input("fin", sql.BigInt, t.rangoFinal)
      .input("causal", sql.NVarChar, causalLimpia)
      .input("obs", sql.NVarChar, obs || null)
      .input("uc", sql.NVarChar, String(decoded.userId != null ? decoded.userId : decoded.documento || ""))
      .input("un", sql.NVarChar, (decoded.nombre || "").toString())
      .query(`
        INSERT INTO dbo.talonarios_cancelaciones
          (talonario_id, numero, prefijo, rango_inicial, rango_final, causal, observaciones, usuario_codigo, usuario_nombre, estado)
        OUTPUT INSERTED.id
        VALUES (@tid, @num, @pref, @ini, @fin, @causal, @obs, @uc, @un, 'CANCELADO')
      `)
    cancelacionId = ins.recordset[0].id

    if (evidencia && evidencia.contenido && evidencia.contenido.length > 0) {
      await transaction.request()
        .input("origen", sql.NVarChar, "talonario")
        .input("vendId", sql.Int, decoded.userId != null ? Number(decoded.userId) : null)
        .input("vendNom", sql.NVarChar, (decoded.nombre || "").toString() || null)
        .input("cancelacionId", sql.Int, cancelacionId)
        .input("contenido", sql.VarBinary(sql.MAX), evidencia.contenido)
        .input("tamano", sql.Int, evidencia.contenido.length)
        .input("ancho", sql.Int, evidencia.ancho || null)
        .input("alto", sql.Int, evidencia.alto || null)
        .query(`
          INSERT INTO dbo.evidencias_archivos
            (origen, vendedor_id, vendedor_nombre, cancelacion_id, contenido, tamano, ancho, alto)
          VALUES (@origen, @vendId, @vendNom, @cancelacionId, @contenido, @tamano, @ancho, @alto)
        `)
    }
    await transaction.commit()
  } catch (e) {
    try { await transaction.rollback() } catch (_) {}
    throw e
  }

  await invalidarCache(prefijo)

  const enCurso = await talonarioEnCurso(() => pool.request(), sql, prefijo)
  return {
    status: 200,
    data: {
      cancelacionId,
      talonarioId: t.talonarioId,
      prefijo: t.prefijo,
      rangoInicial: t.rangoInicial,
      rangoFinal: t.rangoFinal,
      numeroCancelado: t.siguiente,
      causal: causalLimpia,
      observaciones: obs,
      evidencia: Boolean(evidencia && evidencia.contenido),
      estado: "CANCELADO",
      siguiente: enCurso && enCurso.siguiente != null ? enCurso : null,
    },
  }
}

function registrarRutas(app, { requireAuth, getPedidosPool, sql, subida, procesarImagen, log }) {
  const logger = log || console

  app.get("/api/talonarios/siguiente", requireAuth, async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      const prefijo = prefijoDeSesion(req.user)
      if (!prefijo) return res.json({ success: true, sinTalonario: true, aplica: false })
      const data = await consultarSiguiente(getPedidosPool, sql, prefijo)
      if (data.sinTalonario) return res.json({ success: true, sinTalonario: true, aplica: true, prefijo })
      res.json({ success: true, data, cache: cache.disponible() })
    } catch (error) {
      logger.error("Error consultando talonario:", error.message)
      res.status(500).json({ success: false, message: "No se pudo consultar el talonario" })
    }
  })

  app.get("/api/talonarios/causales", requireAuth, (req, res) => {
    res.json({ success: true, data: CAUSALES })
  })

  app.post("/api/talonarios/cancelar", requireAuth, subida.single("foto"), async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      let evidencia = null
      if (req.file && req.file.buffer && req.file.buffer.length > 0) {
        try {
          evidencia = await procesarImagen(req.file.buffer)
        } catch (e) {
          return res.status(400).json({ success: false, message: "La imagen de evidencia no se pudo procesar" })
        }
      }
      const b = req.body || {}
      const r = await cancelarUnidad(getPedidosPool(), sql, req.user || {}, {
        causal: b.causal,
        observaciones: b.observaciones,
        evidencia,
      })
      if (r.status !== 200) return res.status(r.status).json({ success: false, message: r.message })
      const d = r.data
      logger.log(`Recibo ${d.prefijo}-${d.numeroCancelado} cancelado por ${(req.user && req.user.nombre) || "?"}: ${d.causal}${d.evidencia ? " (con evidencia)" : ""}. Sigue ${d.siguiente ? `${d.siguiente.prefijo}-${d.siguiente.siguiente}` : "sin unidades disponibles"}`)
      res.json({
        success: true,
        message: d.siguiente
          ? `Recibo N° ${d.numeroCancelado} cancelado. Continúa con el recibo N° ${d.siguiente.siguiente}${d.siguiente.talonarioId !== d.talonarioId ? ` del talonario ${d.siguiente.rangoInicial}-${d.siguiente.rangoFinal}` : ""}.`
          : `Recibo N° ${d.numeroCancelado} cancelado. No quedan unidades disponibles: solicita un talonario nuevo a Sistemas para poder registrar pagos.`,
        data: d,
      })
    } catch (error) {
      logger.error("Error cancelando recibo del talonario:", error.message)
      res.status(500).json({ success: false, message: "No se pudo cancelar el recibo" })
    }
  })
}

module.exports = { CAUSALES, prefijoDeSesion, ensureEstructuras, consultarSiguiente, asignar, cancelarUnidad, invalidarCache, registrarRutas }
