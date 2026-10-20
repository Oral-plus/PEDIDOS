// Una app vieja debe poder seguir registrando recaudos despues de este cambio.
//
// Las versiones anteriores ponen como abono el SALDO COMPLETO de la factura
// aunque el cobro sea parcial. El servidor no las rechaza: acomoda los abonos
// a la plata que de verdad entro. Si alguna vez esto empieza a fallar, un
// gestor en campo recibe dinero y no puede registrarlo.
const http = require("http")
const https = require("https")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const CLIENTE = "C-COMPAT-TEST"
const ts = Date.now()

function llamar(metodo, ruta, { body, token } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) { h["Content-Type"] = "application/json"; h["Content-Length"] = Buffer.byteLength(datos) }
    if (token) h.Authorization = `Bearer ${token}`
    const cliente = BASE.startsWith("https") ? https : http
    const req = cliente.request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const t = []
      res.on("data", (c) => t.push(c))
      res.on("end", () => { let j = null; try { j = JSON.parse(Buffer.concat(t).toString("utf8")) } catch (_) {} resolve({ status: res.statusCode, json: j }) })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}

async function esperar() {
  for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) }
  return false
}

const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })
const n = (v) => Number(v)

;(async () => {
  const out = []
  const ok = (t, c, extra) => out.push([t + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA COMPAT", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA COMPAT", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })

  const creados = []
  const leer = async (numero) => {
    const cab = (await pedidos.request().input("r", sql.NVarChar, numero)
      .query("SELECT id, total_recaudo, total_aplicado, saldo FROM dbo.recaudos WHERE numero_recaudo=@r")).recordset[0]
    if (!cab) return null
    creados.push(cab.id)
    const docs = (await pedidos.request().input("i", sql.Int, cab.id)
      .query("SELECT doc_entry, abono FROM dbo.recaudos_documentos WHERE recaudo_id=@i ORDER BY doc_entry")).recordset
    return { cab, docs }
  }

  try {
    // 1. El cuerpo exacto de una app vieja: cobro parcial de 200.000 sobre una
    //    factura de 498.828, con el abono puesto al saldo completo.
    const VIEJA = `REC-COMPAT-VIEJA-${ts}`
    const rv = await llamar("POST", "/api/recaudos", { token, body: {
      numeroRecaudo: VIEJA, clienteId: CLIENTE, clienteNombre: "PRUEBA COMPATIBILIDAD",
      formaPago: "Efectivo", totalDocumentos: 498828, totalAplicado: 498828,
      totalRecaudo: 200000, saldo: -298828,
      documentos: [{ docEntry: 900001, docNum: "F-COMPAT", numFactura: "F-COMPAT", saldo: 498828, abono: 498828, dueDate: "2026-09-30" }],
    } })
    ok("una app vieja con cobro parcial SIGUE pudiendo registrar el recaudo",
      rv.status === 200 && rv.json && rv.json.success === true, `status=${rv.status}`)

    const v = await leer(VIEJA)
    ok("el abono queda acomodado a la plata que de verdad entro",
      v && n(v.docs[0].abono) === 200000, v && `abono=${n(v.docs[0].abono)}`)
    ok("la cabecera queda cuadrada: aplicado = recaudado, saldo en cero",
      v && n(v.cab.total_aplicado) === 200000 && n(v.cab.saldo) === 0,
      v && `aplicado=${n(v.cab.total_aplicado)} saldo=${n(v.cab.saldo)}`)
    ok("el servidor avisa que lo ajusto, para que una app nueva pueda mostrarlo",
      rv.json && rv.json.ajustado === true)

    // 2. El cuerpo de la app nueva, que ya manda bien: no se le toca nada.
    const NUEVA = `REC-COMPAT-NUEVA-${ts}`
    const rn = await llamar("POST", "/api/recaudos", { token, body: {
      numeroRecaudo: NUEVA, clienteId: CLIENTE, clienteNombre: "PRUEBA COMPATIBILIDAD",
      formaPago: "Efectivo", totalDocumentos: 498828, totalAplicado: 200000,
      totalRecaudo: 200000, saldo: 0,
      documentos: [{ docEntry: 900002, docNum: "F-COMPAT2", numFactura: "F-COMPAT2", saldo: 498828, abono: 200000, dueDate: "2026-09-30" }],
    } })
    const nu = await leer(NUEVA)
    ok("la app nueva pasa sin que le ajusten nada",
      rn.status === 200 && rn.json && rn.json.success === true && rn.json.ajustado === false &&
      nu && n(nu.docs[0].abono) === 200000, nu && `abono=${n(nu.docs[0].abono)}`)

    // 3. Varias facturas de una app vieja: se reparte y la suma cuadra.
    const MULTI = `REC-COMPAT-MULTI-${ts}`
    await llamar("POST", "/api/recaudos", { token, body: {
      numeroRecaudo: MULTI, clienteId: CLIENTE, clienteNombre: "PRUEBA COMPATIBILIDAD",
      formaPago: "Efectivo", totalDocumentos: 1500000, totalAplicado: 1500000,
      totalRecaudo: 1000000, saldo: -500000,
      documentos: [
        { docEntry: 900003, docNum: "F-A", numFactura: "F-A", saldo: 600000, abono: 600000, dueDate: "2026-09-30" },
        { docEntry: 900004, docNum: "F-B", numFactura: "F-B", saldo: 900000, abono: 900000, dueDate: "2026-10-15" },
      ],
    } })
    const m = await leer(MULTI)
    const sumaM = m ? m.docs.reduce((s, d) => s + n(d.abono), 0) : -1
    ok("con varias facturas, los abonos suman exactamente lo recaudado",
      sumaM === 1000000, `${m && m.docs.map((d) => n(d.abono)).join(" + ")} = ${sumaM}`)
  } finally {
    for (const id of creados) {
      await pedidos.request().input("i", sql.Int, id).query("DELETE FROM dbo.recaudos_documentos WHERE recaudo_id=@i")
      await pedidos.request().input("i", sql.Int, id).query("DELETE FROM dbo.recaudos WHERE id=@i")
    }
    const quedan = (await pedidos.request().input("c", sql.NVarChar, CLIENTE)
      .query("SELECT COUNT(*) c FROM dbo.recaudos WHERE cliente_id=@c")).recordset[0].c
    out.push([`no queda basura de la prueba en la base  [${quedan} filas]`, quedan === 0])
    await pedidos.close()
  }

  for (const [t, bien] of out) process.stdout.write((bien ? "OK    " : "FALLA ") + t + "\n")
  const todo = out.every(([, bien]) => bien)
  process.stdout.write("\n" + (todo ? "COMPATIBILIDAD RECAUDOS OK\n" : "HAY FALLOS EN COMPATIBILIDAD\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("FALLA " + e.message + "\n"); process.exit(1) })
