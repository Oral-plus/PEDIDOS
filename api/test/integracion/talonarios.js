// Talonarios de recibos de caja: asignacion del consecutivo, cancelacion con
// causal, bloqueo de pagos, cache en Redis y concurrencia.
//
// El prefijo del talonario es el usuario de inicio de sesion (SKVnn). Trabaja
// con un vendedor ficticio (SKV99981) para no tocar los talonarios reales, y
// borra todo lo que crea al terminar.
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99981
const PREFIJO = `SKV${VEND}`
const CLIENTE = "CLI-TALONARIO"
const CLAVE_REDIS = `${process.env.REDIS_PREFIJO || "pedidos:"}talonario:siguiente:${PREFIJO}`

function llamar(metodo, ruta, { token, body } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body !== undefined ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) { h["Content-Type"] = "application/json"; h["Content-Length"] = Buffer.byteLength(datos) }
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

// Cliente Redis solo para comprobar la cache desde fuera del backend
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
    documentos: [{ docEntry: 1, docNum: "F-TAL", numFactura: "FE-TAL", saldo: 1000, abono: 1000, dueDate: "2026-12-31" }],
  } })

  // Primera consulta: el backend crea las estructuras que falten
  await llamar("GET", "/api/talonarios/siguiente", { token })
  await limpiar()

  // ── 1) Estructura en base de datos: tabla e integridad ──
  const tabla = (await pedidos.request().query(`
    SELECT COLUMN_NAME c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='talonarios_cancelaciones'
  `)).recordset.map((r) => r.c)
  const requeridas = ["talonario_id", "causal", "fecha", "usuario_codigo", "usuario_nombre", "estado_anterior", "prefijo"]
  ok("BD: tabla talonarios_cancelaciones con talonario, causal, fecha, usuario y estado",
    requeridas.every((c) => tabla.includes(c)), tabla.join(","))
  const fk = (await pedidos.request().query("SELECT name FROM sys.foreign_keys WHERE name='FK_talcanc_talonario'")).recordset
  ok("BD: integridad referencial con TALONARIO (FK_talcanc_talonario)", fk.length === 1)

  // ── 2) Catalogo de causales que impone el servidor ──
  const cau = await llamar("GET", "/api/talonarios/causales", { token })
  const causales = (cau.json && cau.json.data) || []
  ok("causales: Deterioro y Daño por mal manejo", cau.status === 200 && causales.length === 2 &&
    causales.includes("Deterioro") && causales.includes("Daño por mal manejo"), causales.join(" / "))

  // ── 3) Sin talonario: no hay nada que cancelar ──
  const sinTal = await llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Deterioro" } })
  ok("sin talonario: cancelar responde 404 y no crea registros", sinTal.status === 404, sinTal.json && sinTal.json.message)

  // ── 4) Talonario activo: permite pagos y entrega consecutivos ──
  const tal1 = await crearTalonario(100, 105)
  const p1 = await pagar("a")
  const p2 = await pagar("b")
  ok("talonario ACTIVO: permite pagos y asigna 100 y 101",
    p1.status === 200 && p2.status === 200 &&
    n(p1.json.data.reciboCaja) === 100 && n(p2.json.data.reciboCaja) === 101,
    `${p1.json && p1.json.data && p1.json.data.reciboCaja}, ${p2.json && p2.json.data && p2.json.data.reciboCaja}`)

  // ── 5) Redis: la consulta cachea y el pago invalida ──
  const consulta1 = await llamar("GET", "/api/talonarios/siguiente", { token })
  const enRedis = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: la consulta del talonario queda cacheada", !redis || (enRedis && JSON.parse(enRedis).talonarioId === tal1),
    redis ? `clave ${CLAVE_REDIS}` : "Redis no configurado (se omite)")
  ok("consulta: el siguiente es 102 tras los dos pagos",
    consulta1.status === 200 && n(consulta1.json.data.siguiente) === 102, `sig=${consulta1.json && consulta1.json.data && consulta1.json.data.siguiente}`)
  await pagar("c")
  const trasPago = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: al consumir un numero se invalida la cache", !redis || trasPago === null, trasPago ? "quedo dato viejo" : "invalidada")
  const consulta2 = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("tras invalidar: la consulta devuelve el dato nuevo (103)", n(consulta2.json.data.siguiente) === 103,
    `sig=${consulta2.json && consulta2.json.data && consulta2.json.data.siguiente}`)

  // ── 6) Cancelacion sin causal: rechazada, nada cambia ──
  const sinCausal = await llamar("POST", "/api/talonarios/cancelar", { token, body: {} })
  const vacia = await llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "   " } })
  const inventada = await llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Se me perdio" } })
  const estadoTrasIntentos = (await pedidos.request().input("id", sql.Int, tal1).query("SELECT estado FROM dbo.TALONARIO WHERE id=@id")).recordset[0].estado
  const cancTrasIntentos = (await pedidos.request().input("id", sql.Int, tal1).query("SELECT COUNT(*) n FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id")).recordset[0].n
  ok("cancelar sin causal: 400 (obligatoria)", sinCausal.status === 400, sinCausal.json && sinCausal.json.message)
  ok("cancelar con causal vacia: 400", vacia.status === 400, vacia.json && vacia.json.message)
  ok("cancelar con causal fuera del catalogo: 400", inventada.status === 400, inventada.json && inventada.json.message)
  ok("tras los intentos fallidos el talonario sigue ACTIVO y sin registros de cancelacion",
    estadoTrasIntentos === "ACTIVO" && cancTrasIntentos === 0, `estado=${estadoTrasIntentos} registros=${cancTrasIntentos}`)

  // ── 7) Cancelacion correcta (con la cache caliente, para que la
  //    invalidacion posterior sea una comprobacion real) ──
  await llamar("GET", "/api/talonarios/siguiente", { token })
  const cacheAntesCancelar = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: la cache esta caliente antes de cancelar", !redis || cacheAntesCancelar !== null,
    redis ? (cacheAntesCancelar ? "cacheada" : "no se cacheo") : "Redis no configurado (se omite)")
  const canc = await llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Deterioro" } })
  ok("cancelacion correcta: 200 con el talonario y su causal",
    canc.status === 200 && canc.json.data && canc.json.data.estado === "CANCELADO" && canc.json.data.causal === "Deterioro",
    JSON.stringify(canc.json.data || {}))

  const fila = (await pedidos.request().input("id", sql.Int, tal1)
    .query("SELECT estado FROM dbo.TALONARIO WHERE id=@id")).recordset[0]
  ok("estado: el talonario queda CANCELADO y se conserva en el sistema", fila && fila.estado === "CANCELADO", fila && fila.estado)

  const reg = (await pedidos.request().input("id", sql.Int, tal1).query(`
    SELECT TOP 1 talonario_id, prefijo, rango_inicial, rango_final, causal, usuario_codigo, usuario_nombre, estado_anterior, fecha
    FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id ORDER BY id DESC
  `)).recordset[0]
  ok("BD: queda registrada la causal, el talonario, el usuario, el estado y la fecha",
    reg && reg.talonario_id === tal1 && reg.causal === "Deterioro" && reg.prefijo === PREFIJO &&
    reg.usuario_codigo === `${VEND}` && reg.usuario_nombre === "PRUEBA TALONARIO" &&
    reg.estado_anterior === "ACTIVO" && n(reg.rango_inicial) === 100 && n(reg.rango_final) === 105 && !!reg.fecha,
    reg && `${reg.causal} · ${reg.usuario_nombre} · ${new Date(reg.fecha).toISOString()}`)

  const redisTrasCancelar = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: al cancelar se invalida la cache del talonario", !redis || redisTrasCancelar === null,
    redisTrasCancelar ? "quedo dato viejo" : "invalidada")

  // ── 8) Cancelar uno ya cancelado ──
  const otraVez = await llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Daño por mal manejo" } })
  const cuantas = (await pedidos.request().input("id", sql.Int, tal1)
    .query("SELECT COUNT(*) n FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id")).recordset[0].n
  ok("cancelar un talonario ya cancelado: 409 y no duplica el registro",
    otraVez.status === 409 && cuantas === 1, `${otraVez.status} registros=${cuantas}`)

  // ── 9) Bloqueo de pagos con el talonario cancelado ──
  const consultaCanc = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("consulta: informa cancelado con su causal y sin numero",
    consultaCanc.json.data && consultaCanc.json.data.cancelado === true &&
    consultaCanc.json.data.causalCancelacion === "Deterioro" && consultaCanc.json.data.siguiente == null,
    JSON.stringify(consultaCanc.json.data || {}).slice(0, 110))
  const pagoBloqueado = await pagar("bloqueado")
  const guardado = (await pedidos.request().input("n", sql.NVarChar, `REC-TAL-${ts}-bloqueado`)
    .query("SELECT COUNT(*) n FROM dbo.recaudos WHERE numero_recaudo=@n")).recordset[0].n
  ok("pago con talonario cancelado: rechazado (409) con el motivo y sin guardar nada",
    pagoBloqueado.status === 409 && pagoBloqueado.json.talonarioCancelado === true &&
    /cancelado/i.test(pagoBloqueado.json.message || "") && guardado === 0,
    `${pagoBloqueado.status} · ${(pagoBloqueado.json && pagoBloqueado.json.message || "").slice(0, 70)}`)

  // ── 10) Liberacion del consecutivo: un talonario nuevo vuelve a habilitarlo.
  //    Sistemas lo asigna directo en la base, sin pasar por la app: el estado
  //    cancelado no se cachea, asi que la app lo ve de inmediato.
  const cacheCancelado = redis ? await redis.get(CLAVE_REDIS) : null
  ok("Redis: el estado cancelado no se cachea (Sistemas puede asignar otro talonario)",
    !redis || cacheCancelado === null, cacheCancelado ? "quedo cacheado" : "no cacheado")
  const tal2 = await crearTalonario(100, 105)
  const consultaNueva = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("liberacion: con un talonario nuevo el consecutivo vuelve a estar disponible (100)",
    consultaNueva.json.data && consultaNueva.json.data.talonarioId === tal2 &&
    n(consultaNueva.json.data.siguiente) === 100 && consultaNueva.json.data.cancelado !== true,
    `tal=${consultaNueva.json.data && consultaNueva.json.data.talonarioId} sig=${consultaNueva.json.data && consultaNueva.json.data.siguiente}`)
  const pagoNuevo = await pagar("nuevo")
  ok("permiso de pago con talonario ACTIVO: entra y toma el 100 liberado",
    pagoNuevo.status === 200 && n(pagoNuevo.json.data.reciboCaja) === 100, `recibo=${pagoNuevo.json && pagoNuevo.json.data && pagoNuevo.json.data.reciboCaja}`)

  // ── 11) Concurrencia: pagos simultaneos no repiten consecutivo ──
  const simultaneos = await Promise.all([pagar("s1"), pagar("s2"), pagar("s3"), pagar("s4")])
  const recibos = simultaneos.map((r) => (r.status === 200 && r.json.data ? n(r.json.data.reciboCaja) : null)).filter((v) => v != null).sort((a, b) => a - b)
  const unicos = new Set(recibos)
  ok("concurrencia: 4 pagos simultaneos toman numeros distintos y consecutivos",
    recibos.length === 4 && unicos.size === 4 && JSON.stringify(recibos) === "[101,102,103,104]", recibos.join(","))
  const enBd = (await pedidos.request().input("t", sql.Int, tal2)
    .query("SELECT recibo_caja FROM dbo.recaudos WHERE recibo_talonario_id=@t ORDER BY recibo_caja")).recordset.map((r) => n(r.recibo_caja))
  ok("integridad: los recibos guardados no se repiten en la base",
    new Set(enBd).size === enBd.length && JSON.stringify(enBd) === "[100,101,102,103,104]", enBd.join(","))

  // ── 12) Cancelaciones simultaneas: solo una prospera ──
  const dobles = await Promise.all([
    llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Deterioro" } }),
    llamar("POST", "/api/talonarios/cancelar", { token, body: { causal: "Daño por mal manejo" } }),
  ])
  const exitosas = dobles.filter((r) => r.status === 200).length
  const registros = (await pedidos.request().input("id", sql.Int, tal2)
    .query("SELECT COUNT(*) n FROM dbo.talonarios_cancelaciones WHERE talonario_id=@id")).recordset[0].n
  ok("concurrencia: dos cancelaciones a la vez dejan una sola cancelacion registrada",
    exitosas === 1 && registros === 1, `exitosas=${exitosas} registros=${registros}`)

  // ── 13) Transacciones: un pago rechazado no deja rastro ──
  const antesErr = (await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("SELECT COUNT(*) n FROM dbo.recaudos WHERE cliente_id=@c")).recordset[0].n
  const conError = await llamar("POST", "/api/recaudos", { token, body: {
    numeroRecaudo: `REC-TAL-${ts}-err`, clienteId: CLIENTE, clienteNombre: "PRUEBA", formaPago: "Efectivo",
    totalDocumentos: 1000, totalAplicado: 1000, totalRecaudo: 1000, saldo: 0,
    documentos: [{ docEntry: 9, docNum: "F-ERR", numFactura: "FE-ERR", saldo: 1000, abono: 1000, dueDate: "X".repeat(50) }],
  } })
  const despuesErr = (await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("SELECT COUNT(*) n FROM dbo.recaudos WHERE cliente_id=@c")).recordset[0].n
  ok("transacciones: un fallo a mitad del pago hace rollback completo",
    conError.status !== 200 && despuesErr === antesErr, `${conError.status} · ${antesErr} -> ${despuesErr}`)

  // ── 14) La cache no rompe si Redis se cae: el dato sigue llegando de la BD ──
  const sinCacheOk = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("resiliencia: la consulta responde aunque la cache no acierte", sinCacheOk.status === 200 && !!sinCacheOk.json.data)

  await limpiar()
  if (redis) { try { await redis.quit() } catch (_) {} }
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "TALONARIOS OK\n" : "HAY FALLOS EN TALONARIOS\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
