const TOLERANCIA = 100

const numero = (v) => {
  const n = Number.parseFloat(v)
  return Number.isFinite(n) ? n : 0
}

const redondear = (v) => Math.round(v * 100) / 100

const enteroEntre = (valor, pordefecto, minimo, maximo) => {
  const n = Number.parseInt(valor, 10)
  if (!Number.isFinite(n)) return pordefecto
  return Math.min(maximo, Math.max(minimo, n))
}

function netear(documentos, abonos, { tolerancia = TOLERANCIA, diasAviso = 5 } = {}) {
  const porDocumento = new Map()
  for (const a of abonos || []) {
    const clave = String(a.docEntry)
    if (!porDocumento.has(clave)) porDocumento.set(clave, [])
    porDocumento.get(clave).push(a)
  }

  const pendientes = []
  const neteados = (documentos || []).map((d) => {
    const saldoSap = numero(d.saldo)
    let pendienteDocumento = 0
    for (const abono of porDocumento.get(String(d.docEntry)) || []) {
      const aplicadoEnSap = Math.max(0, numero(abono.saldoAlRegistrar) - saldoSap)
      const pendiente = Math.max(0, numero(abono.abono) - aplicadoEnSap)
      if (pendiente <= tolerancia) continue
      pendienteDocumento += pendiente
      pendientes.push({
        numeroRecaudo: abono.numeroRecaudo,
        fecha: abono.fecha,
        docEntry: d.docEntry,
        docNum: d.docNum,
        numFactura: d.numFactura,
        abono: redondear(numero(abono.abono)),
        pendiente: redondear(pendiente),
        dias: abono.dias || 0,
        vendedor: abono.vendedor || "",
        demorado: (abono.dias || 0) > diasAviso,
      })
    }
    const aplicable = Math.min(pendienteDocumento, saldoSap)
    return {
      ...d,
      pendientePorAplicar: redondear(aplicable),
      saldoNeto: redondear(saldoSap - aplicable),
    }
  })

  const saldoSap = redondear(neteados.reduce((a, d) => a + numero(d.saldo), 0))
  const pendientePorAplicar = redondear(neteados.reduce((a, d) => a + d.pendientePorAplicar, 0))

  return {
    documentos: neteados,
    pendientes,
    saldoSap,
    pendientePorAplicar,
    saldoNeto: redondear(saldoSap - pendientePorAplicar),
  }
}

function medioPago(p) {
  if (numero(p.CashSum) > 0) return "Efectivo"
  if (numero(p.TrsfrSum) > 0) return "Transferencia"
  if (numero(p.CheckSum) > 0) return "Cheque"
  return ""
}

