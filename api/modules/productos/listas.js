// Catalogo visto por lista de precios.
//
// Es el nucleo: no habla con SAP ni con la base. Recibe lo que ya esta en
// memoria y arma la vista; quien lee SAP es fuenteSap y quien expone HTTP es
// rutas. Asi esta regla se prueba sola, sin servidor.

/// Precios del articulo en las listas pedidas, descartando los que no tienen.
function preciosEn(item, ids) {
  const precios = {}
  for (const id of ids) {
    const valor = Number(item.precios ? item.precios[id] : 0)
    if (valor > 0) precios[id] = valor
  }
  return precios
}

/// Arma el catalogo por lista.
///
/// [items] son los articulos del catalogo, [listas] las listas de precios a
/// mostrar y [proyectar] decide como se ve un articulo (nombre, categoria,
/// imagen): esa decision ya vive en el repositorio y no se repite aqui.
/// [ocultar] dice si un articulo no debe salir.
function armar({ items, listas, proyectar, ocultar }) {
  const ids = listas.map((l) => l.id)
  const productos = []

  for (const item of items) {
    if (ocultar && ocultar(item)) continue
    const precios = preciosEn(item, ids)
    if (Object.keys(precios).length === 0) continue
    productos.push({ ...proyectar(item), precios })
  }

  productos.sort((a, b) => {
    const porCategoria = (a.categoria || "").localeCompare(b.categoria || "", "es")
    if (porCategoria !== 0) return porCategoria
    return (a.nombre || "").localeCompare(b.nombre || "", "es")
  })

  // Una lista sin un solo precio no le sirve a nadie: no se muestra.
  const conPrecio = listas.filter((l) => productos.some((p) => p.precios[l.id] > 0))

  return {
    listas: conPrecio.map((l) => ({
      ...l,
      productos: productos.filter((p) => p.precios[l.id] > 0).length,
    })),
    productos,
    total: productos.length,
  }
}

module.exports = { armar, preciosEn }
