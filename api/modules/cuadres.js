const evidencias = require("./evidencias")

const FORMA_PAGO = "Efectivo"

let estructurasListas = false
async function ensureEstructuras(pool) {
  if (estructurasListas) return
  await evidencias.ensureTabla(pool)
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'cuadres_caja')
    CREATE TABLE dbo.cuadres_caja (
      id INT IDENTITY(1,1) PRIMARY KEY,
      recaudo_id      INT            NOT NULL,
      numero_recaudo  NVARCHAR(60)   NULL,
      recibo_caja     BIGINT         NULL,
      recibo_prefijo  NVARCHAR(20)   NULL,
      cliente_id      NVARCHAR(50)   NULL,
      cliente_nombre  NVARCHAR(255)  NULL,
      valor           DECIMAL(18,2)  NULL,
      banco           NVARCHAR(120)  NOT NULL,
      numero_recibo   NVARCHAR(120)  NOT NULL,
      observaciones   NVARCHAR(1000) NULL,
      usuario_codigo  NVARCHAR(60)   NULL,
      usuario_nombre  NVARCHAR(255)  NULL,
      fecha           DATETIME       NOT NULL CONSTRAINT DF_cuadres_fecha DEFAULT (GETDATE()),
      CONSTRAINT FK_cuadre_recaudo FOREIGN KEY (recaudo_id) REFERENCES dbo.recaudos(id) ON DELETE CASCADE,
      CONSTRAINT UQ_cuadre_recaudo UNIQUE (recaudo_id)
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_cuadres_usuario_fecha' AND object_id = OBJECT_ID('dbo.cuadres_caja'))
      CREATE INDEX IX_cuadres_usuario_fecha ON dbo.cuadres_caja(usuario_codigo, fecha DESC);
    IF OBJECT_ID('dbo.evidencias_archivos') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='cuadre_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
      ALTER TABLE dbo.evidencias_archivos ADD cuadre_id INT NULL;
  `)
  await pool.request().query(`
    IF OBJECT_ID('dbo.evidencias_archivos') IS NOT NULL
       AND EXISTS (SELECT 1 FROM sys.columns WHERE Name='cuadre_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_evid_cuadre')
      ALTER TABLE dbo.evidencias_archivos
        ADD CONSTRAINT FK_evid_cuadre FOREIGN KEY (cuadre_id) REFERENCES dbo.cuadres_caja(id);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_evid_cuadre' AND object_id = OBJECT_ID('dbo.evidencias_archivos'))
      CREATE INDEX IX_evid_cuadre ON dbo.evidencias_archivos(cuadre_id);
  `)
  estructurasListas = true
}

function codigoDeSesion(decoded) {
  if (!decoded) return null
  if (decoded.userId != null) return String(decoded.userId)
  return (decoded.documento || "").toString().trim() || null
}

const num = (v) => { const n = Number.parseFloat(v); return Number.isNaN(n) ? 0 : n }

function filaRecaudo(r) {
  return {
    recaudoId: r.id,
    numeroRecaudo: r.numero_recaudo,
    clienteId: r.cliente_id,
    clienteNombre: (r.cliente_nombre || "").toString().trim(),
    formaPago: r.forma_pago,
    valor: num(r.total_recaudo),
    aplicado: num(r.total_aplicado),
    reciboCaja: r.recibo_caja == null ? null : Number(r.recibo_caja),
    reciboPrefijo: (r.recibo_prefijo || "").toString().trim(),
    fecha: r.fecha instanceof Date ? r.fecha.toISOString() : r.fecha,
    cuadrado: r.cuadre_id != null,
    cuadre: r.cuadre_id == null ? null : {
      cuadreId: r.cuadre_id,
      banco: r.cuadre_banco,
      numeroRecibo: r.cuadre_numero_recibo,
      observaciones: r.cuadre_observaciones || "",
      fecha: r.cuadre_fecha instanceof Date ? r.cuadre_fecha.toISOString() : r.cuadre_fecha,
      evidencias: Number(r.cuadre_evidencias) || 0,
    },
  }
}

const SELECT_RECAUDOS = `
  SELECT r.id, r.numero_recaudo, r.cliente_id, r.cliente_nombre, r.forma_pago,
         r.total_recaudo, r.total_aplicado, r.recibo_caja, r.recibo_prefijo, r.fecha,
         c.id AS cuadre_id, c.banco AS cuadre_banco, c.numero_recibo AS cuadre_numero_recibo,
         c.observaciones AS cuadre_observaciones, c.fecha AS cuadre_fecha,
         (SELECT COUNT(*) FROM dbo.evidencias_archivos e WHERE e.cuadre_id = c.id) AS cuadre_evidencias
  FROM dbo.recaudos r
  LEFT JOIN dbo.cuadres_caja c ON c.recaudo_id = r.id
`

async function listar(pool, sql, codigo, estado) {
  const filtro = estado === "cuadrado" ? "AND c.id IS NOT NULL" : "AND c.id IS NULL"
  const r = await pool.request()
    .input("u", sql.Int, Number.parseInt(codigo, 10))
    .input("f", sql.NVarChar, FORMA_PAGO)
    .query(`
      ${SELECT_RECAUDOS}
      WHERE r.vendedor_id = @u AND r.forma_pago = @f ${filtro}
      ORDER BY r.fecha DESC, r.id DESC
    `)
  return r.recordset.map(filaRecaudo)
}

async function detalle(pool, sql, codigo, recaudoId) {
  const r = await pool.request()
    .input("id", sql.Int, recaudoId)
    .input("u", sql.Int, Number.parseInt(codigo, 10))
    .query(`${SELECT_RECAUDOS} WHERE r.id = @id AND r.vendedor_id = @u`)
  if (r.recordset.length === 0) return null
  const cab = filaRecaudo(r.recordset[0])
  const docs = await pool.request()
    .input("id", sql.Int, recaudoId)
    .query(`
      SELECT doc_entry, doc_num, num_factura, saldo, abono, due_date
      FROM dbo.recaudos_documentos WHERE recaudo_id = @id ORDER BY doc_entry
    `)
  cab.documentos = docs.recordset.map((d) => ({
    docEntry: d.doc_entry,
    docNum: d.doc_num,
    numFactura: d.num_factura,
    saldo: num(d.saldo),
    abono: num(d.abono),
    vencimiento: d.due_date,
  }))
  return cab
}

async function registrar(pool, sql, decoded, { recaudoId, banco, numeroRecibo, observaciones, evidencia }) {
  const codigo = codigoDeSesion(decoded)
  if (!codigo) return { status: 400, message: "Sesión sin usuario identificable" }

  const id = Number.parseInt(recaudoId, 10)
  if (!(id > 0)) return { status: 400, message: "Recaudo requerido" }
  const bancoLimpio = (banco || "").toString().trim()
  const reciboLimpio = (numeroRecibo || "").toString().trim()
  if (!bancoLimpio) return { status: 400, message: "Indica el banco al que se consignó" }
  if (!reciboLimpio) return { status: 400, message: "Indica el número del recibo de consignación" }
  if (!evidencia || !evidencia.contenido || evidencia.contenido.length === 0) {
    return { status: 400, message: "Adjunta la imagen del comprobante de consignación" }
  }
  const obs = (observaciones || "").toString().trim().slice(0, 1000)

  const rec = await pool.request()
    .input("id", sql.Int, id)
    .input("u", sql.Int, Number.parseInt(codigo, 10))
    .query(`
      SELECT r.id, r.numero_recaudo, r.cliente_id, r.cliente_nombre, r.forma_pago,
             r.total_recaudo, r.recibo_caja, r.recibo_prefijo,
             (SELECT COUNT(*) FROM dbo.cuadres_caja c WHERE c.recaudo_id = r.id) AS ya
      FROM dbo.recaudos r WHERE r.id = @id AND r.vendedor_id = @u
    `)
  if (rec.recordset.length === 0) return { status: 404, message: "El recaudo no existe o no es tuyo" }
  const r = rec.recordset[0]
  if ((r.forma_pago || "").toString().trim().toLowerCase() !== FORMA_PAGO.toLowerCase()) {
    return { status: 409, message: `Solo se cuadran los recaudos en ${FORMA_PAGO.toLowerCase()}` }
  }
  if (Number(r.ya) > 0) return { status: 409, message: "Este recaudo ya fue cuadrado" }

  const transaction = pool.transaction()
  await transaction.begin()
  let cuadreId = null
  try {
    const ins = await transaction.request()
      .input("rid", sql.Int, r.id)
      .input("nrec", sql.NVarChar, r.numero_recaudo)
      .input("rcaja", sql.BigInt, r.recibo_caja)
      .input("rpref", sql.NVarChar, (r.recibo_prefijo || "").toString().trim() || null)
      .input("cli", sql.NVarChar, r.cliente_id)
      .input("cliNom", sql.NVarChar, (r.cliente_nombre || "").toString().trim() || null)
      .input("valor", sql.Decimal(18, 2), num(r.total_recaudo))
      .input("banco", sql.NVarChar, bancoLimpio)
      .input("recibo", sql.NVarChar, reciboLimpio)
      .input("obs", sql.NVarChar, obs || null)
      .input("uc", sql.NVarChar, codigo)
      .input("un", sql.NVarChar, (decoded.nombre || "").toString())
      .query(`
        INSERT INTO dbo.cuadres_caja
          (recaudo_id, numero_recaudo, recibo_caja, recibo_prefijo, cliente_id, cliente_nombre,
           valor, banco, numero_recibo, observaciones, usuario_codigo, usuario_nombre)
        OUTPUT INSERTED.id, INSERTED.fecha
        VALUES (@rid, @nrec, @rcaja, @rpref, @cli, @cliNom,
                @valor, @banco, @recibo, @obs, @uc, @un)
      `)
    cuadreId = ins.recordset[0].id
    const fecha = ins.recordset[0].fecha

    await transaction.request()
      .input("origen", sql.NVarChar, "cuadre")
      .input("cliente", sql.NVarChar, r.cliente_id)
      .input("numRec", sql.NVarChar, r.numero_recaudo)
      .input("vendId", sql.Int, Number.parseInt(codigo, 10))
      .input("vendNom", sql.NVarChar, (decoded.nombre || "").toString() || null)
      .input("cuadreId", sql.Int, cuadreId)
      .input("recaudoId", sql.Int, r.id)
      .input("contenido", sql.VarBinary(sql.MAX), evidencia.contenido)
      .input("tamano", sql.Int, evidencia.contenido.length)
      .input("ancho", sql.Int, evidencia.ancho || null)
      .input("alto", sql.Int, evidencia.alto || null)
      .query(`
        INSERT INTO dbo.evidencias_archivos
          (origen, cliente_id, numero_recaudo, vendedor_id, vendedor_nombre, cuadre_id, recaudo_id,
           contenido, tamano, ancho, alto)
        VALUES (@origen, @cliente, @numRec, @vendId, @vendNom, @cuadreId, @recaudoId,
                @contenido, @tamano, @ancho, @alto)
      `)
    await transaction.commit()
    return {
      status: 200,
      data: {
        cuadreId,
        recaudoId: r.id,
        numeroRecaudo: r.numero_recaudo,
        reciboCaja: r.recibo_caja == null ? null : Number(r.recibo_caja),
        clienteId: r.cliente_id,
        clienteNombre: (r.cliente_nombre || "").toString().trim(),
        valor: num(r.total_recaudo),
        banco: bancoLimpio,
        numeroRecibo: reciboLimpio,
        observaciones: obs,
        fecha: fecha instanceof Date ? fecha.toISOString() : fecha,
      },
    }
  } catch (e) {
    try { await transaction.rollback() } catch (_) {}
    if (/UQ_cuadre_recaudo/i.test(e.message || "")) {
      return { status: 409, message: "Este recaudo ya fue cuadrado" }
    }
    throw e
  }
}

function registrarRutas(app, { requireAuth, getPedidosPool, sql, subida, procesarImagen, log }) {
  const logger = log || console

  app.get("/api/cuadres/recaudos", requireAuth, async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      const codigo = codigoDeSesion(req.user)
      if (!codigo) return res.json({ success: true, data: [], total: 0 })
      const estado = (req.query.estado || "pendiente").toString().toLowerCase()
      const data = await listar(getPedidosPool(), sql, codigo, estado)
      res.json({
        success: true,
        estado,
        data,
        total: data.length,
        valorTotal: data.reduce((a, x) => a + x.valor, 0),
      })
    } catch (error) {
      logger.error("Error listando recaudos por cuadrar:", error.message)
      res.status(500).json({ success: false, message: "No se pudieron cargar los recaudos", data: [] })
    }
  })

  app.get("/api/cuadres/recaudos/:id", requireAuth, async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      const codigo = codigoDeSesion(req.user)
      const id = Number.parseInt(req.params.id, 10)
      if (!codigo || !(id > 0)) return res.status(400).json({ success: false, message: "Recaudo requerido" })
      const data = await detalle(getPedidosPool(), sql, codigo, id)
      if (!data) return res.status(404).json({ success: false, message: "El recaudo no existe o no es tuyo" })
      res.json({ success: true, data })
    } catch (error) {
      logger.error("Error obteniendo el recaudo:", error.message)
      res.status(500).json({ success: false, message: "No se pudo cargar el recaudo" })
    }
  })

  app.post("/api/cuadres", requireAuth, subida.single("foto"), async (req, res) => {
    try {
      await ensureEstructuras(getPedidosPool())
      let evidencia = null
      if (req.file && req.file.buffer && req.file.buffer.length > 0) {
        try {
          evidencia = await procesarImagen(req.file.buffer)
        } catch (e) {
          return res.status(400).json({ success: false, message: "La imagen del comprobante no se pudo procesar" })
        }
      }
      const b = req.body || {}
      const r = await registrar(getPedidosPool(), sql, req.user || {}, {
        recaudoId: b.recaudoId,
        banco: b.banco,
        numeroRecibo: b.numeroRecibo,
        observaciones: b.observaciones,
        evidencia,
      })
      if (r.status !== 200) return res.status(r.status).json({ success: false, message: r.message })
      const d = r.data
      logger.log(`Cuadre #${d.cuadreId} recaudo ${d.numeroRecaudo} recibo ${d.reciboCaja || "-"} cliente ${d.clienteId} banco ${d.banco} consignacion ${d.numeroRecibo} por ${(req.user && req.user.nombre) || "?"}`)
      res.json({ success: true, message: "Cuadre de caja registrado", data: d })
    } catch (error) {
      logger.error("Error registrando el cuadre:", error.message)
      res.status(500).json({ success: false, message: "No se pudo registrar el cuadre" })
    }
  })
}

module.exports = { FORMA_PAGO, ensureEstructuras, listar, detalle, registrar, registrarRutas }
