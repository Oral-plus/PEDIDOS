const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CLIENTE = `RECVAL${ts % 1000000}`

function multipart(campos, archivos) {
  const limite = "----rv" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [k, v] of Object.entries(campos)) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  }
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="fotos"; filename="${a.nombre}"\r\nContent-Type: image/png\r\n\r\n`))
    partes.push(a.contenido); partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

function llamar(metodo, ruta, { token, mp, raw } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : null
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
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

async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test", {}); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = (d) => ({ server: process.env.DB_SERVER, database: d, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA RECVAL", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA RECVAL", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const cuenta = async (t, col, v) => (await pedidos.request().input("v", sql.NVarChar, v).query(`SELECT COUNT(*) n FROM ${t} WHERE ${col}=@v`)).recordset[0].n
  const img = await sharp({ create: { width: 700, height: 500, channels: 3, background: { r: 40, g: 90, b: 160 } } }).png().toBuffer()
  const archivos = [{ nombre: "evidencia.png", contenido: img }]

  const docOk = { docEntry: 11, docNum: "FV-11", numFactura: "FE11", saldo: 200000, abono: 200000, dueDate: "2026-09-30" }
  const base = {
    clienteId: CLIENTE, clienteNombre: "CLIENTE RECAUDO", formaPago: "Transferencia",
    bancoPago: "Bancolombia", referenciaPago: "TRF-RV-1",
    totalDocumentos: "200000.0", totalAplicado: "200000.0", totalRecaudo: "200000.0", saldo: "0.0",
    notas: "validacion de recaudo", documentos: JSON.stringify([docOk]),
  }

  const casos = [
    ["valor recaudado en cero", { totalRecaudo: "0.0" }],
    ["valor recaudado nulo", { totalRecaudo: "null" }],
    ["valor recaudado vacio", { totalRecaudo: "" }],
    ["sin forma de pago", { formaPago: "" }],
    ["total aplicado en cero", { totalAplicado: "0.0", documentos: JSON.stringify([{ ...docOk, abono: 0 }]) }],
    ["documento con abono en cero", { documentos: JSON.stringify([{ ...docOk, abono: 0 }]) }],
    ["aplicado que no cuadra con los abonos", { totalAplicado: "999999.0" }],
  ]
  for (const [nombre, cambio] of casos) {
    const numero = `RV-${nombre.replace(/[^a-z]/gi, "").slice(0, 12)}-${ts}`
    const campos = { ...base, ...cambio, numeroRecaudo: numero }
    const r = await llamar("POST", "/api/recaudos", { token, mp: multipart(campos, archivos) })
    const rec = await cuenta("dbo.recaudos", "numero_recaudo", numero)
    const evi = await cuenta("dbo.evidencias_archivos", "numero_recaudo", numero)
    ok(`guarda tal cual, con su imagen: ${nombre}`, r.status === 200 && rec === 1 && evi === 1, `${r.status} rec=${rec} img=${evi} · ${r.json && r.json.message}`)
    await pedidos.request().input("n", sql.NVarChar, numero).query("DELETE FROM dbo.recaudos WHERE numero_recaudo=@n")
  }

  const numSinDocs = `RV-sindocs-${ts}`
  const rSin = await llamar("POST", "/api/recaudos", { token, mp: multipart({ ...base, numeroRecaudo: numSinDocs, documentos: "[]" }, archivos) })
  const recSin = await cuenta("dbo.recaudos", "numero_recaudo", numSinDocs)
  const eviSin = await cuenta("dbo.evidencias_archivos", "numero_recaudo", numSinDocs)
  ok("rechaza el recaudo sin documentos cruzados y no sube la imagen", rSin.status === 400 && recSin === 0 && eviSin === 0, `${rSin.status} rec=${recSin} img=${eviSin} · ${rSin.json && rSin.json.message}`)

  const NUM_OK = `RV-OK-${ts}`
  const camposOk = {
    ...base, numeroRecaudo: NUM_OK,
    totalDocumentos: "500000.0", totalAplicado: "350000.0", totalRecaudo: "400000.0", saldo: "50000.0",
    documentos: JSON.stringify([
      { docEntry: 21, docNum: "FV-21", numFactura: "FE21", saldo: 300000, abono: 200000, dueDate: "2026-09-30" },
      { docEntry: 22, docNum: "FV-22", numFactura: "FE22", saldo: 200000, abono: 150000, dueDate: "2026-10-10" },
    ]),
  }
  const rOk = await llamar("POST", "/api/recaudos", { token, mp: multipart(camposOk, archivos) })
  const recId = rOk.json && rOk.json.data && rOk.json.data.id
  ok("acepta el recaudo valido enviado como lo manda el APK", rOk.status === 200 && recId && rOk.json.data.evidencias === 1, `id=${recId} evidencias=${rOk.json && rOk.json.data && rOk.json.data.evidencias}`)

  const c = recId ? (await pedidos.request().input("i", sql.Int, recId).query(`
    SELECT numero_recaudo, cliente_id, cliente_nombre, vendedor_id, vendedor_nombre, forma_pago, banco_pago,
           referencia_pago, total_documentos, total_aplicado, total_recaudo, saldo, notas
    FROM dbo.recaudos WHERE id=@i`)).recordset[0] : null
  const n = (v) => Number(v)
  const camposMal = c ? Object.entries({
    numero_recaudo: c.numero_recaudo === NUM_OK,
    cliente_id: c.cliente_id === CLIENTE,
    cliente_nombre: c.cliente_nombre === "CLIENTE RECAUDO",
    vendedor_id: c.vendedor_id === 0,
    vendedor_nombre: c.vendedor_nombre === "PRUEBA RECVAL",
    forma_pago: c.forma_pago === "Transferencia",
    banco_pago: c.banco_pago === "Bancolombia",
    referencia_pago: c.referencia_pago === "TRF-RV-1",
    total_documentos: n(c.total_documentos) === 500000,
    total_aplicado: n(c.total_aplicado) === 350000,
    total_recaudo: n(c.total_recaudo) === 400000,
    saldo: n(c.saldo) === 50000,
    notas: c.notas === "validacion de recaudo",
  }).filter(([, v]) => !v).map(([k]) => k) : ["sin fila"]
  ok("los importes y datos guardados son exactamente los enviados", camposMal.length === 0, camposMal.length ? "fallan: " + camposMal.join(",") : `recaudo=${c && n(c.total_recaudo)} aplicado=${c && n(c.total_aplicado)} saldo=${c && n(c.saldo)}`)

  const ninguno = c ? Object.entries({
    forma_pago: c.forma_pago, total_documentos: n(c.total_documentos), total_aplicado: n(c.total_aplicado), total_recaudo: n(c.total_recaudo),
  }).filter(([, v]) => v === null || v === "" || v === 0).map(([k]) => k) : ["sin fila"]
  ok("ningun dato clave quedo nulo ni en cero", ninguno.length === 0, ninguno.length ? "en cero/nulo: " + ninguno.join(",") : "todos con valor")

  const docs = recId ? (await pedidos.request().input("i", sql.Int, recId).query("SELECT doc_num, abono FROM dbo.recaudos_documentos WHERE recaudo_id=@i ORDER BY doc_entry")).recordset : []
  const sumaOk = docs.length === 2 && docs.reduce((s, d) => s + n(d.abono), 0) === 350000
  ok("los documentos entraron con sus abonos y suman el total aplicado", sumaOk, `${docs.length} docs, suma=${docs.reduce((s, d) => s + n(d.abono), 0)}`)

  const ev = recId ? (await pedidos.request().input("i", sql.Int, recId).query("SELECT id, recaudo_id, mime, tamano FROM dbo.evidencias_archivos WHERE recaudo_id=@i")).recordset : []
  ok("la imagen quedo ligada al recaudo por recaudo_id", ev.length === 1 && ev[0].recaudo_id === recId && ev[0].mime === "image/webp" && ev[0].tamano > 0, ev[0] && `id=${ev[0].id} ${ev[0].tamano}b`)

  const foto = ev[0] ? await llamar("GET", `/api/evidencias/${ev[0].id}/foto`, { token, raw: true }) : { status: 0 }
  ok("la imagen se recupera integra", foto.status === 200 && foto.buf && foto.buf.length === (ev[0] && ev[0].tamano), `${foto.status} ${foto.buf && foto.buf.length}b`)

  try {
    if (recId) await pedidos.request().input("i", sql.Int, recId).query("DELETE FROM dbo.recaudos WHERE id=@i")
    await pedidos.request().input("c", sql.NVarChar, CLIENTE).query("DELETE FROM dbo.evidencias_archivos WHERE cliente_id=@c")
    await sesiones.cerrar(pedidos, sql, jti, "prueba")
  } catch (e) { process.stdout.write("aviso limpieza: " + e.message + "\n") }
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "VALIDACION DE RECAUDO OK\n" : "HAY FALLOS EN LA VALIDACION DEL RECAUDO\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
