const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CLIENTE = `ATOMREC${ts % 1000000}`

function llamar(metodo, ruta, { token, mp, body, raw } = {}) {
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
      res.on("end", () => {
        const buf = Buffer.concat(t)
        if (raw) return resolve({ status: res.statusCode, headers: res.headers, buf })
        let j = null; try { j = JSON.parse(buf.toString("utf8")) } catch (_) {}
        resolve({ status: res.statusCode, json: j })
      })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}

function multipart(campos, archivos) {
  const limite = "----atom" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [k, v] of Object.entries(campos)) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  }
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${a.campo}"; filename="${a.nombre}"\r\nContent-Type: ${a.mime}\r\n\r\n`))
    partes.push(a.contenido)
    partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = (d) => ({ server: process.env.DB_SERVER, database: d, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA ATOMICA REC", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA ATOMICA REC", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const uno = async (q, i) => { const r = pedidos.request(); for (const [k, t, v] of i) r.input(k, t, v); return (await r.query(q)).recordset[0] }
  const cuenta = async (t, col, v) => (await uno(`SELECT COUNT(*) n FROM ${t} WHERE ${col}=@v`, [["v", sql.NVarChar, v]])).n

  const foto = async (w, color) => sharp({ create: { width: w, height: 600, channels: 3, background: color } }).png().toBuffer()
  const docsOk = [
    { docEntry: 201, docNum: "FV-2001", numFactura: "FE2001", saldo: 400000, abono: 400000, dueDate: "2026-09-30" },
    { docEntry: 202, docNum: "FV-2002", numFactura: "FE2002", saldo: 300000, abono: 200000, dueDate: "2026-10-10" },
  ]

  const NUM_OK = `REC-ATOM-OK-${ts}`
  const campos = {
    numeroRecaudo: NUM_OK, clienteId: CLIENTE, clienteNombre: "CLIENTE ATOMICO",
    formaPago: "Transferencia", bancoPago: "Bancolombia", referenciaPago: "TRF-ATOM-1",
    totalDocumentos: 700000, totalAplicado: 600000, totalRecaudo: 600000, saldo: 100000,
    notas: "Recaudo atomico con evidencias", documentos: JSON.stringify(docsOk),
  }
  const archivos = [
    { campo: "fotos", nombre: "e1.png", mime: "image/png", contenido: await foto(900, { r: 190, g: 40, b: 40 }) },
    { campo: "fotos", nombre: "e2.png", mime: "image/png", contenido: await foto(1000, { r: 20, g: 120, b: 80 }) },
  ]
  const r1 = await llamar("POST", "/api/recaudos", { token, mp: multipart(campos, archivos) })
  const recId = r1.json && r1.json.data && r1.json.data.id
  ok("una sola peticion crea el recaudo con sus evidencias", r1.status === 200 && recId && r1.json.data.evidencias === 2, `id=${recId} evidencias=${r1.json && r1.json.data && r1.json.data.evidencias}`)

  const nDocs = recId ? (await uno("SELECT COUNT(*) n FROM dbo.recaudos_documentos WHERE recaudo_id=@v", [["v", sql.Int, recId]])).n : 0
  const evs = recId ? (await pedidos.request().input("v", sql.Int, recId)
    .query("SELECT mime, tamano, ancho, alto, recaudo_id, numero_recaudo FROM dbo.evidencias_archivos WHERE recaudo_id=@v ORDER BY id")).recordset : []
  ok("misma transaccion: 2 documentos y 2 imagenes ligadas por recaudo_id", nDocs === 2 && evs.length === 2 && evs.every((e) => e.recaudo_id === recId && e.numero_recaudo === NUM_OK && e.mime === "image/webp" && e.tamano > 0), `docs=${nDocs} imgs=${evs.length} ${evs.map((e) => e.ancho + "x" + e.alto).join(",")}`)

  const NUM_MAL = `REC-ATOM-MAL-${ts}`
  const docsMal = [{ docEntry: 301, docNum: "FV-3001", numFactura: "FE3001", saldo: 100000, abono: 100000, dueDate: "X".repeat(50) }]
  const camposMal = {
    ...campos, numeroRecaudo: NUM_MAL, documentos: JSON.stringify(docsMal),
    totalDocumentos: 100000, totalAplicado: 100000, totalRecaudo: 100000, saldo: 0,
  }
  const archivosMal = [
    { campo: "fotos", nombre: "m1.png", mime: "image/png", contenido: await foto(800, { r: 90, g: 90, b: 200 }) },
    { campo: "fotos", nombre: "m2.png", mime: "image/png", contenido: await foto(850, { r: 200, g: 200, b: 40 }) },
  ]
  const r2 = await llamar("POST", "/api/recaudos", { token, mp: multipart(camposMal, archivosMal) })
  const recMal = await cuenta("dbo.recaudos", "numero_recaudo", NUM_MAL)
  const eviMal = await cuenta("dbo.evidencias_archivos", "numero_recaudo", NUM_MAL)
  ok("fallo a mitad: no queda recaudo NI imagenes (rollback total)", r2.status !== 200 && recMal === 0 && eviMal === 0, `status=${r2.status} recaudos=${recMal} imagenes=${eviMal}`)

  const NUM_JSON = `REC-ATOM-JSON-${ts}`
  const r3 = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: NUM_JSON, clienteId: CLIENTE, clienteNombre: "SIN FOTOS", formaPago: "Efectivo", totalDocumentos: 700000, totalAplicado: 600000, totalRecaudo: 600000, saldo: 0, documentos: docsOk } })
  const recJson = r3.json && r3.json.data && r3.json.data.id
  ok("compatibilidad: el envio JSON sin fotos sigue funcionando", r3.status === 200 && recJson && r3.json.data.evidencias === 0, `id=${recJson} evidencias=${r3.json && r3.json.data && r3.json.data.evidencias}`)

  try {
    for (const id of [recId, recJson]) if (id) await pedidos.request().input("id", sql.Int, id).query("DELETE FROM dbo.recaudos WHERE id=@id")
    await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("DELETE FROM dbo.evidencias_archivos WHERE cliente_id=@c")
    await sesiones.cerrar(pedidos, sql, jti, "prueba")
  } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") }
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "RECAUDO ATOMICO OK\n" : "FALLO DE ATOMICIDAD DEL RECAUDO\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
