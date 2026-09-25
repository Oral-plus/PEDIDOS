const path = require("path")
const { guardar } = require(path.join(process.cwd(), "modules", "evidencias"))

const out = []
const ok = (nombre, condicion, extra) => out.push([nombre + (extra ? `  [${extra}]` : ""), !!condicion])

// Un doble del pool/transaccion: anota la consulta y los parametros en vez de
// tocar la base, para poder probar el armado del INSERT sin SQL Server.
const sqlFalso = { VarBinary: () => "varbinary", MAX: "max", Int: "int", NVarChar: "nvarchar" }
function ejecutorFalso() {
  const visto = { consulta: "", parametros: {} }
  return {
    visto,
    request() {
      return {
        input(nombre, tipo, valor) {
          visto.parametros[nombre] = { tipo, valor }
          return this
        },
        async query(q) {
          visto.consulta = q
          return { recordset: [{ id: 77 }] }
        },
      }
    },
  }
}

const imagen = { contenido: Buffer.alloc(120, 7), ancho: 400, alto: 300 }
const valores = (visto) => Object.values(visto.parametros).map((p) => p.valor)

;(async () => {
  const eTarea = ejecutorFalso()
  const id = await guardar(
    eTarea,
    sqlFalso,
    { origen: "tarea", clienteId: "C123", vendedorId: 500, vendedorNombre: "GESTOR", tareaRespuestaId: 9 },
    imagen,
  )
  ok("devuelve el id que asigno la base", id === 77, `id ${id}`)
  ok("la foto de una tarea queda ligada a su respuesta",
    /tarea_respuesta_id/.test(eTarea.visto.consulta) && valores(eTarea.visto).includes(9))
  ok("guarda el tamano calculado, no uno que le pasen",
    eTarea.visto.parametros.tamano.valor === 120, `${eTarea.visto.parametros.tamano.valor} bytes`)
  ok("el codigo del vendedor viaja como entero y el del cliente como texto",
    eTarea.visto.parametros.d4.tipo === "int" && eTarea.visto.parametros.d3.tipo === "nvarchar",
    `${eTarea.visto.parametros.d4.tipo} / ${eTarea.visto.parametros.d3.tipo}`)

  const eRecaudo = ejecutorFalso()
  await guardar(eRecaudo, sqlFalso, { origen: "recaudo", numeroRecaudo: "REC-1", recaudoId: 4 }, imagen)
  ok("cada origen solo escribe sus columnas",
    /numero_recaudo/.test(eRecaudo.visto.consulta) &&
      !/tarea_respuesta_id/.test(eRecaudo.visto.consulta) &&
      !/cuadre_id/.test(eRecaudo.visto.consulta))

  const eMinimo = ejecutorFalso()
  await guardar(eMinimo, sqlFalso, { origen: "visita", clienteId: null, numeroPedido: "" }, imagen)
  ok("lo que llega vacio o nulo no viaja a la consulta",
    !/cliente_id/.test(eMinimo.visto.consulta) && !/numero_pedido/.test(eMinimo.visto.consulta))
  ok("siempre viajan contenido, tamano y medidas",
    /contenido/.test(eMinimo.visto.consulta) && /tamano/.test(eMinimo.visto.consulta) &&
      /ancho/.test(eMinimo.visto.consulta) && /alto/.test(eMinimo.visto.consulta))

  const eSinMedidas = ejecutorFalso()
  await guardar(eSinMedidas, sqlFalso, { origen: "gestion" }, { contenido: Buffer.alloc(3) })
  ok("una imagen sin medidas se guarda igual, con medidas nulas",
    eSinMedidas.visto.parametros.ancho.valor === null && eSinMedidas.visto.parametros.alto.valor === null)

  for (const [nombre, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + nombre + "\n")
  const todo = out.every(([, bien]) => bien)
  process.stdout.write("\n" + (todo ? "EVIDENCIAS (UNIDAD) OK\n" : "HAY FALLOS EN EVIDENCIAS (UNIDAD)\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => {
  process.stdout.write("ERROR " + e.message + "\n" + e.stack + "\n")
  process.exit(1)
})
