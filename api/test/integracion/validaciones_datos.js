const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CLIENTE = `VALID${ts % 1000000}`

function llamar(metodo, ruta, { body, token } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) { h["Content-Type"] = "application/json"; h["Content-Length"] = Buffer.byteLength(datos) }
    if (token) h.Authorization = `Bearer ${token}`
    const req = http.request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const t = []
      res.on("data", (c) => t.push(c))
      res.on("end", () => { let j = null; try { j = JSON.parse(Buffer.concat(t).toString("utf8")) } catch (_) {} resolve({ status: res.statusCode, json: j }) })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}
async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = (d) => ({ server: process.env.DB_SERVER, database: d, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA VALIDACION", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA VALIDACION", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const cuenta = async (t, col, v) => (await pedidos.request().input("v", sql.NVarChar, v).query(`SELECT COUNT(*) n FROM ${t} WHERE ${col}=@v`)).recordset[0].n

  const docOk = { docEntry: 1, docNum: "F1", numFactura: "FE1", saldo: 100000, abono: 100000, dueDate: "2026-09-30" }
  const baseRec = { clienteId: CLIENTE, clienteNombre: "VALIDACION", formaPago: "Efectivo", totalDocumentos: 100000, totalAplicado: 100000, totalRecaudo: 100000, saldo: 0, documentos: [docOk] }

  const casos = [
    ["recaudo con valor recaudado en cero", { ...baseRec, numeroRecaudo: `V0-${ts}`, totalRecaudo: 0 }],
    ["recaudo con valor recaudado nulo", { ...baseRec, numeroRecaudo: `VN-${ts}`, totalRecaudo: null }],
    ["recaudo sin forma de pago", { ...baseRec, numeroRecaudo: `VF-${ts}`, formaPago: "" }],
    ["recaudo con total aplicado en cero", { ...baseRec, numeroRecaudo: `VA-${ts}`, totalAplicado: 0, documentos: [{ ...docOk, abono: 0 }] }],
    ["recaudo con un documento sin abono", { ...baseRec, numeroRecaudo: `VD-${ts}`, documentos: [{ ...docOk, abono: 0 }] }],
    ["recaudo cuyo aplicado no cuadra con los abonos", { ...baseRec, numeroRecaudo: `VC-${ts}`, totalAplicado: 999999 }],
  ]
  for (const [nombre, cuerpo] of casos) {
    const r = await llamar("POST", "/api/recaudos", { token, body: cuerpo })
    const guardado = await cuenta("dbo.recaudos", "numero_recaudo", cuerpo.numeroRecaudo)
    ok(`guarda tal cual: ${nombre}`, r.status === 200 && guardado === 1, `${r.status} · ${r.json && r.json.message}`)
    await pedidos.request().input("n", sql.NVarChar, cuerpo.numeroRecaudo).query("DELETE FROM dbo.recaudos WHERE numero_recaudo=@n")
  }

  const NUM_OK = `VOK-${ts}`
  const rOk = await llamar("POST", "/api/recaudos", { token, body: { ...baseRec, numeroRecaudo: NUM_OK, totalRecaudo: 150000, saldo: 50000 } })
  const recId = rOk.json && rOk.json.data && rOk.json.data.id
  const fila = recId ? (await pedidos.request().input("i", sql.Int, recId).query("SELECT total_recaudo, total_aplicado, forma_pago FROM dbo.recaudos WHERE id=@i")).recordset[0] : null
  ok("acepta el recaudo valido con sus importes reales", rOk.status === 200 && fila && Number(fila.total_recaudo) === 150000 && Number(fila.total_aplicado) === 100000 && fila.forma_pago === "Efectivo", fila && `recaudo=${Number(fila.total_recaudo)} aplicado=${Number(fila.total_aplicado)}`)
  if (recId) await pedidos.request().input("i", sql.Int, recId).query("DELETE FROM dbo.recaudos WHERE id=@i")

  const basePed = { cedula: CLIENTE, nombre: "VALIDACION", correo: "v@oral-plus.com", codigoCliente: CLIENTE, vendedor: "PRUEBA" }
  const casosPed = [
    ["pedido con producto sin código", { ...basePed, productos: [{ codigo: "", nombre: "X", cantidad: 1, precio: 1000 }] }],
    ["pedido con cantidad en cero", { ...basePed, productos: [{ codigo: "P1", nombre: "X", cantidad: 0, precio: 1000 }] }],
    ["pedido con precio en cero", { ...basePed, productos: [{ codigo: "P1", nombre: "X", cantidad: 1, precio: 0 }] }],
    ["pedido con precio nulo", { ...basePed, productos: [{ codigo: "P1", nombre: "X", cantidad: 1, precio: null }] }],
  ]
  const antes = await cuenta("pedidos", "codigo_cliente", CLIENTE)
  for (const [nombre, cuerpo] of casosPed) {
    const r = await llamar("POST", "/api/orders", { token, body: cuerpo })
    ok(`guarda tal cual: ${nombre}`, r.status === 200, `${r.status} · ${r.json && r.json.message}`)
  }
  const despues = await cuenta("pedidos", "codigo_cliente", CLIENTE)
  ok("todos los pedidos planos quedaron guardados", despues === antes + casosPed.length, `${antes} -> ${despues}`)

  const rPedOk = await llamar("POST", "/api/orders", { token, body: { ...basePed, productos: [{ codigo: "P1", nombre: "Producto", cantidad: 3, precio: 2000 }] } })
  const docNum = rPedOk.json && rPedOk.json.docNum
  const fPed = docNum ? (await pedidos.request().input("n", sql.NVarChar, docNum).query("SELECT id, total FROM pedidos WHERE numero_pedido=@n")).recordset[0] : null
  ok("acepta el pedido valido con su total real", rPedOk.status === 200 && fPed && Number(fPed.total) === 6000, fPed && `total=${Number(fPed.total)}`)
  if (fPed) {
    await pedidos.request().input("i", sql.Int, fPed.id).query("DELETE FROM pedidos_historial WHERE pedido_id=@i")
    await pedidos.request().input("i", sql.Int, fPed.id).query("DELETE FROM pedidos_detalle WHERE pedido_id=@i")
    await pedidos.request().input("i", sql.Int, fPed.id).query("DELETE FROM pedidos WHERE id=@i")
  }

  try {
    await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("DELETE h FROM pedidos_historial h JOIN pedidos p ON p.id=h.pedido_id WHERE p.codigo_cliente=@c")
    await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("DELETE d FROM pedidos_detalle d JOIN pedidos p ON p.id=d.pedido_id WHERE p.codigo_cliente=@c")
    await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("DELETE FROM pedidos WHERE codigo_cliente=@c")
  } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") }
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "VALIDACIONES DE DATOS OK\n" : "HAY FALLOS EN LAS VALIDACIONES\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
