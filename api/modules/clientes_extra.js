
let tablaLista = false

async function ensureTabla(pool) {
  if (tablaLista) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'comentarios_clientes')
    CREATE TABLE dbo.comentarios_clientes (
      id              INT IDENTITY(1,1) PRIMARY KEY,
      cliente_id      NVARCHAR(50)   NOT NULL,
      usuario_codigo  NVARCHAR(60)   NULL,
      usuario_nombre  NVARCHAR(255)  NULL,
      comentario      NVARCHAR(2000) NOT NULL,
      fecha           DATETIME       NOT NULL CONSTRAINT DF_comentarios_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_comentarios_cliente_fecha' AND object_id = OBJECT_ID('dbo.comentarios_clientes'))
      CREATE INDEX IX_comentarios_cliente_fecha ON dbo.comentarios_clientes (cliente_id, fecha DESC);
  `)
  tablaLista = true
}

function filaComentario(r) {
  return {
    id: r.id,
    comentario: r.comentario,
    usuarioCodigo: r.usuario_codigo || "",
    usuarioNombre: r.usuario_nombre || "",
    fechaCreacion: r.fecha instanceof Date ? r.fecha.toISOString() : r.fecha,
  }
}

async function leerFreeText(sap, sql, cardCode) {
  const r = await sap.request()
    .input("c", sql.VarChar, cardCode)
    .query("SELECT CAST(Free_Text AS NVARCHAR(MAX)) AS texto FROM OCRD WHERE CardCode = @c")
  if (!r.recordset.length) return null
  return (r.recordset[0].texto || "").toString()
}

function registrarRutas(app, { requireAuth, getPedidosPool, connectSAP, sql, serviceLayer, limiteDesdeQuery, log }) {
  const logger = log || console

  app.get("/api/clientes/:codigo/comentarios", requireAuth, async (req, res) => {
    const cardCode = (req.params.codigo || "").toString().trim()
    try {
      const pool = getPedidosPool()
      await ensureTabla(pool)
      const filas = await pool.request()
        .input("c", sql.NVarChar, cardCode)
        .query(`
          SELECT TOP 200 id, cliente_id, usuario_codigo, usuario_nombre, comentario, fecha
          FROM dbo.comentarios_clientes WHERE cliente_id = @c ORDER BY fecha DESC, id DESC
        `)
      let freeText = ""
      try {
        freeText = (await leerFreeText(await connectSAP(), sql, cardCode)) || ""
      } catch (e) {
        logger.warn(`Free_Text de ${cardCode} no disponible: ${e.message}`)
      }
      res.json({ success: true, data: filas.recordset.map(filaComentario), total: filas.recordset.length, freeText })
    } catch (error) {
      logger.error("Error obteniendo comentarios:", error.message)
      res.status(500).json({ success: false, message: "Error al obtener los comentarios", data: [] })
    }
  })

  app.post("/api/clientes/:codigo/comentarios", requireAuth, async (req, res) => {
    const cardCode = (req.params.codigo || "").toString().trim()
    const texto = (req.body && req.body.comentario != null ? req.body.comentario : "").toString().trim()
    if (!cardCode || !texto) {
      return res.status(400).json({ success: false, message: "El comentario no puede estar vacío" })
    }
    if (texto.length > 2000) {
      return res.status(400).json({ success: false, message: "El comentario no puede superar 2000 caracteres" })
    }
    try {
      const pool = getPedidosPool()
      await ensureTabla(pool)
      const u = req.user || {}
      const r = await pool.request()
        .input("c", sql.NVarChar, cardCode)
        .input("uc", sql.NVarChar, String(u.userId != null ? u.userId : u.documento || ""))
        .input("un", sql.NVarChar, (u.nombre || "").toString())
        .input("t", sql.NVarChar, texto)
        .query(`
          INSERT INTO dbo.comentarios_clientes (cliente_id, usuario_codigo, usuario_nombre, comentario)
          OUTPUT INSERTED.id, INSERTED.cliente_id, INSERTED.usuario_codigo, INSERTED.usuario_nombre, INSERTED.comentario, INSERTED.fecha
          VALUES (@c, @uc, @un, @t)
        `)
      res.json({ success: true, data: filaComentario(r.recordset[0]) })
    } catch (error) {
      logger.error("Error guardando comentario:", error.message)
      res.status(500).json({ success: false, message: "No se pudo guardar el comentario" })
    }
  })

  app.put("/api/clientes/:codigo/free-text", requireAuth, async (req, res) => {
    const cardCode = (req.params.codigo || "").toString().trim()
    const texto = (req.body && req.body.texto != null ? req.body.texto : "").toString()
    if (!cardCode) return res.status(400).json({ success: false, message: "Cliente requerido" })
    if (texto.length > 2000) {
      return res.status(400).json({ success: false, message: "El texto no puede superar 2000 caracteres" })
    }
    if (!serviceLayer || !serviceLayer.configurado) {
      return res.status(503).json({ success: false, message: "El Service Layer de SAP no está configurado (SL_* en .env)" })
    }
    try {
      const sap = await connectSAP()
      const actual = await leerFreeText(sap, sql, cardCode)
      if (actual === null) return res.status(404).json({ success: false, message: "Cliente no encontrado en SAP" })
      if (actual !== texto) {
        await serviceLayer.enviar("PATCH", `/BusinessPartners('${encodeURIComponent(cardCode).replace(/'/g, "''")}')`, { FreeText: texto })
      }
      logger.log(`Free_Text de ${cardCode} actualizado por ${(req.user && req.user.nombre) || "?"}`)
      res.json({ success: true, freeText: texto })
    } catch (error) {
      logger.error("Error actualizando Free_Text:", error.message)
      res.status(502).json({ success: false, message: `No se pudo actualizar el texto en SAP: ${error.message}` })
    }
  })

  app.get("/api/clientes/:codigo/facturas-historico", requireAuth, async (req, res) => {
    const cardCode = (req.params.codigo || "").toString().trim()
    const limite = limiteDesdeQuery(req.query.limite || req.query.limit, 100, 1000)
    try {
      const sap = await connectSAP()
      const r = await sap.request()
        .input("c", sql.VarChar, cardCode)
        .input("limite", sql.Int, limite)
        .query(`
          SELECT TOP (@limite) T0.DocEntry, T0.DocNum, T0.NumAtCard, T0.DocStatus,
                 CONVERT(VARCHAR(10), T0.DocDate, 120)    AS docDate,
                 CONVERT(VARCHAR(10), T0.DocDueDate, 120) AS dueDate,
                 T0.DocTotal, T0.PaidToDate,
                 DATEDIFF(day, GETDATE(), T0.DocDueDate)  AS diasVencimiento
          FROM OINV T0
          WHERE T0.CardCode = @c AND T0.CANCELED = 'N'
          ORDER BY T0.DocDate DESC, T0.DocNum DESC
        `)
      const facturas = r.recordset.map((d) => {
        const total = Number.parseFloat(d.DocTotal) || 0
        const pagado = Number.parseFloat(d.PaidToDate) || 0
        const saldo = Math.max(0, total - pagado)
        const abierta = d.DocStatus === "O" && saldo > 0
        const estado = !abierta ? "PAGADA" : ((d.diasVencimiento || 0) < 0 ? "VENCIDA" : "ABIERTA")
        return {
          docEntry: d.DocEntry,
          docNum: d.DocNum,
          numero: (d.NumAtCard || `${d.DocNum}`).toString(),
          fecha: d.docDate,
          vencimiento: d.dueDate,
          total,
          pagado,
          saldo,
          diasVencimiento: d.diasVencimiento || 0,
          estado,
        }
      })
      const resumen = {
        facturas,
        total: facturas.length,
        pagadas: facturas.filter((f) => f.estado === "PAGADA").length,
        abiertas: facturas.filter((f) => f.estado !== "PAGADA").length,
        totalCompras: facturas.reduce((a, f) => a + f.total, 0),
        totalPagado: facturas.reduce((a, f) => a + f.pagado, 0),
        saldo: facturas.reduce((a, f) => a + f.saldo, 0),
      }
      res.json({ success: true, data: resumen })
    } catch (error) {
      logger.error("Error obteniendo histórico de facturas:", error.message)
      res.status(500).json({ success: false, message: "Error al obtener el histórico de facturas" })
    }
  })
}

module.exports = { registrarRutas, ensureTabla }
