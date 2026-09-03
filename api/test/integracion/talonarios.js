// Recibos de caja por talonario (dbo.TALONARIO): el prefijo del talonario es
// el usuario de inicio de sesion (SKVnn). Cada recaudo consume el consecutivo
// del rango [inicial, final] sin repetirse; agotado el rango, el recaudo entra
// sin recibo (insercion plana). Crea un talonario de prueba y lo borra al final.
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99981 // vendedor ficticio solo para esta prueba
const PREFIJO = `SKV${VEND}`

function llamar(metodo, ruta, { token, body } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? JSON.stringify(body) : null
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

;(async () => {
  const out = []
  const ok = (nm, c, extra) => out.push([nm + (extra ? `  [${extra}]` : ""), !!c])
  const n = (v) => (v == null ? null : Number(v))
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${VEND}`, usuarioNombre: "PRUEBA TALONARIO", tipo: "vendedor", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: VEND, nombre: "PRUEBA TALONARIO", tipo: "vendedor", jti }, process.env.JWT_SECRET, { expiresIn: 900 })

  // Primera consulta: obliga al backend a crear las columnas de recibo si faltan
  await llamar("GET", "/api/talonarios/siguiente", { token })

  // Limpieza previa por si quedo algo de una corrida anterior
  await pedidos.request().input("p", sql.NVarChar, PREFIJO).query("DELETE FROM dbo.recaudos WHERE recibo_prefijo=@p OR cliente_id='CLI-TALONARIO'")
  await pedidos.request().input("p", sql.NVarChar, PREFIJO).query("DELETE FROM dbo.TALONARIO WHERE prefijo=@p")

  // ── 1) Sin talonario: la consulta lo dice y el recaudo entra sin recibo ──
  const sin = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("sin talonario: la consulta responde sinTalonario", sin.status === 200 && sin.json.sinTalonario === true, JSON.stringify(sin.json).slice(0, 80))

  // ── 2) Talonario del usuario (prefijo = usuario de sesion), rango 100-102 ──
  await pedidos.request().input("v", sql.Int, VEND).input("p", sql.NVarChar, PREFIJO).query(`
    INSERT INTO dbo.TALONARIO (vendedor_codigo, vendedor_nombre, prefijo, tipo_recibo, rango_inicial, rango_final, estado, usuario, fecha)
    VALUES (@v, 'PRUEBA TALONARIO', @p, 'RECIBO DE CAJA', 100, 102, 'ACTIVO', 'prueba', GETDATE())
  `)
  const s1 = await llamar("GET", "/api/talonarios/siguiente", { token })
  const d1 = s1.json && s1.json.data
  ok("con talonario: el siguiente es el rango inicial (100)", s1.status === 200 && d1 && n(d1.siguiente) === 100 && n(d1.rangoFinal) === 102 && d1.agotado === false, d1 && `sig=${d1.siguiente} disp=${d1.disponibles}`)

  // ── 3) Tres pagos consumen 100, 101 y 102 sin repetirse ──
  const doc = { docEntry: 1, docNum: "F-TAL", numFactura: "FE-TAL", saldo: 1000, abono: 1000, dueDate: "2026-12-31" }
  const recibos = []
  for (let i = 0; i < 3; i++) {
    const r = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: `REC-TAL-${ts}-${i}`, clienteId: "CLI-TALONARIO", clienteNombre: "PRUEBA", formaPago: "Efectivo", totalDocumentos: 1000, totalAplicado: 1000, totalRecaudo: 1000, saldo: 0, documentos: [doc] } })
    recibos.push(r.json && r.json.data ? n(r.json.data.reciboCaja) : null)
  }
  ok("tres pagos seguidos: recibos 100, 101 y 102 sin repetir", JSON.stringify(recibos) === "[100,101,102]", recibos.join(","))
  const enBd = (await pedidos.request().input("p", sql.NVarChar, PREFIJO)
    .query("SELECT recibo_caja FROM dbo.recaudos WHERE recibo_prefijo=@p ORDER BY recibo_caja")).recordset.map((r) => n(r.recibo_caja))
  ok("los recibos quedaron insertados en la BD junto al recaudo", JSON.stringify(enBd) === "[100,101,102]", enBd.join(","))

  // ── 4) Rango agotado: la consulta avisa y el pago entra sin recibo ──
  const s2 = await llamar("GET", "/api/talonarios/siguiente", { token })
  ok("agotado: la consulta lo informa", s2.status === 200 && s2.json.data && s2.json.data.agotado === true && s2.json.data.siguiente == null, JSON.stringify(s2.json.data).slice(0, 100))
  const r4 = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: `REC-TAL-${ts}-x`, clienteId: "CLI-TALONARIO", clienteNombre: "PRUEBA", formaPago: "Efectivo", totalDocumentos: 1000, totalAplicado: 1000, totalRecaudo: 1000, saldo: 0, documentos: [doc] } })
  ok("agotado: el pago entra igual, con recibo en blanco", r4.status === 200 && r4.json.data && r4.json.data.reciboCaja == null, `recibo=${r4.json && r4.json.data && r4.json.data.reciboCaja}`)

  // Limpieza
  await pedidos.request().input("p", sql.NVarChar, PREFIJO).query("DELETE FROM dbo.recaudos WHERE recibo_prefijo=@p OR cliente_id='CLI-TALONARIO'")
  await pedidos.request().input("p", sql.NVarChar, PREFIJO).query("DELETE FROM dbo.TALONARIO WHERE prefijo=@p")
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "TALONARIOS OK\n" : "HAY FALLOS EN TALONARIOS\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
