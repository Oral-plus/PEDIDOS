
const GRUPOS_POR_DEFECTO = [157, 130, 132, 133, 137, 139, 140, 141, 142]

function gruposDesdeEnv(valor) {
  const lista = (valor || "")
    .split(",")
    .map((s) => Number.parseInt(s.trim(), 10))
    .filter((n) => !Number.isNaN(n))
  return lista.length > 0 ? lista : GRUPOS_POR_DEFECTO
}

async function leerPorServiceLayer(sl, { bodega, grupos }) {
  const filtroGrupos = grupos.map((g) => `ItemsGroupCode eq ${g}`).join(" or ")
  const filtro = `SalesItem eq 'tYES' and Frozen eq 'tNO' and (${filtroGrupos})`
  const select = "ItemCode,ItemName,ItemsGroupCode,User_Text,ItemWarehouseInfoCollection,ItemPrices"

  const [items, gruposSap] = await Promise.all([
    sl.getAll(`/Items?$select=${select}&$filter=${encodeURIComponent(filtro)}`),
    sl.getAll("/ItemGroups?$select=Number,GroupName"),
  ])
  const nombreGrupo = new Map(gruposSap.map((g) => [g.Number, (g.GroupName || "").trim()]))

  return items.map((it) => {
    const almacen = (it.ItemWarehouseInfoCollection || []).find((w) => w.WarehouseCode === bodega)
    const precios = {}
    for (const p of it.ItemPrices || []) {
      if (Number(p.Price) > 0) precios[p.PriceList] = Number(p.Price)
    }
    return {
      codigo: it.ItemCode,
      nombre: (it.ItemName || "").trim(),
      grupoCodigo: it.ItemsGroupCode,
      grupoNombre: nombreGrupo.get(it.ItemsGroupCode) || "",
      descripcion: (it.User_Text || "").toString().trim(),
      stock: almacen ? Math.max(0, Number(almacen.InStock || 0) - Number(almacen.Committed || 0)) : 0,
      precios,
    }
  })
}

async function leerPorSql(pool, sql, { bodega, grupos }) {
  const req = pool.request().input("bodega", sql.VarChar, bodega)
  const marcadores = grupos.map((g, i) => {
    req.input(`g${i}`, sql.Int, g)
    return `@g${i}`
  })
  const enGrupos = `T0.ItmsGrpCod IN (${marcadores.join(",")})`

  const articulos = await req.query(`
    SELECT T0.ItemCode, T0.ItemName, T0.ItmsGrpCod, T2.ItmsGrpNam,
           CAST(T0.UserText AS NVARCHAR(MAX)) AS UserText,
           ISNULL(T1.OnHand, 0) AS OnHand, ISNULL(T1.IsCommited, 0) AS IsCommited
    FROM OITM T0
    JOIN OITB T2 ON T2.ItmsGrpCod = T0.ItmsGrpCod
    LEFT JOIN OITW T1 ON T1.ItemCode = T0.ItemCode AND T1.WhsCode = @bodega
    WHERE T0.SellItem = 'Y' AND T0.frozenFor = 'N' AND ${enGrupos}
    ORDER BY T0.ItemName;

    SELECT P.ItemCode, P.PriceList, P.Price
    FROM ITM1 P
    JOIN OITM T0 ON T0.ItemCode = P.ItemCode
    WHERE P.Price > 0 AND T0.SellItem = 'Y' AND T0.frozenFor = 'N' AND ${enGrupos};
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

module.exports = { GRUPOS_POR_DEFECTO, gruposDesdeEnv, leerPorServiceLayer, leerPorSql }
