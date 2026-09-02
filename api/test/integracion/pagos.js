const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const CLIENTE = "PRUEBA-PAGOS"
const NUM_RECAUDO = `REC-PRUEBA-${Date.now()}`

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
  const limite = "----prueba" + Date.now()
  const partes = []
  for (const [k, v] of Object.entries(campos)) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  }
  if (archivo) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${archivo.campo}"; filename="${archivo.nombre}"\r\nContent-Type: ${archivo.mime}\r\n\r\n`))
    partes.push(archivo.contenido)
    partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

async function esperar() {
  for (let i = 0; i < 120; i++) {
    try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {}
    await new Promise((r) => setTimeout(r, 1000))
  }
  return false
}

const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const ruta = await new sql.ConnectionPool(cfgDb(process.env.RUTA_DB_NAME || "Ruta")).connect()

  const jti = await sesiones.registrar(pedidos, sql, {
    usuarioCodigo: "0", usuarioNombre: "PRUEBA PAGOS", tipo: "usuario", plataforma: "prueba", duracionSeg: 900,
  })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA PAGOS", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })

  const png = await sharp({ create: { width: 900, height: 600, channels: 3, background: { r: 30, g: 90, b: 180 } } }).png().toBuffer()

  const sinToken = await llamar("POST", "/api/evidencias", multipart({ origen: "recaudo" }, { campo: "foto", nombre: "e.png", mime: "image/png", contenido: png }))
  ok("evidencia sin token: 401", sinToken.status === 401, sinToken.status)

  const origenMal = await llamar("POST", "/api/evidencias", { token, ...multipart({ origen: "otra" }, { campo: "foto", nombre: "e.png", mime: "image/png", contenido: png }) })
  ok("evidencia origen inválido: 400", origenMal.status === 400, origenMal.json && origenMal.json.message)

  const sinArchivo = await llamar("POST", "/api/evidencias", { token, ...multipart({ origen: "recaudo" }, null) })
  ok("evidencia sin archivo: 400", sinArchivo.status === 400, sinArchivo.json && sinArchivo.json.message)

  const subir = await llamar("POST", "/api/evidencias", { token, ...multipart({ origen: "recaudo", numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE }, { campo: "foto", nombre: "e.png", mime: "image/png", contenido: png }) })
  const evidId = subir.json && subir.json.data && subir.json.data.id
  ok("evidencia subida: 200 con id y tamaño", subir.status === 200 && subir.json.success === true && evidId, subir.json && subir.json.data && `id=${evidId} ${subir.json.data.tamano}b`)

  const dbEvid = evidId ? await pedidos.request().input("id", sql.Int, evidId).query("SELECT origen, numero_recaudo, mime, DATALENGTH(contenido) AS bytes FROM dbo.evidencias_archivos WHERE id = @id") : { recordset: [] }
  const filaEvid = dbEvid.recordset[0]
  ok("evidencia en BD: fila con webp, origen y numero_recaudo", !!filaEvid && filaEvid.origen === "recaudo" && filaEvid.numero_recaudo === NUM_RECAUDO && filaEvid.mime === "image/webp" && filaEvid.bytes > 0, filaEvid && `${filaEvid.mime} ${filaEvid.bytes}b`)

  const listar = await llamar("GET", `/api/evidencias?numeroRecaudo=${encodeURIComponent(NUM_RECAUDO)}`, { token })
  ok("evidencia listada por numeroRecaudo", listar.status === 200 && Array.isArray(listar.json.data) && listar.json.data.some((e) => e.id === evidId), listar.json && `total=${listar.json.total}`)

  const foto = evidId ? await llamar("GET", `/api/evidencias/${evidId}/foto`, { token, raw: true }) : { status: 0 }
  ok("evidencia descargada: webp válido", foto.status === 200 && /image\/webp/.test(foto.headers["content-type"] || "") && foto.buf && foto.buf.length > 0, `${foto.status} ${foto.buf && foto.buf.length}b`)

  const gestion = await llamar("POST", "/api/pedidos/gestion", { token, body: { clienteId: CLIENTE, clienteNombre: "PRUEBA", total: 1000, formaPago: "Efectivo", numeroRecaudo: NUM_RECAUDO, estado: "GUARDADO" } })
  const gestionId = gestion.json && gestion.json.data && gestion.json.data.id
  const dbGestion = gestionId ? await pedidos.request().input("id", sql.Int, gestionId).query("SELECT forma_pago, numero_recaudo FROM dbo.pedidos_gestion WHERE id = @id") : { recordset: [] }
  ok("gestión: persiste forma_pago y numero_recaudo", gestion.status === 200 && dbGestion.recordset[0] && dbGestion.recordset[0].forma_pago === "Efectivo" && dbGestion.recordset[0].numero_recaudo === NUM_RECAUDO, dbGestion.recordset[0] && `${dbGestion.recordset[0].forma_pago}/${dbGestion.recordset[0].numero_recaudo}`)

  const visita = await llamar("POST", `/api/clientes/${CLIENTE}/visita`, { token, body: { observacion: "prueba pagos", metodoPago: "Transferencia", bancoPago: "Bancolombia", referenciaPago: "REF-1", numeroRecaudo: NUM_RECAUDO, totalRecaudos: 5000 } })
  const visitaId = visita.json && visita.json.data && visita.json.data.id
  const dbVisita = visitaId ? await ruta.request().input("id", sql.Int, visitaId).query("SELECT metodo_pago, banco_pago, referencia_pago, numero_recaudo FROM visitas_clientes WHERE id = @id") : { recordset: [] }
  const fv = dbVisita.recordset[0]
  ok("visita: persiste metodo_pago, banco, referencia y numero_recaudo", visita.status === 200 && fv && fv.metodo_pago === "Transferencia" && fv.banco_pago === "Bancolombia" && fv.referencia_pago === "REF-1" && fv.numero_recaudo === NUM_RECAUDO, fv && `${fv.metodo_pago}/${fv.numero_recaudo}`)

  const pedido = await llamar("POST", "/api/orders", { token, body: { cedula: CLIENTE, nombre: "PRUEBA PAGOS", correo: "prueba@oral-plus.com", codigoCliente: CLIENTE, vendedor: "PRUEBA", productos: [{ codigo: "PRB001", nombre: "Producto prueba", cantidad: 2, precio: 1500 }] } })
  const docNum = pedido.json && pedido.json.docNum
  const dbPedido = docNum ? await pedidos.request().input("n", sql.NVarChar, docNum).query("SELECT id, total FROM pedidos WHERE numero_pedido = @n") : { recordset: [] }
  const pedidoId = dbPedido.recordset[0] && dbPedido.recordset[0].id
  ok("pedido: se inserta con token y devuelve docNum", pedido.status === 200 && pedido.json.success === true && docNum && pedidoId, `docNum=${docNum} total=${dbPedido.recordset[0] && dbPedido.recordset[0].total}`)

  const pedidoSinToken = await llamar("POST", "/api/orders", { body: { cedula: CLIENTE, nombre: "x", correo: "x@x.com", productos: [{ codigo: "P", cantidad: 1, precio: 1 }] } })
  ok("pedido sin token: 401", pedidoSinToken.status === 401, pedidoSinToken.status)

  try {
    if (evidId) await pedidos.request().input("id", sql.Int, evidId).query("DELETE FROM dbo.evidencias_archivos WHERE id = @id")
    if (gestionId) await pedidos.request().input("id", sql.Int, gestionId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM dbo.pedidos_gestion WHERE id = @id AND cliente_id = @c")
    if (visitaId) await ruta.request().input("id", sql.Int, visitaId).input("c", sql.NVarChar, CLIENTE).query("DELETE FROM visitas_clientes WHERE id = @id AND cliente_id = @c")
    if (pedidoId) {
      await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos_historial WHERE pedido_id = @id")
      await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos_detalle WHERE pedido_id = @id")
      await pedidos.request().input("id", sql.Int, pedidoId).query("DELETE FROM pedidos WHERE id = @id")
    }
    await sesiones.cerrar(pedidos, sql, jti, "prueba")
  } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") }

  await pedidos.close()
  await ruta.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write(todo ? "TODAS OK\n" : "HAY FALLOS\n")
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
