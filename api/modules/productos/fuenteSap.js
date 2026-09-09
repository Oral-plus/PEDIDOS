
const LOTE_STOCK = 40

async function leerPorServiceLayer(sl, { bodega }) {
  const filtro = "Valid eq 'tYES'"
  const select = "ItemCode,ItemName,ItemsGroupCode,User_Text,ItemPrices"

  const [items, gruposSap] = await Promise.all([
    sl.getAll(`/Items?$select=${select}&$orderby=ItemCode&$filter=${encodeURIComponent(filtro)}`),
    sl.getAll("/ItemGroups?$select=Number,GroupName"),
  ])
  const nombreGrupo = new Map(gruposSap.map((g) => [g.Number, (g.GroupName || "").trim()]))

  const catalogo = []
  for (const it of items) {
    const precios = {}
    for (const p of it.ItemPrices || []) {
      if (Number(p.Price) > 0) precios[p.PriceList] = Number(p.Price)
    }
    if (Object.keys(precios).length === 0) continue
    catalogo.push({
      codigo: it.ItemCode,
      nombre: (it.ItemName || "").trim(),
      grupoCodigo: it.ItemsGroupCode,
      grupoNombre: nombreGrupo.get(it.ItemsGroupCode) || "",
      descripcion: (it.User_Text || "").toString().trim(),
      stock: 0,
      precios,
    })
  }

  const stock = await leerStockPorServiceLayer(sl, catalogo.map((i) => i.codigo), bodega)
  for (const item of catalogo) item.stock = stock.get(item.codigo) || 0
  return catalogo
}

async function leerStockPorServiceLayer(sl, codigos, bodega) {
  const stock = new Map()
  for (let i = 0; i < codigos.length; i += LOTE_STOCK) {
    const filtro = codigos
      .slice(i, i + LOTE_STOCK)
      .map((c) => `ItemCode eq '${String(c).replace(/'/g, "''")}'`)
      .join(" or ")
    const filas = await sl.getAll(
      `/Items?$select=ItemCode,ItemWarehouseInfoCollection&$orderby=ItemCode&$filter=${encodeURIComponent(filtro)}`,
    )
    for (const f of filas) {
      const almacen = (f.ItemWarehouseInfoCollection || []).find((w) => w.WarehouseCode === bodega)
      stock.set(f.ItemCode, almacen ? Math.max(0, Number(almacen.InStock || 0) - Number(almacen.Committed || 0)) : 0)
    }
  }
  return stock
}

async function leerPorSql(pool, sql, { bodega }) {
  const req = pool.request().input("bodega", sql.VarChar, bodega)

  const articulos = await req.query(`
    SELECT T0.ItemCode, T0.ItemName, T0.ItmsGrpCod, T2.ItmsGrpNam,
           CAST(T0.UserText AS NVARCHAR(MAX)) AS UserText,
           ISNULL(T1.OnHand, 0) AS OnHand, ISNULL(T1.IsCommited, 0) AS IsCommited
    FROM OITM T0
    LEFT JOIN OITB T2 ON T2.ItmsGrpCod = T0.ItmsGrpCod
    LEFT JOIN OITW T1 ON T1.ItemCode = T0.ItemCode AND T1.WhsCode = @bodega
    WHERE T0.validFor = 'Y'
      AND EXISTS (SELECT 1 FROM ITM1 P WHERE P.ItemCode = T0.ItemCode AND P.Price > 0)
    ORDER BY T0.ItemName;

    SELECT P.ItemCode, P.PriceList, P.Price
    FROM ITM1 P
    JOIN OITM T0 ON T0.ItemCode = P.ItemCode
    WHERE P.Price > 0 AND T0.validFor = 'Y';
  `)

  const precios = new Map()
  for (const p of articulos.recordsets[1]) {
    if (!precios.has(p.ItemCode)) precios.set(p.ItemCode, {})
    precios.get(p.ItemCode)[p.PriceList] = Number(p.Price)
  }

  return articulos.recordsets[0].map((r) => ({
    codigo: r.ItemCode,
    nombre: (r.ItemName || "").trim(),
    grupoCodigo: r.ItmsGrpCod,
    grupoNombre: (r.ItmsGrpNam || "").trim(),
    descripcion: (r.UserText || "").toString().trim(),
    stock: Math.max(0, Number(r.OnHand) - Number(r.IsCommited)),
    precios: precios.get(r.ItemCode) || {},
  }))
}

module.exports = { leerPorServiceLayer, leerPorSql }
