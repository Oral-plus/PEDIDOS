const path = require("path")
const { datosDe, enriquecer, limpiarCache, LOTE } = require(
  path.join(process.cwd(), "modules", "clientes_sap"),
)

const out = []
const ok = (nombre, condicion, extra) => out.push([nombre + (extra ? `  [${extra}]` : ""), !!condicion])

const sqlFalso = { VarChar: "varchar" }
const silencio = { error() {} }

// Un doble del pool de SAP: anota cuantas consultas recibe, para comprobar que
// no se cae en una por fila.
function poolFalso(filas, { falla = false } = {}) {
  const visto = { consultas: 0, parametros: [] }
  const pool = {
    visto,
    request() {
      const params = []
      return {
        input(nombre, tipo, valor) {
          params.push(valor)
          return this
        },
        async query() {
          visto.consultas += 1
          visto.parametros.push(params)
          if (falla) throw new Error("SAP no responde")
          return { recordset: filas.filter((f) => params.includes(f.CardCode)) }
        },
      }
    },
  }
  return pool
}

const FILAS = [
  { CardCode: "C1", CardName: "AUTOSERVICIO H D F", CardFName: "H.D.F", Address: "CALLE 100 # 20-30", City: "APARTADO" },
  { CardCode: "C2", CardName: "DROGUERIA NUEVA FRONTERA", CardFName: "", Address: "CRA 5 # 12-45", City: "TURBO" },
]

;(async () => {
  limpiarCache()
  const pool = poolFalso(FILAS)
  const datos = await datosDe(async () => pool, sqlFalso, ["C1", "C2"], silencio)

  ok("trae nombre, direccion y ciudad de cada cliente",
    datos.get("C1").direccion === "CALLE 100 # 20-30" && datos.get("C2").ciudad === "TURBO")

  ok("una sola consulta para todo el listado, no una por fila",
    pool.visto.consultas === 1, `${pool.visto.consultas} consulta(s)`)

  limpiarCache()
  const repetidos = poolFalso(FILAS)
  await datosDe(async () => repetidos, sqlFalso, ["C1", "C1", "C2", "", null, "C2"], silencio)
  ok("los codigos repetidos y vacios no se consultan dos veces",
    repetidos.visto.parametros[0].length === 2, `${repetidos.visto.parametros[0].length} codigo(s)`)

  const cacheado = poolFalso(FILAS)
  await datosDe(async () => cacheado, sqlFalso, ["C1", "C2"], silencio)
  ok("lo ya consultado no vuelve a pedirse a SAP", cacheado.visto.consultas === 0)

  limpiarCache()
  const caido = poolFalso(FILAS, { falla: true })
  const vacios = await datosDe(async () => caido, sqlFalso, ["C1"], silencio)
  ok("si SAP falla devuelve vacio en vez de reventar", vacios.size === 0)

  limpiarCache()
  const muchos = poolFalso([])
  await datosDe(async () => muchos, sqlFalso, Array.from({ length: LOTE + 50 }, (_, i) => `C${i}`), silencio)
  ok("mas codigos que el tope por consulta se parten en lotes",
    muchos.visto.consultas === 2, `${muchos.visto.consultas} consulta(s)`)

  // enriquecer() es pura: se prueba sin pool.
  const mapa = new Map([["C1", { nombre: "AUTOSERVICIO H D F", nombreComercial: "H.D.F", direccion: "CALLE 100", ciudad: "APARTADO" }]])
  const filas = enriquecer(
    [
      { id: 1, clienteId: "C1", ciudad: "" },
      { id: 2, clienteId: "SIN-DATOS", ciudad: "TURBO" },
    ],
    mapa,
  )
  ok("la ruta queda con el nombre y la direccion del cliente",
    filas[0].clienteNombre === "AUTOSERVICIO H D F" && filas[0].direccion === "CALLE 100")

  ok("si la ruta no trae ciudad, se usa la de SAP", filas[0].ciudad === "APARTADO")

  ok("un cliente sin datos en SAP deja la ruta intacta, no la borra",
    filas[1].id === 2 && filas[1].ciudad === "TURBO" && filas[1].direccion === undefined)

  ok("la ciudad que ya traia la ruta manda sobre la de SAP",
    enriquecer([{ clienteId: "C1", ciudad: "MEDELLIN" }], mapa)[0].ciudad === "MEDELLIN")

  ok("una lista vacia no rompe nada", enriquecer([], mapa).length === 0 && enriquecer(null, mapa).length === 0)

  for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
  const todo = out.every(([, bien]) => bien)
  process.stdout.write("\n" + (todo ? "CLIENTES SAP (UNIDAD) OK\n" : "HAY FALLOS EN CLIENTES SAP\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => {
  process.stdout.write("ERROR " + e.message + "\n" + e.stack + "\n")
  process.exit(1)
})
