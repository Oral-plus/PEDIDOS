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

async function etapasSap(getSapPool, sql, codigos) {
  const mapa = new Map()
  if (codigos.length === 0) return mapa
  const sap = await getSapPool()
  const req = sap.request()
  const marcadores = codigos.map((c, i) => {
    req.input(`c${i}`, sql.VarChar, c)
    return `@c${i}`
  })
  const r = await req.query(`
    SELECT C.CardCode,
           ISNULL(C.CreditLine, 0) AS creditLine,
           ISNULL(C.Balance, 0)    AS balance,
           (SELECT COUNT(*) FROM OINV I WHERE I.CardCode = C.CardCode) AS facturas,
           (SELECT COUNT(*) FROM OINV I
             WHERE I.CardCode = C.CardCode AND I.DocStatus = 'O'
               AND I.DocDueDate < GETDATE() AND (I.DocTotal - I.PaidToDate) > 0) AS vencidas
    FROM OCRD C
    WHERE C.CardCode IN (${marcadores.join(",")})
  `)
  for (const f of r.recordset) {
    const creditLine = num(f.creditLine)
    const balance = num(f.balance)
    mapa.set(f.CardCode, {
      enSap: true,
      creditLine,
      balance,
      cupoDisponible: creditLine > 0 ? creditLine - balance : null,
      facturas: Number(f.facturas) || 0,
      vencidas: Number(f.vencidas) || 0,
    })
  }
  return mapa
}

function etapaDePedido(pedido, sapCliente) {
  const enviado = pedido.sincronizado
  const enSap = !!sapCliente
  const bloqueoCartera = enSap && sapCliente.vencidas > 0
  const cupoDisponible = enSap ? sapCliente.cupoDisponible : null
  const bloqueoCupo = cupoDisponible != null && pedido.total > cupoDisponible
  const nuevo = enSap && sapCliente.facturas === 0

  const etiquetas = []
  if (enviado) etiquetas.push("ENVIADO")
  else if (bloqueoCartera || bloqueoCupo) {
    if (bloqueoCartera) etiquetas.push("BLOQUEO CARTERA")
    if (bloqueoCupo) etiquetas.push("BLOQUEO CUPO")
  } else if (nuevo) etiquetas.push("NUEVO")
  else if (enSap) etiquetas.push("OK")
  else etiquetas.push("N/D")

  return {
    etiquetas,
    enviado,
    bloqueoCartera,
    bloqueoCupo,
    nuevo,
    enSap,
    facturasVencidas: enSap ? sapCliente.vencidas : 0,
    cupoLimite: enSap ? sapCliente.creditLine : 0,
    cupoDisponible,
  }
}

