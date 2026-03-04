const { sql, getDbPool, getSapPool } = require('../config/database');

async function obtenerTodosClientesSAP(nit, esAdmin, tipoUsuario) {
  const sapPool = await getSapPool();
  let query;
  const request = sapPool.request();

  if (esAdmin) {
    query = `
      SELECT DISTINCT T0.[CardCode], T0.[CardFName], T0.[CardName], T1.[SlpCode], T1.[SlpName]
      FROM OCRD T0 INNER JOIN OSLP T1 ON T0.[SlpCode] = T1.[SlpCode]
      WHERE T0.[validFor] = 'Y' AND T0.[CardCode] NOT LIKE 'L%'
    `;
  } else if (tipoUsuario === 'COACH') {
    query = `
      SELECT DISTINCT T0.[CardCode], T0.[CardFName], T0.[CardName], T2.[SlpCode], T2.[SlpName]
      FROM OCRD T0
      INNER JOIN [dbo].[@COACH] T1 ON T0.[U_COACH] = T1.[Code]
      INNER JOIN OSLP T2 ON T0.[SlpCode] = T2.[SlpCode]
      WHERE T0.[validFor] = 'Y' AND T0.[CardCode] NOT LIKE 'L%' AND T1.[Code] = @nit
      UNION ALL
      SELECT DISTINCT T0.[CardCode], T0.[CardFName], T0.[CardName], T1.[SlpCode], T1.[SlpName]
      FROM OCRD T0 INNER JOIN OSLP T1 ON T0.[SlpCode] = T1.[SlpCode]
      WHERE T0.[validFor] = 'Y' AND T0.[CardCode] NOT LIKE 'L%' AND T1.[SlpCode] = @nit
    `;
    request.input('nit', sql.NVarChar, nit);
  } else {
    query = `
      SELECT DISTINCT T0.[CardCode], T0.[CardFName], T0.[CardName], T1.[SlpCode], T1.[SlpName]
      FROM OCRD T0 INNER JOIN OSLP T1 ON T0.[SlpCode] = T1.[SlpCode]
      WHERE T0.[validFor] = 'Y' AND T0.[CardCode] NOT LIKE 'L%' AND T1.[SlpCode] = @nit
    `;
    request.input('nit', sql.NVarChar, nit);
  }

  const result = await request.query(query);

  return result.recordset.map((r) => ({
    id: r.CardCode,
    nombre: r.CardFName,
    nombre1: r.CardFName,
    cardName: r.CardName,
    slpcode: r.SlpCode,
    slpname: r.SlpName,
  }));
}

async function obtenerClientesNoAsignados(nit, esAdmin, tipoUsuario) {
  const todosClientes = await obtenerTodosClientesSAP(nit, esAdmin, tipoUsuario);

  const dbPool = await getDbPool();
  const rutasResult = await dbPool.request().query(`
    SELECT DISTINCT cliente_id
    FROM Ruta.dbo.rutas
    WHERE cliente_id IS NOT NULL AND cliente_id != ''
    AND DATEDIFF(day, fecha_creacion, GETDATE()) < 15
  `);

  const clientesConRutas = new Set(rutasResult.recordset.map((r) => r.cliente_id));

  if (clientesConRutas.size === 0) return todosClientes;

  return todosClientes.filter((c) => !clientesConRutas.has(c.id));
}

async function obtenerClientesProximosARevisitar(usuario_id) {
  const dbPool = await getDbPool();
  const esAdmin = usuario_id === 1;

  const result = await dbPool
    .request()
    .input('usuario_id', sql.Int, usuario_id)
    .input('es_admin', sql.Int, esAdmin ? 1 : 0)
    .query(`
      SELECT DISTINCT r.cliente_id, r.fecha_creacion,
             DATEDIFF(day, r.fecha_creacion, GETDATE()) as dias_transcurridos
      FROM Ruta.dbo.rutas r
      WHERE r.cliente_id IS NOT NULL AND r.cliente_id != ''
      AND DATEDIFF(day, r.fecha_creacion, GETDATE()) BETWEEN 11 AND 13
      AND (r.usuario_id = @usuario_id OR @es_admin = 1)
      ORDER BY r.fecha_creacion DESC
    `);

  const clientesProximos = [];
  const sapPool = await getSapPool();

  for (const row of result.recordset) {
    const clienteResult = await sapPool
      .request()
      .input('code', sql.NVarChar, row.cliente_id)
      .query('SELECT TOP 1 CardCode as id, CardName as nombre1 FROM OCRD WHERE CardCode = @code');

    if (clienteResult.recordset.length > 0) {
      clientesProximos.push({
        id: row.cliente_id,
        nombre: clienteResult.recordset[0].nombre1,
        dias_transcurridos: row.dias_transcurridos,
        fecha_ultima_ruta: row.fecha_creacion,
        dias_restantes: 15 - row.dias_transcurridos,
      });
    }
  }

  return clientesProximos;
}

