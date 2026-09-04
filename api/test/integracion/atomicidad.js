const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"

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

async function esperar() {
  for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) }
  return false
}

const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA ATOMICA", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA ATOMICA", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })

  const ts = Date.now()
  const CLIENTE_ATOM = `ATOM${ts % 100000000}`
  const cont = async (q, inp) => { const r = pedidos.request(); for (const [k, t, v] of inp) r.input(k, t, v); return (await r.query(q)).recordset[0].n }

  const nombreLargo = "X".repeat(300)
  const antesPed = await cont("SELECT COUNT(*) n FROM pedidos WHERE codigo_cliente=@c", [["c", sql.NVarChar, CLIENTE_ATOM]])
  const rPedMal = await llamar("POST", "/api/orders", { token, body: { cedula: CLIENTE_ATOM, nombre: "PRUEBA", correo: "a@oral-plus.com", codigoCliente: CLIENTE_ATOM, vendedor: "PRUEBA", productos: [
    { codigo: "OK1", nombre: "Producto bueno", cantidad: 1, precio: 1000 },
    { codigo: "BAD", nombre: nombreLargo, cantidad: 1, precio: 1000 },
  ] } })
  const despuesPed = await cont("SELECT COUNT(*) n FROM pedidos WHERE codigo_cliente=@c", [["c", sql.NVarChar, CLIENTE_ATOM]])
  const huerfDet = await cont("SELECT COUNT(*) n FROM pedidos_detalle d JOIN pedidos p ON p.id=d.pedido_id WHERE p.codigo_cliente=@c", [["c", sql.NVarChar, CLIENTE_ATOM]])
  ok("pedido: el detalle invalido NO deja cabecera (rollback)", rPedMal.status !== 200 && despuesPed === antesPed, `status=${rPedMal.status} pedidos ${antesPed}->${despuesPed}`)
  ok("pedido: no quedaron lineas de detalle huerfanas", huerfDet === 0, `detalle=${huerfDet}`)

  const rPedOk = await llamar("POST", "/api/orders", { token, body: { cedula: CLIENTE_ATOM, nombre: "PRUEBA", correo: "a@oral-plus.com", codigoCliente: CLIENTE_ATOM, vendedor: "PRUEBA", productos: [
    { codigo: "OK1", nombre: "Producto A", cantidad: 2, precio: 1500 },
    { codigo: "OK2", nombre: "Producto B", cantidad: 1, precio: 3000 },
  ] } })
  const docNum = rPedOk.json && rPedOk.json.docNum
  const pid = docNum ? (await pedidos.request().input("n", sql.NVarChar, docNum).query("SELECT id FROM pedidos WHERE numero_pedido=@n")).recordset[0].id : null
  const det = pid ? await cont("SELECT COUNT(*) n FROM pedidos_detalle WHERE pedido_id=@id", [["id", sql.Int, pid]]) : 0
  const his = pid ? await cont("SELECT COUNT(*) n FROM pedidos_historial WHERE pedido_id=@id", [["id", sql.Int, pid]]) : 0
  ok("pedido valido: cabecera + 2 detalle + 1 historial (commit completo)", rPedOk.status === 200 && pid && det === 2 && his === 1, `det=${det} hist=${his}`)
  if (pid) {
    await pedidos.request().input("id", sql.Int, pid).query("DELETE FROM pedidos_historial WHERE pedido_id=@id")
    await pedidos.request().input("id", sql.Int, pid).query("DELETE FROM pedidos_detalle WHERE pedido_id=@id")
    await pedidos.request().input("id", sql.Int, pid).query("DELETE FROM pedidos WHERE id=@id")
  }

  const RECMAL = `REC-ATOM-MAL-${ts}`
  const antesRec = await cont("SELECT COUNT(*) n FROM dbo.recaudos WHERE numero_recaudo=@r", [["r", sql.NVarChar, RECMAL]])
  const rRecMal = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: RECMAL, clienteId: CLIENTE_ATOM, clienteNombre: "PRUEBA", formaPago: "Efectivo", totalAplicado: 1000, totalRecaudo: 1000, documentos: [
    { docEntry: 1, docNum: "F1", numFactura: "F1", saldo: 1000, abono: 1000, dueDate: "X".repeat(50) },
  ] } })
  const despuesRec = await cont("SELECT COUNT(*) n FROM dbo.recaudos WHERE numero_recaudo=@r", [["r", sql.NVarChar, RECMAL]])
  ok("recaudo: el documento invalido NO deja cabecera (rollback)", rRecMal.status !== 200 && despuesRec === antesRec, `status=${rRecMal.status} recaudos ${antesRec}->${despuesRec}`)

  const RECOK = `REC-ATOM-OK-${ts}`
  const rRecOk = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: RECOK, clienteId: CLIENTE_ATOM, clienteNombre: "PRUEBA", formaPago: "Efectivo", totalAplicado: 2000, totalRecaudo: 2000, documentos: [
    { docEntry: 1, docNum: "F1", numFactura: "F1", saldo: 1000, abono: 1000, dueDate: "2026-09-30" },
    { docEntry: 2, docNum: "F2", numFactura: "F2", saldo: 1000, abono: 1000, dueDate: "2026-10-15" },
  ] } })
  const rid = rRecOk.json && rRecOk.json.data && rRecOk.json.data.id
  const rdocs = rid ? await cont("SELECT COUNT(*) n FROM dbo.recaudos_documentos WHERE recaudo_id=@id", [["id", sql.Int, rid]]) : 0
  ok("recaudo valido: cabecera + 2 documentos (commit completo)", rRecOk.status === 200 && rid && rdocs === 2, `docs=${rdocs}`)
  if (rid) {
    await pedidos.request().input("id", sql.Int, rid).query("DELETE FROM dbo.recaudos_documentos WHERE recaudo_id=@id")
    await pedidos.request().input("id", sql.Int, rid).query("DELETE FROM dbo.recaudos WHERE id=@id")
  }

  await pedidos.request().input("c", sql.NVarChar, CLIENTE_ATOM).query("DELETE d FROM pedidos_detalle d JOIN pedidos p ON p.id=d.pedido_id WHERE p.codigo_cliente=@c")
  await pedidos.request().input("c", sql.NVarChar, CLIENTE_ATOM).query("DELETE h FROM pedidos_historial h JOIN pedidos p ON p.id=h.pedido_id WHERE p.codigo_cliente=@c")
  await pedidos.request().input("c", sql.NVarChar, CLIENTE_ATOM).query("DELETE FROM pedidos WHERE codigo_cliente=@c")
  await pedidos.request().input("r", sql.NVarChar, `REC-ATOM-%${ts}`).query("DELETE d FROM dbo.recaudos_documentos d JOIN dbo.recaudos r ON r.id=d.recaudo_id WHERE r.numero_recaudo LIKE @r")
  await pedidos.request().input("r", sql.NVarChar, `REC-ATOM-%`).input("c", sql.NVarChar, CLIENTE_ATOM).query("DELETE FROM dbo.recaudos WHERE cliente_id=@c")
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "ATOMICIDAD OK\n" : "FALLO DE ATOMICIDAD\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
