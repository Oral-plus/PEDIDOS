const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const CLIENTE = "PRUEBA-INSERT"
const NUM_RECAUDO = `REC-INS-${Date.now()}`

function llamar(metodo, ruta, { body, token, headers = {}, raw = false } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? (Buffer.isBuffer(body) ? body : JSON.stringify(body)) : null
    const h = { ...headers }
    if (datos && !Buffer.isBuffer(body)) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = datos.length
    if (token) h.Authorization = `Bearer ${token}`
    const req = (BASE.startsWith("https") ? require("https") : http).request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const trozos = []
      res.on("data", (c) => trozos.push(c))
      res.on("end", () => {
        const buf = Buffer.concat(trozos)
        if (raw) return resolve({ status: res.statusCode, headers: res.headers, buf })
        let json = null
        try { json = JSON.parse(buf.toString("utf8")) } catch (_) {}
        resolve({ status: res.statusCode, headers: res.headers, json })
      })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}

function multipart(campos, archivo) {
  const limite = "----ins" + Date.now()
  const partes = []
  for (const [k, v] of Object.entries(campos)) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  }
  partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${archivo.campo}"; filename="${archivo.nombre}"\r\nContent-Type: ${archivo.mime}\r\n\r\n`))
  partes.push(archivo.contenido)
  partes.push(Buffer.from(`\r\n--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

async function esperar() {
  for (let i = 0; i < 60; i++) {
    try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {}
    await new Promise((r) => setTimeout(r, 1000))
  }
  return false
}

const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, tabla, base, c, extra) => out.push([n, tabla, base, !!c, extra || ""])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const ruta = await new sql.ConnectionPool(cfgDb(process.env.RUTA_DB_NAME || "Ruta")).connect()

  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA INSERCION", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA INSERCION", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const png = await sharp({ create: { width: 800, height: 600, channels: 3, background: { r: 20, g: 120, b: 90 } } }).png().toBuffer()

  const limpieza = []

  const rPed = await llamar("POST", "/api/orders", { token, body: { cedula: CLIENTE, nombre: "PRUEBA", correo: "p@oral-plus.com", codigoCliente: CLIENTE, vendedor: "PRUEBA", productos: [{ codigo: "PRB1", nombre: "Prod prueba", cantidad: 2, precio: 1500 }] } })
  const docNum = rPed.json && rPed.json.docNum
  const fPed = docNum ? (await pedidos.request().input("n", sql.NVarChar, docNum).query("SELECT id FROM pedidos WHERE numero_pedido=@n")).recordset[0] : null
  const pedidoId = fPed && fPed.id
  const nDet = pedidoId ? (await pedidos.request().input("id", sql.Int, pedidoId).query("SELECT COUNT(*) n FROM pedidos_detalle WHERE pedido_id=@id")).recordset[0].n : 0
  const nHist = pedidoId ? (await pedidos.request().input("id", sql.Int, pedidoId).query("SELECT COUNT(*) n FROM pedidos_historial WHERE pedido_id=@id")).recordset[0].n : 0
  ok("Pedido (checkout)", "pedidos + pedidos_detalle + pedidos_historial", "Pedidos", rPed.status === 200 && pedidoId && nDet >= 1 && nHist >= 1, `${docNum} det=${nDet} hist=${nHist}`)
  if (pedidoId) limpieza.push(async () => {
    await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos_historial WHERE pedido_id=@id")
    await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos_detalle WHERE pedido_id=@id")
    await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos WHERE id=@id")
  })

  const rRec = await llamar("POST", "/api/recaudos", { token, body: { numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE, clienteNombre: "PRUEBA", formaPago: "Efectivo", totalAplicado: 5000, totalRecaudo: 5000, documentos: [{ docEntry: 1, docNum: "F1", numFactura: "F1", saldo: 5000, abono: 5000, dueDate: "2026-09-30" }] } })
  const recId = rRec.json && rRec.json.data && rRec.json.data.id
  const nRecDoc = recId ? (await pedidos.request().input("id", sql.Int, recId).query("SELECT COUNT(*) n FROM dbo.recaudos_documentos WHERE recaudo_id=@id")).recordset[0].n : 0
  ok("Recaudo (cartera)", "recaudos + recaudos_documentos", "Pedidos", rRec.status === 200 && recId && nRecDoc >= 1, `id=${recId} docs=${nRecDoc}`)
  if (recId) limpieza.push(async () => {
    await pedidos.request().input("id", sql.Int, recId).query("DELETE FROM dbo.recaudos_documentos WHERE recaudo_id=@id")
    await pedidos.request().input("id", sql.Int, recId).query("DELETE FROM dbo.recaudos WHERE id=@id")
  })

  const rGes = await llamar("POST", "/api/pedidos/gestion", { token, body: { clienteId: CLIENTE, clienteNombre: "PRUEBA", total: 1000, formaPago: "Efectivo", numeroRecaudo: NUM_RECAUDO, evidencias: 1, estado: "GUARDADO" } })
  const gesId = rGes.json && rGes.json.data && rGes.json.data.id
  const fGes = gesId ? (await pedidos.request().input("id", sql.Int, gesId).query("SELECT forma_pago, numero_recaudo FROM dbo.pedidos_gestion WHERE id=@id")).recordset[0] : null
  ok("Gestión de pedido", "pedidos_gestion", "Pedidos", rGes.status === 200 && fGes && fGes.forma_pago === "Efectivo" && fGes.numero_recaudo === NUM_RECAUDO, fGes && `${fGes.forma_pago}/${fGes.numero_recaudo}`)
  if (gesId) limpieza.push(async () => { await pedidos.request().input("id", sql.Int, gesId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM dbo.pedidos_gestion WHERE id=@id AND cliente_id=@c") })

  const rVis = await llamar("POST", `/api/clientes/${CLIENTE}/visita`, { token, body: { observacion: "prueba insercion", metodoPago: "Transferencia", bancoPago: "Bancolombia", referenciaPago: "REF-9", numeroRecaudo: NUM_RECAUDO, totalRecaudos: 5000, encuestaTipo: "Encuesta prueba", encuestaRespuestas: { tipo: "T1", nombre: "Encuesta prueba", respuestas: { p1: "si", p2: "no", p3: "tal vez" } } } })
  const visId = rVis.json && rVis.json.data && rVis.json.data.id
  const fVis = visId ? (await ruta.request().input("id", sql.Int, visId).query("SELECT metodo_pago, numero_recaudo FROM visitas_clientes WHERE id=@id")).recordset[0] : null
  const fEnc = visId ? (await pedidos.request().input("id", sql.Int, visId).query("SELECT id FROM dbo.encuestas_visitas WHERE visita_id=@id")).recordset[0] : null
  const encId = fEnc && fEnc.id
  const nResp = encId ? (await pedidos.request().input("id", sql.Int, encId).query("SELECT COUNT(*) n FROM dbo.encuestas_respuestas WHERE encuesta_id=@id")).recordset[0].n : 0
  ok("Visita", "visitas_clientes", "Ruta", rVis.status === 200 && fVis && fVis.metodo_pago === "Transferencia" && fVis.numero_recaudo === NUM_RECAUDO, fVis && `${fVis.metodo_pago}/${fVis.numero_recaudo}`)
  ok("Encuesta de visita", "encuestas_visitas + encuestas_respuestas", "Pedidos", encId && nResp === 3, `enc=${encId} respuestas=${nResp}`)
  if (visId) limpieza.push(async () => {
    if (encId) {
      await pedidos.request().input("id", sql.Int, encId).query("DELETE FROM dbo.encuestas_respuestas WHERE encuesta_id=@id")
      await pedidos.request().input("id", sql.Int, encId).query("DELETE FROM dbo.encuestas_visitas WHERE id=@id")
    }
    await ruta.request().input("id", sql.Int, visId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM visitas_clientes WHERE id=@id AND cliente_id=@c")
  })

  const rCom = await llamar("POST", `/api/clientes/${CLIENTE}/comentarios`, { token, body: { comentario: `comentario prueba ${Date.now()}` } })
  const comId = rCom.json && rCom.json.data && rCom.json.data.id
  ok("Comentario de cliente", "comentarios_clientes", "Pedidos", rCom.status === 200 && comId, `id=${comId}`)
  if (comId) limpieza.push(async () => { await pedidos.request().input("id", sql.Int, comId).query("DELETE FROM dbo.comentarios_clientes WHERE id=@id") })

  const rRut = await llamar("POST", "/api/rutas/extra", { token, body: { clienteId: CLIENTE, clienteNombre: "PRUEBA", ciudad: "Medellin", motivo: "Motivo de prueba", observacion: "Observacion de prueba" } })
  const rutId = rRut.json && rRut.json.data && rRut.json.data.id
  ok("Ruta extra", "rutas (es_extra=1)", "Ruta", rRut.status === 200 && rutId, `id=${rutId}`)
  if (rutId) limpieza.push(async () => { await ruta.request().input("id", sql.Int, rutId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM dbo.rutas WHERE id=@id AND cliente_id=@c") })

  const rEvi = await llamar("POST", "/api/evidencias", { token, ...multipart({ origen: "recaudo", numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE }, { campo: "foto", nombre: "e.png", mime: "image/png", contenido: png }) })
  const eviId = rEvi.json && rEvi.json.data && rEvi.json.data.id
  const fEvi = eviId ? (await pedidos.request().input("id", sql.Int, eviId).query("SELECT mime, DATALENGTH(contenido) b FROM dbo.evidencias_archivos WHERE id=@id")).recordset[0] : null
  ok("Evidencia (foto de pago)", "evidencias_archivos", "Pedidos", rEvi.status === 200 && fEvi && fEvi.mime === "image/webp" && fEvi.b > 0, fEvi && `${fEvi.mime} ${fEvi.b}b`)
  if (eviId) limpieza.push(async () => { await pedidos.request().input("id", sql.Int, eviId).query("DELETE FROM dbo.evidencias_archivos WHERE id=@id") })

  for (const fn of limpieza) { try { await fn() } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") } }
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()
  await ruta.close()

  const pad = (s, n) => (s + " ".repeat(n)).slice(0, n)
  process.stdout.write("\nESTRUCTURA DE INSERCIONES (endpoint -> tabla -> BD)\n")
  process.stdout.write(pad("DATO", 26) + pad("TABLA", 48) + pad("BD", 9) + "RESULTADO\n")
  for (const [n, tabla, base, b, extra] of out) {
    process.stdout.write(pad(n, 26) + pad(tabla, 48) + pad(base, 9) + (b ? "OK" : "FALLA") + (extra ? "  [" + extra + "]" : "") + "\n")
  }
  const todo = out.every((x) => x[3])
  process.stdout.write("\n" + (todo ? "TODAS LAS INSERCIONES OK\n" : "HAY INSERCIONES CON FALLO\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
