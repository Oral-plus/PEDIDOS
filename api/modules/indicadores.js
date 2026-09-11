function codigoDeSesion(decoded) {
  if (!decoded) return null
  if (decoded.userId != null) return String(decoded.userId)
  return (decoded.documento || "").toString().trim() || null
}

const num = (v) => {
  const n = Number.parseFloat(v)
  return Number.isNaN(n) ? 0 : n
}

const SELECT_PAGOS = `
  SELECT r.id, r.numero_recaudo, r.cliente_id, r.cliente_nombre, r.forma_pago,
         r.banco_pago, r.referencia_pago, r.total_recaudo, r.total_aplicado, r.saldo,
         r.recibo_caja, r.recibo_prefijo, r.fecha, r.notas,
         c.id AS cuadre_id, c.fecha AS cuadre_fecha,
         (SELECT COUNT(*) FROM dbo.recaudos_documentos d WHERE d.recaudo_id = r.id) AS documentos
  FROM dbo.recaudos r
  LEFT JOIN dbo.cuadres_caja c ON c.recaudo_id = r.id
`

function filaPago(r) {
  const prefijo = (r.recibo_prefijo || "").toString().trim()
  const numero = r.recibo_caja == null ? null : Number(r.recibo_caja)
  return {
    recaudoId: r.id,
    numeroRecaudo: r.numero_recaudo,
    clienteId: r.cliente_id,
    clienteNombre: (r.cliente_nombre || "").toString().trim(),
    formaPago: (r.forma_pago || "").toString().trim(),
    banco: (r.banco_pago || "").toString().trim(),
    referencia: (r.referencia_pago || "").toString().trim(),
    valor: num(r.total_recaudo),
    aplicado: num(r.total_aplicado),
    saldo: num(r.saldo),
    documentos: Number(r.documentos) || 0,
    reciboCaja: numero,
    reciboPrefijo: prefijo,
    recibo: numero == null ? "" : `${prefijo}${numero}`,
    notas: (r.notas || "").toString().trim(),
    fecha: r.fecha instanceof Date ? r.fecha.toISOString() : r.fecha,
    cuadrado: r.cuadre_id != null,
    fechaCuadre: r.cuadre_fecha instanceof Date ? r.cuadre_fecha.toISOString() : r.cuadre_fecha,
  }
}

function limiteDesde(valor, pordefecto, maximo) {
  const n = Number.parseInt(valor, 10)
  if (!(n > 0)) return pordefecto
  return Math.min(n, maximo)
}

function fechaValida(valor) {
  const t = (valor || "").toString().trim()
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null
}

async function historialPagos(pool, sql, codigo, { desde, hasta, limite }) {
  const req = pool.request().input("u", sql.Int, Number.parseInt(codigo, 10)).input("limite", sql.Int, limite)
  const filtros = ["r.vendedor_id = @u"]
  if (desde) {
    req.input("desde", sql.VarChar, desde)
    filtros.push("r.fecha >= CONVERT(DATE, @desde)")
  }
  if (hasta) {
    req.input("hasta", sql.VarChar, hasta)
    filtros.push("r.fecha < DATEADD(day, 1, CONVERT(DATE, @hasta))")
  }
  const r = await req.query(`
    ${SELECT_PAGOS}
    WHERE ${filtros.join(" AND ")}
    ORDER BY r.fecha DESC, r.id DESC
    OFFSET 0 ROWS FETCH NEXT @limite ROWS ONLY
  `)
  return r.recordset.map(filaPago)
}

function resumen(pagos) {
  const porForma = new Map()
  let total = 0
  let cuadrados = 0
  for (const p of pagos) {
    total += p.valor
    if (p.cuadrado) cuadrados++
    const clave = p.formaPago || "Sin forma"
    const actual = porForma.get(clave) || { formaPago: clave, cantidad: 0, valor: 0 }
    actual.cantidad++
    actual.valor += p.valor
    porForma.set(clave, actual)
  }
  return {
    cantidad: pagos.length,
    total,
    cuadrados,
    porCuadrar: pagos.length - cuadrados,
    porFormaPago: [...porForma.values()].sort((a, b) => b.valor - a.valor),
  }
}

function registrarRutas(app, { requireAuth, getPedidosPool, sql, log }) {
  const logger = log || console

  app.get("/api/indicadores/pagos", requireAuth, async (req, res) => {
    try {
      const codigo = codigoDeSesion(req.user)
      if (!codigo) return res.json({ success: true, data: [], resumen: resumen([]) })
      const pagos = await historialPagos(getPedidosPool(), sql, codigo, {
        desde: fechaValida(req.query.desde),
        hasta: fechaValida(req.query.hasta),
        limite: limiteDesde(req.query.limite, 300, 1000),
      })
      res.json({ success: true, data: pagos, total: pagos.length, resumen: resumen(pagos) })
    } catch (error) {
      logger.error("Error listando historial de pagos:", error.message)
      res.status(500).json({ success: false, message: "No se pudo cargar el historial de pagos", data: [] })
    }
  })
}

module.exports = { registrarRutas, historialPagos, resumen }
