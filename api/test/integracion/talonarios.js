const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99981
const PREFIJO = `SKV${VEND}`
const CLIENTE = "CLI-TALONARIO"
const CLAVE_REDIS = `${process.env.REDIS_PREFIJO || "pedidos:"}talonario:siguiente:${PREFIJO}`

function multipart(campos, archivos) {
  const limite = "----tal" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [k, v] of Object.entries(campos)) partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${a.campo}"; filename="${a.nombre}"\r\nContent-Type: image/png\r\n\r\n`))
    partes.push(a.contenido); partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

function llamar(metodo, ruta, { token, body, mp } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : body !== undefined ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
    else if (datos) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = Buffer.byteLength(datos)
    if (token) h.Authorization = `Bearer ${token}`
    const req = (BASE.startsWith("https") ? require("https") : http).request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const t = []
      res.on("data", (c) => t.push(c))
      res.on("end", () => { let j = null; try { j = JSON.parse(Buffer.concat(t).toString("utf8")) } catch (_) {} resolve({ status: res.statusCode, json: j }) })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}
async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test", {}); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = { server: process.env.DB_SERVER, database: process.env.PEDIDOS_DB_NAME || "Pedidos", user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } }

async function abrirRedis() {
  const url = (process.env.REDIS_URL || "").trim()
  if (!url) return null
  try {
    const { createClient } = require(path.join(process.cwd(), "node_modules", "redis"))
    const c = createClient({ url, socket: { connectTimeout: 3000, reconnectStrategy: false } })
    c.on("error", () => {})
    await c.connect()
    return c
  } catch (_) {
    return null
  }
}

