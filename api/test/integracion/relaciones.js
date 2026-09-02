// Valida la relacion por clave foranea (recaudo_id) entre recaudos y sus hijos.
// recaudos, evidencias_archivos y pedidos_gestion viven en la BD Pedidos -> FK real.
// visitas_clientes vive en la BD Ruta -> se guarda recaudo_id como referencia por id
// (SQL Server no permite FK entre bases distintas).
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CLIENTE = `RELFK${ts % 100000000}`
const NUM_RECAUDO = `REC-REL-${ts}`

function llamar(metodo, ruta, { body, token, mp } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : (body ? JSON.stringify(body) : null)
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
    else if (datos) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = datos.length
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

function multipart(campos, archivo) {
  const limite = "----rel" + ts
  const partes = []
  for (const [k, v] of Object.entries(campos)) partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${archivo.campo}"; filename="${archivo.nombre}"\r\nContent-Type: ${archivo.mime}\r\n\r\n`))
  partes.push(archivo.contenido); partes.push(Buffer.from(`\r\n--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = (d) => ({ server: process.env.DB_SERVER, database: d, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const ruta = await new sql.ConnectionPool(cfg(process.env.RUTA_DB_NAME || "Ruta")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA REL", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA REL", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const png = await sharp({ create: { width: 400, height: 300, channels: 3, background: { r: 10, g: 100, b: 100 } } }).png().toBuffer()
  const uno = async (q, i) => { const r = pedidos.request(); for (const [k, t, v] of i) r.input(k, t, v); return (await r.query(q)).recordset[0] }
  const unoR = async (q, i) => { const r = ruta.request(); for (const [k, t, v] of i) r.input(k, t, v); return (await r.query(q)).recordset[0] }

  // Recaudo padre
  const rRec = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE, clienteNombre: "PRUEBA", formaPago: "Efectivo", totalAplicado: 5000, totalRecaudo: 5000, documentos: [{ docEntry: 1, docNum: "F1", numFactura: "F1", saldo: 5000, abono: 5000, dueDate: "2026-09-30" }] } })
  const recaudoId = rRec.json && rRec.json.data && rRec.json.data.id
  ok("recaudo creado y devuelve id", rRec.status === 200 && recaudoId, `id=${recaudoId}`)

  // Evidencia -> recaudo_id debe igualar el id del recaudo
  const rEvi = await llamar("POST", "/api/evidencias", { token, mp: multipart({ origen: "recaudo", numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE }, { campo: "foto", nombre: "e.png", mime: "image/png", contenido: png }) })
  const eviId = rEvi.json && rEvi.json.data && rEvi.json.data.id
  const fEvi = eviId ? await uno("SELECT recaudo_id, numero_recaudo FROM dbo.evidencias_archivos WHERE id=@id", [["id", sql.Int, eviId]]) : null
  ok("evidencia: recaudo_id = id del recaudo (FK)", fEvi && fEvi.recaudo_id === recaudoId, `recaudo_id=${fEvi && fEvi.recaudo_id} esperado ${recaudoId}`)

  // Gestion -> recaudo_id
  const rGes = await llamar("POST", "/api/pedidos/gestion", { token, body: { clienteId: CLIENTE, clienteNombre: "PRUEBA", total: 1000, formaPago: "Efectivo", numeroRecaudo: NUM_RECAUDO, estado: "GUARDADO" } })
  const gesId = rGes.json && rGes.json.data && rGes.json.data.id
  const fGes = gesId ? await uno("SELECT recaudo_id FROM dbo.pedidos_gestion WHERE id=@id", [["id", sql.Int, gesId]]) : null
  ok("gestion: recaudo_id = id del recaudo (FK)", fGes && fGes.recaudo_id === recaudoId, `recaudo_id=${fGes && fGes.recaudo_id}`)

  // Visita -> recaudo_id (referencia por id entre BD, sin FK)
  const rVis = await llamar("POST", `/api/clientes/${CLIENTE}/visita`, { token, body: { observacion: "prueba rel", metodoPago: "Transferencia", numeroRecaudo: NUM_RECAUDO, totalRecaudos: 5000 } })
  const visId = rVis.json && rVis.json.data && rVis.json.data.id
  const fVis = visId ? await unoR("SELECT recaudo_id FROM visitas_clientes WHERE id=@id", [["id", sql.Int, visId]]) : null
  ok("visita: recaudo_id = id del recaudo (referencia entre BD)", fVis && fVis.recaudo_id === recaudoId, `recaudo_id=${fVis && fVis.recaudo_id}`)

  // Las FK existen en la BD Pedidos
  const fks = (await pedidos.request().query("SELECT name FROM sys.foreign_keys WHERE name IN ('FK_evid_recaudo','FK_pedgest_recaudo','FK_recdoc_recaudo')")).recordset.map((r) => r.name)
  ok("FK declaradas: FK_evid_recaudo, FK_pedgest_recaudo, FK_recdoc_recaudo", fks.length === 3, fks.join(","))

  // La FK IMPIDE borrar el recaudo mientras tenga hijos (evidencia/gestion/documentos)
  let bloqueo = false, msg = ""
  try {
    await pedidos.request().input("id", sql.Int, recaudoId).query("DELETE FROM dbo.recaudos WHERE id=@id")
  } catch (e) { bloqueo = true; msg = e.message.split(".")[0] }
  ok("la FK impide borrar el recaudo con hijos (integridad referencial)", bloqueo, msg)

  // limpieza en orden (hijos -> padre)
  try {
    if (eviId) await pedidos.request().input("id", sql.Int, eviId).query("DELETE FROM dbo.evidencias_archivos WHERE id=@id")
    if (gesId) await pedidos.request().input("id", sql.Int, gesId).query("DELETE FROM dbo.pedidos_gestion WHERE id=@id")
    if (visId) await ruta.request().input("id", sql.Int, visId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM visitas_clientes WHERE id=@id AND cliente_id=@c")
    if (recaudoId) {
      await pedidos.request().input("id", sql.Int, recaudoId).query("DELETE FROM dbo.recaudos_documentos WHERE recaudo_id=@id")
      await pedidos.request().input("id", sql.Int, recaudoId).query("DELETE FROM dbo.recaudos WHERE id=@id")
    }
    await sesiones.cerrar(pedidos, sql, jti, "prueba")
  } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") }
  await pedidos.close(); await ruta.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "RELACIONES FK OK\n" : "FALLO DE RELACIONES FK\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