async function obtenerClientePorCodigo(codigoCliente) {
  const sapPool = await getSapPool();
  const result = await sapPool
    .request()
    .input('code', sql.NVarChar, codigoCliente)
    .query('SELECT TOP 1 CardCode as id, CardName as nombre1 FROM OCRD WHERE CardCode = @code');

  return result.recordset.length > 0 ? result.recordset[0] : null;
}

async function obtenerCarteraCliente(codigoCliente) {
  const sapPool = await getSapPool();

  const clienteReq = sapPool.request();
  const clienteResult = await clienteReq
    .input('code', sql.NVarChar, codigoCliente)
    .query(`
      SELECT TOP 1
        T0.CardCode,
        T0.CardFName,
        T0.CardName,
        T0.Balance,
        T0.Phone1,
        T0.Phone2,
        T0.Address,
        T0.City,
        T0.SlpCode,
        T1.SlpName
      FROM OCRD T0
      LEFT JOIN OSLP T1 ON T0.SlpCode = T1.SlpCode
      WHERE T0.CardCode = @code
    `);

  if (clienteResult.recordset.length === 0) {
    return null;
  }

  const cliente = clienteResult.recordset[0];

  const factReq = sapPool.request();
  const facturasResult = await factReq
    .input('code2', sql.NVarChar, codigoCliente)
    .query(`
      SELECT
        T1.DocNum,
        T1.DocDate,
        T1.DocDueDate,
        T1.DocTotal,
        T1.PaidToDate,
        (T1.DocTotal - T1.PaidToDate) AS SaldoPendiente,
        CASE WHEN T1.DocDueDate < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS Vencida
      FROM OINV T1
      WHERE T1.CardCode = @code2
        AND T1.DocStatus = 'O'
        AND (T1.DocTotal - T1.PaidToDate) > 0
      ORDER BY T1.DocDueDate ASC
    `);

  const facturas = facturasResult.recordset;
  const totalFacturasAbiertas = facturas.length;
  const facturasVencidas = facturas.filter(f => f.Vencida === 1).length;
  const saldoFacturas = facturas.reduce((sum, f) => sum + (parseFloat(f.SaldoPendiente) || 0), 0);

  return {
    codigo: cliente.CardCode,
    nombre: cliente.CardFName || cliente.CardName,
    nombreComercial: cliente.CardName,
    balance: parseFloat(cliente.Balance) || 0,
    telefono: cliente.Phone1 || cliente.Phone2 || '',
    direccion: cliente.Address || '',
    ciudad: cliente.City || '',
    vendedor: cliente.SlpName || '',
    codigoVendedor: cliente.SlpCode,
    totalFacturasAbiertas,
    facturasVencidas,
    saldoFacturas,
    facturas: facturas.map(f => ({
      numero: f.DocNum,
      fecha: f.DocDate,
      vencimiento: f.DocDueDate,
      total: parseFloat(f.DocTotal) || 0,
      abonado: parseFloat(f.PaidToDate) || 0,
      saldo: parseFloat(f.SaldoPendiente) || 0,
      vencida: f.Vencida === 1,
    })),
  };
}

module.exports = {
  obtenerTodosClientesSAP,
  obtenerClientesNoAsignados,
  obtenerClientesProximosARevisitar,
  obtenerClientePorCodigo,
  obtenerCarteraCliente,
};