async function historialPedidos(pedidosPool, getSapPool, sql, vendedor, { desde, hasta, limite }) {
  const req = pedidosPool.request().input("v", sql.NVarChar, vendedor).input("limite", sql.Int, limite)
  const filtros = ["p.vendedor = @v"]
  if (desde) {
    req.input("desde", sql.VarChar, desde)
    filtros.push("p.fecha_creacion >= CONVERT(DATE, @desde)")
  }
  if (hasta) {
    req.input("hasta", sql.VarChar, hasta)
    filtros.push("p.fecha_creacion < DATEADD(day, 1, CONVERT(DATE, @hasta))")
  }
  const r = await req.query(`
    SELECT p.id, p.numero_pedido, p.codigo_cliente, p.nombre_cliente, p.estado,
           p.subtotal, p.iva, p.total, p.observaciones,
           p.fecha_creacion, p.fecha_entrega,
           p.sincronizado_sap, p.doc_num_sap, p.doc_entry_sap,
           (SELECT COUNT(*) FROM dbo.pedidos_detalle d WHERE d.pedido_id = p.id) AS lineas
    FROM dbo.pedidos p
    WHERE ${filtros.join(" AND ")}
    ORDER BY p.fecha_creacion DESC, p.id DESC
    OFFSET 0 ROWS FETCH NEXT @limite ROWS ONLY
  `)

  const base = r.recordset.map((p) => ({
    pedidoId: p.id,
    numeroPedido: p.numero_pedido,
    clienteId: (p.codigo_cliente || "").toString().trim(),
    clienteNombre: (p.nombre_cliente || "").toString().trim(),
    estado: (p.estado || "").toString().trim(),
    subtotal: num(p.subtotal),
    iva: num(p.iva),
    total: num(p.total),
    lineas: Number(p.lineas) || 0,
    observaciones: (p.observaciones || "").toString().trim(),
    fecha: p.fecha_creacion instanceof Date ? p.fecha_creacion.toISOString() : p.fecha_creacion,
    fechaEntrega: p.fecha_entrega instanceof Date ? p.fecha_entrega.toISOString() : p.fecha_entrega,
    sincronizado: p.sincronizado_sap === 1 || p.sincronizado_sap === true || p.sincronizado_sap === "1",
    docNumSap: p.doc_num_sap == null ? "" : `${p.doc_num_sap}`,
    docEntrySap: p.doc_entry_sap == null ? null : Number(p.doc_entry_sap),
  }))

  const codigos = [...new Set(base.map((p) => p.clienteId).filter(Boolean))]
  let porCliente = new Map()
  let sapOk = true
  let sapMensaje = ""
  try {
    porCliente = await etapasSap(getSapPool, sql, codigos)
  } catch (e) {
    sapOk = false
    sapMensaje = e.message
  }

  const pedidos = base.map((p) => ({
    ...p,
    etapa: sapOk
      ? etapaDePedido(p, porCliente.get(p.clienteId))
      : { etiquetas: [p.sincronizado ? "ENVIADO" : "—"], enviado: p.sincronizado, bloqueoCartera: false, bloqueoCupo: false, nuevo: false, enSap: false, facturasVencidas: 0, cupoLimite: 0, cupoDisponible: null },
  }))
  return { pedidos, sapOk, sapMensaje }
}

function resumenPedidos(pedidos) {
  const contar = (f) => pedidos.filter(f).length
  return {
    cantidad: pedidos.length,
    total: pedidos.reduce((a, p) => a + p.total, 0),
    enviados: contar((p) => p.etapa.enviado),
    bloqueoCartera: contar((p) => p.etapa.bloqueoCartera && !p.etapa.enviado),
    bloqueoCupo: contar((p) => p.etapa.bloqueoCupo && !p.etapa.enviado),
    nuevos: contar((p) => p.etapa.etiquetas.includes("NUEVO")),
    pendientes: contar((p) => !p.etapa.enviado),
  }
}

function registrarRutas(app, { requireAuth, getPedidosPool, getSapPool, sql, log }) {
  const logger = log || console

  app.get("/api/indicadores/pedidos", requireAuth, async (req, res) => {
    try {
      const vendedor = (req.user && req.user.nombre ? req.user.nombre : "").toString().trim()
      if (!vendedor) return res.json({ success: true, data: [], resumen: resumenPedidos([]) })
      const { pedidos, sapOk, sapMensaje } = await historialPedidos(
        getPedidosPool(),
        getSapPool,
        sql,
        vendedor,
        {
          desde: fechaValida(req.query.desde),
          hasta: fechaValida(req.query.hasta),
          limite: limiteDesde(req.query.limite, 200, 1000),
        },
      )
      res.json({
        success: true,
        data: pedidos,
        total: pedidos.length,
        resumen: resumenPedidos(pedidos),
        sapOk,
        sapMensaje,
      })
    } catch (error) {
      logger.error("Error listando historial de pedidos:", error.message)
      res.status(500).json({ success: false, message: "No se pudo cargar el historial de pedidos", data: [] })
    }
  })

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

module.exports = { registrarRutas, historialPagos, resumen, etapaDePedido, resumenPedidos }
