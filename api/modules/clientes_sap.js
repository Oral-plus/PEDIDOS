// Datos del cliente que viven en SAP y hacen falta en otras pantallas.
//
// Las rutas y las visitas se guardan en la base Ruta, que solo conoce el
// codigo del cliente. El nombre y la direccion estan en OCRD. Este modulo los
// trae de a muchos: una consulta por listado, nunca una por fila.

// SQL Server admite 2100 parametros por consulta.
const LOTE = 400

// La direccion de un cliente no cambia de un minuto a otro.
const TTL_MS = 10 * 60 * 1000

const cache = new Map()

const texto = (v) => (v == null ? "" : String(v)).trim()

function enCache(codigo) {
  const guardado = cache.get(codigo)
  if (!guardado || Date.now() >= guardado.vence) return null
  return guardado.datos
}

/// Nombre, direccion y ciudad de cada cliente, por codigo.
///
/// Devuelve siempre un Map: si SAP falla, llega vacio y quien llame sigue su
/// camino sin esos datos. Nunca lanza.
async function datosDe(getSapPool, sql, codigos, log = console) {
  const unicos = [...new Set((codigos || []).map(texto).filter(Boolean))]
  const resultado = new Map()
  if (unicos.length === 0) return resultado

  const faltantes = []
  for (const codigo of unicos) {
    const guardado = enCache(codigo)
    if (guardado) resultado.set(codigo, guardado)
    else faltantes.push(codigo)
  }
  if (faltantes.length === 0) return resultado

  try {
    const pool = await getSapPool()
    for (let i = 0; i < faltantes.length; i += LOTE) {
      const lote = faltantes.slice(i, i + LOTE)
      const req = pool.request()
      const marcadores = lote.map((codigo, j) => {
        req.input(`c${j}`, sql.VarChar, codigo)
        return `@c${j}`
      })
      const r = await req.query(`
        SELECT CardCode, CardName, CardFName, Address, City
        FROM OCRD
        WHERE CardCode IN (${marcadores.join(",")})
      `)
      for (const fila of r.recordset) {
        const datos = {
          nombre: texto(fila.CardName),
          nombreComercial: texto(fila.CardFName),
          direccion: texto(fila.Address),
          ciudad: texto(fila.City),
        }
        const codigo = texto(fila.CardCode)
        cache.set(codigo, { datos, vence: Date.now() + TTL_MS })
        resultado.set(codigo, datos)
      }
    }
  } catch (e) {
    // Que SAP falle no puede dejar al gestor sin ver sus rutas.
    log.error("No se pudieron leer los datos de clientes en SAP:", e.message)
  }
  return resultado
}

/// Pega nombre y direccion sobre una lista que ya trae el codigo del cliente.
///
/// Funcion pura: recibe las filas y el mapa, y no sabe de bases de datos.
function enriquecer(filas, datos, clave = "clienteId") {
  return (filas || []).map((fila) => {
    const info = datos.get(texto(fila[clave]))
    if (!info) return fila
    return {
      ...fila,
      clienteNombre: info.nombre,
      clienteNombreComercial: info.nombreComercial,
      direccion: info.direccion,
      ciudad: texto(fila.ciudad) || info.ciudad,
    }
  })
}

function limpiarCache() {
  cache.clear()
}

module.exports = { datosDe, enriquecer, limpiarCache, LOTE }
