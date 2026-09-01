
const multer = require("multer")
const sharp = require("sharp")

const LADO_MAX = 1600
const CALIDAD = 80
const ORIGENES = new Set(["recaudo", "visita", "gestion"])

let tablaLista = false

async function ensureTabla(pool) {
  if (tablaLista) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'evidencias_archivos')
    CREATE TABLE dbo.evidencias_archivos (
      id              INT IDENTITY(1,1) PRIMARY KEY,
      origen          NVARCHAR(20)   NOT NULL,
      numero_recaudo  NVARCHAR(60)   NULL,
      numero_pedido   NVARCHAR(50)   NULL,
      cliente_id      NVARCHAR(50)   NULL,
      vendedor_id     INT            NULL,
      vendedor_nombre NVARCHAR(255)  NULL,
      contenido       VARBINARY(MAX) NOT NULL,
      mime            NVARCHAR(40)   NOT NULL CONSTRAINT DF_evid_mime DEFAULT ('image/webp'),
      tamano          INT            NOT NULL,
      ancho           INT            NULL,
      alto            INT            NULL,
      fecha           DATETIME       NOT NULL CONSTRAINT DF_evid_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_evid_recaudo' AND object_id = OBJECT_ID('dbo.evidencias_archivos'))
      CREATE INDEX IX_evid_recaudo ON dbo.evidencias_archivos(numero_recaudo);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_evid_cliente' AND object_id = OBJECT_ID('dbo.evidencias_archivos'))
      CREATE INDEX IX_evid_cliente ON dbo.evidencias_archivos(cliente_id, fecha DESC);
  `)
  tablaLista = true
}

async function procesar(buffer) {
  const { data, info } = await sharp(buffer)
    .rotate()
    .resize(LADO_MAX, LADO_MAX, { fit: "inside", withoutEnlargement: true })
    .webp({ quality: CALIDAD })
    .toBuffer({ resolveWithObject: true })
  return { contenido: data, ancho: info.width, alto: info.height }
}

function registrarRutas(app, { requireAuth, getPedidosPool, sql, log }) {
  const subida = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 12 * 1024 * 1024, files: 1 },
  })

  app.post("/api/evidencias", requireAuth, subida.single("foto"), async (req, res) => {
    try {
      const origen = (req.body.origen || "").toString().trim().toLowerCase()
      if (!ORIGENES.has(origen)) {
        return res.status(400).json({ success: false, message: "Origen inválido: usa recaudo, visita o gestion" })
      }
      if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
        return res.status(400).json({ success: false, message: "Adjunta la imagen en el campo 'foto'" })
      }

      const numeroRecaudo = (req.body.numeroRecaudo || "").toString().trim() || null
      const numeroPedido = (req.body.numeroPedido || "").toString().trim() || null
      const clienteId = (req.body.clienteId || "").toString().trim() || null
      const vendedorId = Number.isInteger(Number(req.user && req.user.userId)) ? Number(req.user.userId) : null
      const vendedorNombre = ((req.user && req.user.nombre) || "").toString().trim() || null

      const { contenido, ancho, alto } = await procesar(req.file.buffer)

      const pool = getPedidosPool()
      await ensureTabla(pool)
      const r = await pool
        .request()
        .input("origen", sql.NVarChar, origen)
        .input("numRec", sql.NVarChar, numeroRecaudo)
        .input("numPed", sql.NVarChar, numeroPedido)
        .input("cliente", sql.NVarChar, clienteId)
        .input("vendId", sql.Int, vendedorId)
        .input("vendNom", sql.NVarChar, vendedorNombre)
        .input("contenido", sql.VarBinary(sql.MAX), contenido)
        .input("tamano", sql.Int, contenido.length)
        .input("ancho", sql.Int, ancho)
        .input("alto", sql.Int, alto)
        .query(`
          INSERT INTO dbo.evidencias_archivos
            (origen, numero_recaudo, numero_pedido, cliente_id, vendedor_id, vendedor_nombre, contenido, tamano, ancho, alto)
          OUTPUT INSERTED.id
          VALUES (@origen, @numRec, @numPed, @cliente, @vendId, @vendNom, @contenido, @tamano, @ancho, @alto)
        `)

      const id = r.recordset[0].id
      log.info(`Evidencia #${id} ${origen} cliente ${clienteId || "-"} recaudo ${numeroRecaudo || "-"} pedido ${numeroPedido || "-"} ${contenido.length} bytes vend ${vendedorId != null ? vendedorId : "-"}`)
      res.json({ success: true, message: "Evidencia guardada", data: { id, tamano: contenido.length } })
    } catch (error) {
      log.error("Error guardando evidencia:", error.message)
      res.status(500).json({ success: false, message: "No se pudo guardar la evidencia" })
    }
  })

  app.get("/api/evidencias", requireAuth, async (req, res) => {
    try {
      const numeroRecaudo = (req.query.numeroRecaudo || "").toString().trim()
      const clienteId = (req.query.clienteId || "").toString().trim()
      const numeroPedido = (req.query.numeroPedido || "").toString().trim()
      if (!numeroRecaudo && !clienteId && !numeroPedido) {
        return res.status(400).json({ success: false, message: "Filtra por numeroRecaudo, clienteId o numeroPedido", data: [] })
      }

      const pool = getPedidosPool()
      await ensureTabla(pool)
      const reqDb = pool.request()
      const filtros = []
      if (numeroRecaudo) {
        filtros.push("numero_recaudo = @numRec")
        reqDb.input("numRec", sql.NVarChar, numeroRecaudo)
      }
      if (clienteId) {
        filtros.push("cliente_id = @cliente")
        reqDb.input("cliente", sql.NVarChar, clienteId)
      }
      if (numeroPedido) {
        filtros.push("numero_pedido = @numPed")
        reqDb.input("numPed", sql.NVarChar, numeroPedido)
      }
      const r = await reqDb.query(`
        SELECT TOP 200 id, origen, numero_recaudo, numero_pedido, cliente_id,
               vendedor_id, vendedor_nombre, mime, tamano, ancho, alto,
               CONVERT(VARCHAR(19), fecha, 120) AS fecha
        FROM dbo.evidencias_archivos
        WHERE ${filtros.join(" AND ")}
        ORDER BY fecha DESC, id DESC
      `)
      res.json({ success: true, data: r.recordset, total: r.recordset.length })
    } catch (error) {
      log.error("Error listando evidencias:", error.message)
      res.status(500).json({ success: false, message: "No se pudieron consultar las evidencias", data: [] })
    }
  })

  app.get("/api/evidencias/:id/foto", requireAuth, async (req, res) => {
    try {
      const id = Number.parseInt(req.params.id, 10)
      if (Number.isNaN(id)) return res.status(400).json({ success: false, message: "Id inválido" })

      const pool = getPedidosPool()
      await ensureTabla(pool)
      const r = await pool
        .request()
        .input("id", sql.Int, id)
        .query("SELECT contenido, mime FROM dbo.evidencias_archivos WHERE id = @id")
      if (r.recordset.length === 0) {
        return res.status(404).json({ success: false, message: "Evidencia no encontrada" })
      }
      res.set("Cache-Control", "private, max-age=86400")
      res.type(r.recordset[0].mime)
      res.send(r.recordset[0].contenido)
    } catch (error) {
      log.error("Error entregando evidencia:", error.message)
      res.status(500).json({ success: false, message: "No se pudo leer la evidencia" })
    }
  })
}

module.exports = { registrarRutas, ensureTabla }