function crear({ sql, getSapPool, getPedidosPool, env, log }) {
  const logger = log || console
  const variables = env || {}
  const diasVentana = enteroEntre(variables.CARTERA_DIAS_PENDIENTES, 30, 1, 365)
  const diasAviso = enteroEntre(variables.CARTERA_DIAS_AVISO, 5, 1, 90)

  async function documentosDe(cardCode, limite = 500) {
    const sap = await getSapPool()
    const r = await sap
      .request()
      .input("cardCode", sql.VarChar, cardCode)
      .input("limite", sql.Int, limite)
      .query(`
        SELECT TOP (@limite) T0.DocEntry, T0.DocNum, T0.NumAtCard,
               CONVERT(VARCHAR(10), T0.DocDate, 120)     AS docDate,
               CONVERT(VARCHAR(10), T0.DocDueDate, 120)  AS dueDate,
               T0.DocTotal, T0.PaidToDate,
               (T0.DocTotal - T0.PaidToDate)             AS saldo,
               DATEDIFF(day, GETDATE(), T0.DocDueDate)   AS diasVencimiento
        FROM OINV T0
        WHERE T0.CardCode = @cardCode AND T0.DocStatus = 'O'
          AND (T0.DocTotal - T0.PaidToDate) > 0
        ORDER BY T0.DocDueDate ASC
      `)
    return r.recordset.map((d) => ({
      docEntry: d.DocEntry,
      docNum: d.DocNum,
      numFactura: (d.NumAtCard || `${d.DocNum}`).toString(),
      docDate: d.docDate,
      dueDate: d.dueDate,
      total: numero(d.DocTotal),
      pagado: numero(d.PaidToDate),
      saldo: numero(d.saldo),
      diasVencimiento: d.diasVencimiento || 0,
      vencida: (d.diasVencimiento || 0) < 0,
    }))
  }

  async function pagosSinAplicarDe(cardCode, limite = 500) {
    const sap = await getSapPool()
    const r = await sap
      .request()
      .input("cardCode", sql.VarChar, cardCode)
      .input("limite", sql.Int, limite)
      .query(`
        SELECT TOP (@limite) T.TransId, T.Line_ID, R.DocEntry, R.DocNum,
               CONVERT(VARCHAR(10), ISNULL(R.DocDate, T.RefDate), 120) AS fecha,
               T.Credit                                  AS valor,
               T.BalDueCred                              AS saldo,
               DATEDIFF(day, ISNULL(R.DocDate, T.RefDate), GETDATE()) AS antiguedad,
               R.CashSum, R.TrsfrSum, R.CheckSum, R.Comments
        FROM JDT1 T
        LEFT JOIN ORCT R ON R.TransId = T.TransId AND R.Canceled = 'N'
        WHERE T.ShortName = @cardCode AND T.TransType = 24 AND T.BalDueCred > 0
        ORDER BY ISNULL(R.DocDate, T.RefDate) DESC
      `)
    return r.recordset.map((p) => ({
      transId: p.TransId,
      lineId: p.Line_ID,
      docEntry: p.DocEntry,
      docNum: p.DocNum,
      recibo: p.DocNum != null ? `${p.DocNum}` : "",
      fecha: p.fecha,
      valor: numero(p.valor),
      saldo: numero(p.saldo),
      aplicado: numero(p.valor) - numero(p.saldo),
      antiguedad: p.antiguedad || 0,
      medioPago: medioPago(p),
      comentario: (p.Comments || "").toString().trim(),
    }))
  }

  async function abonosDe(codigos) {
    const lista = (Array.isArray(codigos) ? codigos : [codigos]).filter(Boolean)
    const porCliente = new Map()
    if (lista.length === 0) return porCliente
    const req = getPedidosPool().request().input("dias", sql.Int, diasVentana)
    const marcadores = lista.map((c, i) => {
      req.input(`c${i}`, sql.NVarChar, c)
      return `@c${i}`
    })
    const r = await req.query(`
      SELECT r.cliente_id, r.numero_recaudo, r.vendedor_nombre,
             CONVERT(VARCHAR(19), r.fecha, 120) AS fecha,
             DATEDIFF(day, r.fecha, GETDATE()) AS dias,
             d.doc_entry, d.abono, d.saldo AS saldo_al_registrar
      FROM dbo.recaudos r
      JOIN dbo.recaudos_documentos d ON d.recaudo_id = r.id
      WHERE r.cliente_id IN (${marcadores.join(",")})
        AND r.fecha >= DATEADD(day, -@dias, GETDATE())
        AND d.doc_entry IS NOT NULL
      ORDER BY r.fecha DESC
    `)
    for (const f of r.recordset) {
      const clave = (f.cliente_id || "").toString()
      if (!porCliente.has(clave)) porCliente.set(clave, [])
      porCliente.get(clave).push({
        numeroRecaudo: f.numero_recaudo,
        fecha: f.fecha,
        dias: f.dias || 0,
        vendedor: (f.vendedor_nombre || "").toString().trim(),
        docEntry: f.doc_entry,
        abono: numero(f.abono),
        saldoAlRegistrar: numero(f.saldo_al_registrar),
      })
    }
    return porCliente
  }

  async function saldoDe(cardCode, { limite = 500, incluirPagosSap = true } = {}) {
    const [documentos, abonosPorCliente, pagosSinAplicar] = await Promise.all([
      documentosDe(cardCode, limite),
      abonosDe([cardCode]).catch((e) => {
        logger.error("No se pudieron leer los recaudos pendientes:", e.message)
        return new Map()
      }),
      incluirPagosSap ? pagosSinAplicarDe(cardCode, limite).catch(() => []) : Promise.resolve([]),
    ])
    const neto = netear(documentos, abonosPorCliente.get(cardCode) || [], { diasAviso })
    return {
      ...neto,
      pagosSinAplicar,
      totalSinAplicar: redondear(pagosSinAplicar.reduce((a, p) => a + p.saldo, 0)),
    }
  }

  async function pendientesPorCliente(codigos) {
    const lista = [...new Set((codigos || []).filter(Boolean))]
    const resultado = new Map()
    if (lista.length === 0) return resultado
    const abonosPorCliente = await abonosDe(lista)
    await Promise.all(
      [...abonosPorCliente.keys()].map(async (codigo) => {
        try {
          const documentos = await documentosDe(codigo)
          const neto = netear(documentos, abonosPorCliente.get(codigo) || [], { diasAviso })
          if (neto.pendientePorAplicar > 0) resultado.set(codigo, neto.pendientePorAplicar)
        } catch (e) {
          logger.error(`No se pudo netear la cartera de ${codigo}:`, e.message)
        }
      }),
    )
    return resultado
  }

  function registrarRutas(app, { requireAuth, limiteDesdeQuery }) {
    app.get("/api/clientes/:codigo/documentos", requireAuth, async (req, res) => {
      try {
        const cardCode = req.params.codigo
        const limite = limiteDesdeQuery(req.query.limit, 500, 2000)
        const r = await saldoDe(cardCode, { limite })
        logger.log(
          `Documentos abiertos cliente ${cardCode}: ${r.documentos.length} (saldo ${r.saldoSap}, neto ${r.saldoNeto}), ` +
            `recaudos por aplicar: ${r.pendientes.length} (${r.pendientePorAplicar}), ` +
            `pagos sin aplicar en SAP: ${r.pagosSinAplicar.length} (${r.totalSinAplicar})`,
        )
        res.json({
          success: true,
          data: r.documentos,
          total: r.documentos.length,
          totalSaldo: r.saldoSap,
          saldoSap: r.saldoSap,
          saldoNeto: r.saldoNeto,
          pendientePorAplicar: r.pendientePorAplicar,
          recaudosPendientes: r.pendientes,
          pagosSinAplicar: r.pagosSinAplicar,
          totalSinAplicar: r.totalSinAplicar,
        })
      } catch (error) {
        logger.error("Error obteniendo documentos:", error.message)
        res.status(500).json({ success: false, message: "Error al obtener documentos", data: [] })
      }
    })
  }

  return { registrarRutas, saldoDe, documentosDe, pagosSinAplicarDe, pendientesPorCliente, diasAviso }
}

module.exports = { crear, netear, numero, redondear }