;(async () => {
  const out = []
  const ok = (nm, c, extra) => out.push([nm + (extra ? `  [${extra}]` : ""), !!c])
  const n = (v) => (v == null ? null : Number(v))
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg).connect()
  const redis = await abrirRedis()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${VEND}`, usuarioNombre: "PRUEBA TALONARIO", tipo: "vendedor", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: VEND, nombre: "PRUEBA TALONARIO", tipo: "vendedor", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const foto = await sharp({ create: { width: 700, height: 500, channels: 3, background: { r: 180, g: 60, b: 40 } } }).png().toBuffer()

  const limpiar = async () => {
    await pedidos.request().input("p", sql.NVarChar, PREFIJO).input("c", sql.NVarChar, CLIENTE)
      .query("DELETE FROM dbo.recaudos WHERE recibo_prefijo=@p OR cliente_id=@c")
    await pedidos.request().input("p", sql.NVarChar, PREFIJO)
      .query("DELETE FROM dbo.talonarios_cancelaciones WHERE prefijo=@p")
    await pedidos.request().input("p", sql.NVarChar, PREFIJO)
      .query("DELETE FROM dbo.TALONARIO WHERE prefijo=@p")
    if (redis) { try { await redis.del(CLAVE_REDIS) } catch (_) {} }
  }
  const crearTalonario = async (ini, fin) => {
    const r = await pedidos.request().input("v", sql.Int, VEND).input("p", sql.NVarChar, PREFIJO)
      .input("i", sql.BigInt, ini).input("f", sql.BigInt, fin).query(`
        INSERT INTO dbo.TALONARIO (vendedor_codigo, vendedor_nombre, prefijo, tipo_recibo, rango_inicial, rango_final, estado, usuario, fecha)
        OUTPUT INSERTED.id
        VALUES (@v, 'PRUEBA TALONARIO', @p, 'RECIBO DE CAJA', @i, @f, 'ACTIVO', 'prueba', GETDATE())
      `)
    return r.recordset[0].id
  }
  const pagar = async (sufijo) => llamar("POST", "/api/recaudos", { token, body: {
    numeroRecaudo: `REC-TAL-${ts}-${sufijo}`, clienteId: CLIENTE, clienteNombre: "PRUEBA",
    formaPago: "Efectivo", totalDocumentos: 1000, totalAplicado: 1000, totalRecaudo: 1000, saldo: 0,
    notas: "observacion del pago", documentos: [{ docEntry: 1, docNum: "F-TAL", numFactura: "FE-TAL", saldo: 1000, abono: 1000, dueDate: "2026-12-31" }],
  } })
  const cancelar = (campos, conFoto) => llamar("POST", "/api/talonarios/cancelar", conFoto
    ? { token, mp: multipart(campos, [{ campo: "foto", nombre: "novedad.png", contenido: foto }]) }
    : { token, body: campos })
  const siguiente = () => llamar("GET", "/api/talonarios/siguiente", { token })

  await siguiente()
  await limpiar()

  const cols = (await pedidos.request().query(`
    SELECT COLUMN_NAME c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='talonarios_cancelaciones'
  `)).recordset.map((r) => r.c)
  const requeridas = ["talonario_id", "numero", "causal", "observaciones", "fecha", "usuario_codigo", "usuario_nombre", "estado", "prefijo"]
  ok("BD: talonarios_cancelaciones guarda unidad, causal, observaciones, usuario, estado y fecha",
    requeridas.every((c) => cols.includes(c)), cols.join(","))
  const fks = (await pedidos.request().query(`
    SELECT name FROM sys.foreign_keys WHERE name IN ('FK_talcanc_talonario','FK_evid_cancelacion')
  `)).recordset.map((r) => r.name)
  ok("BD: integridad referencial de la cancelacion y de su evidencia",
    fks.includes("FK_talcanc_talonario") && fks.includes("FK_evid_cancelacion"), fks.join(","))
  const uq = (await pedidos.request().query("SELECT name FROM sys.indexes WHERE name='UQ_talcanc_unidad'")).recordset
  ok("BD: una unidad no se puede cancelar dos veces (indice unico)", uq.length === 1)

  const cau = await llamar("GET", "/api/talonarios/causales", { token })
  const causales = (cau.json && cau.json.data) || []
  ok("causales: Deterioro y Daño por mal manejo", cau.status === 200 && causales.length === 2 &&
    causales.includes("Deterioro") && causales.includes("Daño por mal manejo"), causales.join(" / "))

  const sinTalPago = await pagar("sin")
  const guardadoSin = (await pedidos.request().input("n", sql.NVarChar, `REC-TAL-${ts}-sin`)
    .query("SELECT COUNT(*) n FROM dbo.recaudos WHERE numero_recaudo=@n")).recordset[0].n
  ok("sin talonario asignado: el pago se rechaza y no guarda nada",
    sinTalPago.status === 409 && sinTalPago.json.sinTalonario === true && guardadoSin === 0,
    `${sinTalPago.status} · ${(sinTalPago.json && sinTalPago.json.message || "").slice(0, 60)}`)
  const sinTalCanc = await cancelar({ causal: "Deterioro" })
  ok("sin talonario asignado: cancelar responde 404", sinTalCanc.status === 404, sinTalCanc.json && sinTalCanc.json.message)

  const talA = await crearTalonario(1, 3)
  const enCurso = await siguiente()
  ok("talonario de 3 unidades: la primera unidad es la 1",
    enCurso.json.data && enCurso.json.data.talonarioId === talA && n(enCurso.json.data.siguiente) === 1 &&
    n(enCurso.json.data.unidades) === 3, `sig=${enCurso.json.data && enCurso.json.data.siguiente} unidades=${enCurso.json.data && enCurso.json.data.unidades}`)

  const p1 = await pagar("a")
  ok("cada pago consume una unidad en secuencia: el primero toma la 1",
    p1.status === 200 && n(p1.json.data.reciboCaja) === 1, `recibo=${p1.json && p1.json.data && p1.json.data.reciboCaja}`)
  const asignado1 = (await pedidos.request().input("n", sql.NVarChar, `REC-TAL-${ts}-a`)
    .query("SELECT recibo_caja, recibo_talonario_id, notas FROM dbo.recaudos WHERE numero_recaudo=@n")).recordset[0]
  ok("el pago queda asociado a la unidad y guarda la observacion del pago",
    asignado1 && n(asignado1.recibo_caja) === 1 && asignado1.recibo_talonario_id === talA && asignado1.notas === "observacion del pago",
    asignado1 && `unidad ${asignado1.recibo_caja} · "${asignado1.notas}"`)

  const consulta = await siguiente()
  const enRedis = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: la consulta queda cacheada y la siguiente unidad es la 2",
    n(consulta.json.data.siguiente) === 2 && (!redis || (enRedis && JSON.parse(enRedis).siguiente === 2)),
    `sig=${consulta.json.data && consulta.json.data.siguiente}`)

  const sinCausal = await cancelar({})
  const inventada = await cancelar({ causal: "Se me perdio" })
  const registrosTras = (await pedidos.request().input("id", sql.Int, talA)
    .query("SELECT COUNT(*) n FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id")).recordset[0].n
  ok("cancelar sin causal: 400 (obligatoria)", sinCausal.status === 400, sinCausal.json && sinCausal.json.message)
  ok("cancelar con causal fuera del catalogo: 400", inventada.status === 400, inventada.json && inventada.json.message)
  ok("los intentos fallidos no escriben nada", registrosTras === 0, `registros=${registrosTras}`)

  const OBS = "Se mojo el formato en la ruta y no se puede diligenciar"
  const canc2 = await cancelar({ causal: "Deterioro", observaciones: OBS }, true)
  ok("cancelar la unidad 2: 200 e informa que se sigue con la 3",
    canc2.status === 200 && canc2.json.data && n(canc2.json.data.numeroCancelado) === 2 &&
    canc2.json.data.siguiente && n(canc2.json.data.siguiente.siguiente) === 3,
    canc2.json && canc2.json.message)

  const reg2 = (await pedidos.request().input("id", sql.Int, talA).query(`
    SELECT TOP 1 id, numero, causal, observaciones, usuario_codigo, usuario_nombre, estado, rango_inicial, rango_final, fecha
    FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id ORDER BY id DESC
  `)).recordset[0]
  ok("BD: la cancelacion guarda unidad, causal, observaciones, usuario, estado y fecha",
    reg2 && n(reg2.numero) === 2 && reg2.causal === "Deterioro" && reg2.observaciones === OBS &&
    reg2.usuario_codigo === `${VEND}` && reg2.usuario_nombre === "PRUEBA TALONARIO" &&
    reg2.estado === "CANCELADO" && n(reg2.rango_inicial) === 1 && n(reg2.rango_final) === 3 && !!reg2.fecha,
    reg2 && `unidad ${reg2.numero} · ${reg2.causal} · "${(reg2.observaciones || "").slice(0, 28)}..."`)

  const evi = reg2 ? (await pedidos.request().input("c", sql.Int, reg2.id)
    .query("SELECT origen, mime, tamano, ancho, alto FROM dbo.evidencias_archivos WHERE cancelacion_id=@c")).recordset : []
  ok("BD: la foto de la novedad queda ligada a la cancelacion",
    evi.length === 1 && evi[0].origen === "talonario" && evi[0].mime === "image/webp" && evi[0].tamano > 0,
    evi[0] && `${evi[0].tamano} bytes ${evi[0].ancho}x${evi[0].alto}`)

  const redisTrasCancelar = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: al cancelar una unidad se invalida la cache", !redis || redisTrasCancelar === null,
    redisTrasCancelar ? "quedo dato viejo" : "invalidada")

  const tras2 = await siguiente()
  ok("tras cancelar la 2 el sistema pasa a la unidad 3", n(tras2.json.data.siguiente) === 3,
    `sig=${tras2.json.data && tras2.json.data.siguiente}`)

  const canc3 = await cancelar({ causal: "Daño por mal manejo", observaciones: "Se rompio el formato" })
  ok("la cancelacion se puede repetir: la unidad 3 tambien se cancela",
    canc3.status === 200 && n(canc3.json.data.numeroCancelado) === 3, canc3.json && canc3.json.message)
  const numerosCancelados = (await pedidos.request().input("id", sql.Int, talA)
    .query("SELECT numero FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id ORDER BY numero")).recordset.map((r) => n(r.numero))
  ok("BD: quedan registradas las dos unidades canceladas, sin repetirse",
    JSON.stringify(numerosCancelados) === "[2,3]", numerosCancelados.join(","))

  const agotado = await siguiente()
  ok("agotado el talonario: no hay unidad disponible",
    agotado.json.data && agotado.json.data.siguiente == null && agotado.json.data.agotado === true,
    JSON.stringify(agotado.json.data || {}).slice(0, 90))
  const pagoAgotado = await pagar("agotado")
  const guardadoAgotado = (await pedidos.request().input("n", sql.NVarChar, `REC-TAL-${ts}-agotado`)
    .query("SELECT COUNT(*) n FROM dbo.recaudos WHERE numero_recaudo=@n")).recordset[0].n
  ok("sin unidad disponible el pago se rechaza con su motivo y no guarda nada",
    pagoAgotado.status === 409 && pagoAgotado.json.sinTalonario === true && pagoAgotado.json.agotado === true && guardadoAgotado === 0,
    `${pagoAgotado.status} · ${(pagoAgotado.json && pagoAgotado.json.message || "").slice(0, 60)}`)
  const cancAgotado = await cancelar({ causal: "Deterioro" })
  ok("sin unidad disponible tampoco se puede cancelar: 409", cancAgotado.status === 409, cancAgotado.json && cancAgotado.json.message)

  const cacheAgotado = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: el estado agotado no se cachea (Sistemas puede asignar otro talonario)",
    !redis || cacheAgotado === null, cacheAgotado ? "quedo cacheado" : "no cacheado")

  const talB = await crearTalonario(101, 110)
  const conNuevo = await siguiente()
  ok("con un talonario nuevo se sigue por su primera unidad (101)",
    conNuevo.json.data && conNuevo.json.data.talonarioId === talB && n(conNuevo.json.data.siguiente) === 101,
    `tal=${conNuevo.json.data && conNuevo.json.data.talonarioId} sig=${conNuevo.json.data && conNuevo.json.data.siguiente}`)
  const pagoNuevo = await pagar("b")
  ok("el pago se realiza con la unidad del talonario nuevo (101)",
    pagoNuevo.status === 200 && n(pagoNuevo.json.data.reciboCaja) === 101,
    `recibo=${pagoNuevo.json && pagoNuevo.json.data && pagoNuevo.json.data.reciboCaja}`)

  const cancB = await cancelar({ causal: "Deterioro", observaciones: "prueba de paso entre talonarios" })
  ok("cancelar en el talonario nuevo sigue la secuencia (102)",
    cancB.status === 200 && n(cancB.json.data.numeroCancelado) === 102 &&
    cancB.json.data.siguiente && n(cancB.json.data.siguiente.siguiente) === 103,
    cancB.json && cancB.json.message)

  const simultaneos = await Promise.all([pagar("s1"), pagar("s2"), pagar("s3"), pagar("s4")])
  const recibos = simultaneos.map((r) => (r.status === 200 && r.json.data ? n(r.json.data.reciboCaja) : null)).filter((v) => v != null).sort((a, b) => a - b)
  ok("concurrencia: 4 pagos simultaneos toman unidades distintas y consecutivas",
    recibos.length === 4 && new Set(recibos).size === 4 && JSON.stringify(recibos) === "[103,104,105,106]", recibos.join(","))

  const doblesCanc = await Promise.all([
    cancelar({ causal: "Deterioro" }),
    cancelar({ causal: "Daño por mal manejo" }),
  ])
  const numsCanc = doblesCanc.filter((r) => r.status === 200).map((r) => n(r.json.data.numeroCancelado)).sort((a, b) => a - b)
  ok("concurrencia: dos cancelaciones a la vez toman unidades distintas",
    numsCanc.length === 2 && new Set(numsCanc).size === 2 && JSON.stringify(numsCanc) === "[107,108]", numsCanc.join(","))

  const usadas = (await pedidos.request().input("t", sql.Int, talB).query(`
    SELECT numero FROM (
      SELECT recibo_caja AS numero FROM dbo.recaudos WHERE recibo_talonario_id=@t
      UNION ALL
      SELECT numero FROM dbo.talonarios_cancelaciones WHERE talonario_id=@t
    ) x ORDER BY numero
  `)).recordset.map((r) => n(r.numero))
  ok("integridad: ninguna unidad se usa dos veces (pagos y cancelaciones)",
    new Set(usadas).size === usadas.length && JSON.stringify(usadas) === "[101,102,103,104,105,106,107,108]", usadas.join(","))

  const antesErr = (await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("SELECT COUNT(*) n FROM dbo.recaudos WHERE cliente_id=@c")).recordset[0].n
  const conError = await llamar("POST", "/api/recaudos", { token, body: {
    numeroRecaudo: `REC-TAL-${ts}-err`, clienteId: CLIENTE, clienteNombre: "PRUEBA", formaPago: "Efectivo",
    totalDocumentos: 1000, totalAplicado: 1000, totalRecaudo: 1000, saldo: 0,
    documentos: [{ docEntry: 9, docNum: "F-ERR", numFactura: "FE-ERR", saldo: 1000, abono: 1000, dueDate: "X".repeat(50) }],
  } })
  const despuesErr = (await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("SELECT COUNT(*) n FROM dbo.recaudos WHERE cliente_id=@c")).recordset[0].n
  const unidadTrasErr = await siguiente()
  ok("transacciones: un fallo a mitad del pago hace rollback y no gasta la unidad",
    conError.status !== 200 && despuesErr === antesErr && n(unidadTrasErr.json.data.siguiente) === 109,
    `${conError.status} · ${antesErr} -> ${despuesErr} · sig=${unidadTrasErr.json.data && unidadTrasErr.json.data.siguiente}`)

  const sinCacheOk = await siguiente()
  ok("resiliencia: la consulta responde siempre", sinCacheOk.status === 200 && sinCacheOk.json.success === true)

  await limpiar()
  if (redis) { try { await redis.quit() } catch (_) {} }
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "TALONARIOS OK\n" : "HAY FALLOS EN TALONARIOS\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
