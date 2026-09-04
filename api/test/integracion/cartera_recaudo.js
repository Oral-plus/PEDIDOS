const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CANDIDATOS = ["C1000100148", "C890929329-2", "C890921693-2", "C39422290-2", "C901908774"]

function multipart(campos, archivos) {
  const limite = "----cr" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [k, v] of Object.entries(campos)) partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="fotos"; filename="${a.nombre}"\r\nContent-Type: image/png\r\n\r\n`))
    partes.push(a.contenido); partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

function llamar(metodo, ruta, { token, mp } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : null
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
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

async function esperar() { for (let i = 0; i < 60; i++) { try { const r = await llamar("GET", "/api/test", {}); if (r.status === 200) return true } catch (_) {} await new Promise((r) => setTimeout(r, 1000)) } return false }
const cfg = (d) => ({ server: process.env.DB_SERVER, database: d, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA CARTERA", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA CARTERA", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const n = (v) => Number(v)

  let cliente = null, docsCartera = [], saldoCartera = 0
  for (const c of CANDIDATOS) {
    const r = await llamar("GET", `/api/clientes/${c}/documentos`, { token })
    const d = (r.json && r.json.data) || []
    if (r.status === 200 && d.length > 0) { cliente = c; docsCartera = d; saldoCartera = n(r.json.totalSaldo); break }
  }
  ok("cartera real: se obtienen facturas abiertas de SAP", !!cliente && docsCartera.length > 0, cliente ? `${cliente}: ${docsCartera.length} factura(s), saldo ${saldoCartera}` : "ningun cliente con cartera")
  if (!cliente) { process.stdout.write("Sin cartera con que probar\n"); process.exit(1) }

  const usados = docsCartera.slice(0, 2)
  const camposClave = usados.every((d) => d.docEntry != null && d.docNum != null && n(d.saldo) > 0 && d.dueDate)
  ok("las facturas traen docEntry, docNum, saldo y vencimiento", camposClave, usados.map((d) => `${d.docNum}:${n(d.saldo)}`).join(" "))

  const documentos = usados.map((d) => ({
    docEntry: d.docEntry,
    docNum: `${d.docNum}`,
    numFactura: `${d.numFactura || ""}`,
    saldo: n(d.saldo),
    abono: Math.round(n(d.saldo) / 2),
    dueDate: `${d.dueDate}`,
  }))
  const totalAplicado = documentos.reduce((s, d) => s + d.abono, 0)
  const totalDocumentos = documentos.reduce((s, d) => s + d.saldo, 0)
  const NUM = `REC-CART-${ts}`
  const img = await sharp({ create: { width: 800, height: 600, channels: 3, background: { r: 30, g: 110, b: 70 } } }).png().toBuffer()
  const campos = {
    numeroRecaudo: NUM, clienteId: cliente, clienteNombre: "CLIENTE CARTERA REAL",
    formaPago: "Transferencia", bancoPago: "Bancolombia", referenciaPago: `TRF-CART-${ts}`,
    totalDocumentos: `${totalDocumentos}`, totalAplicado: `${totalAplicado}`,
    totalRecaudo: `${totalAplicado}`, saldo: "0",
    notas: "recaudo contra cartera real", documentos: JSON.stringify(documentos),
  }
  const r = await llamar("POST", "/api/recaudos", { token, mp: multipart(campos, [{ nombre: "soporte.png", contenido: img }]) })
  const recId = r.json && r.json.data && r.json.data.id
  ok("se registra el recaudo sobre la cartera real, con su soporte", r.status === 200 && recId && r.json.data.evidencias === 1, `id=${recId} aplicado=${totalAplicado}`)

  const filas = recId ? (await pedidos.request().input("i", sql.Int, recId)
    .query("SELECT doc_entry, doc_num, num_factura, saldo, abono, due_date FROM dbo.recaudos_documentos WHERE recaudo_id=@i ORDER BY doc_entry")).recordset : []
  const esperados = [...documentos].sort((a, b) => a.docEntry - b.docEntry)
  const coincide = filas.length === documentos.length && filas.every((f, i) => {
    const e = esperados[i]
    return f.doc_entry === e.docEntry && f.doc_num === e.docNum && f.num_factura === e.numFactura &&
      n(f.saldo) === e.saldo && n(f.abono) === e.abono && f.due_date === e.dueDate
  })
  ok("cada documento guardado es identico a la factura de cartera", coincide, filas.map((f) => `${f.doc_num}:${n(f.abono)}`).join(" "))

  const cab = recId ? (await pedidos.request().input("i", sql.Int, recId)
    .query("SELECT cliente_id, forma_pago, total_documentos, total_aplicado, total_recaudo FROM dbo.recaudos WHERE id=@i")).recordset[0] : null
  ok("la cabecera guarda el cliente y los importes de la cartera", cab && cab.cliente_id === cliente && n(cab.total_documentos) === totalDocumentos && n(cab.total_aplicado) === totalAplicado && n(cab.total_recaudo) === totalAplicado, cab && `docs=${n(cab.total_documentos)} aplicado=${n(cab.total_aplicado)}`)

  const ev = recId ? (await pedidos.request().input("i", sql.Int, recId).query("SELECT id, recaudo_id, tamano FROM dbo.evidencias_archivos WHERE recaudo_id=@i")).recordset : []
  ok("el soporte quedo ligado al recaudo", ev.length === 1 && ev[0].recaudo_id === recId && ev[0].tamano > 0, ev[0] && `${ev[0].tamano}b`)

  const rCar = await llamar("GET", `/api/clientes/${cliente}/documentos`, { token })
  const saldoDespues = n(rCar.json && rCar.json.totalSaldo)
  ok("la cartera de SAP queda intacta (el recaudo no la modifica)", saldoDespues === saldoCartera, `antes ${saldoCartera} · despues ${saldoDespues}`)

  if (recId) await pedidos.request().input("i", sql.Int, recId).query("DELETE FROM dbo.recaudos WHERE id=@i")
  const quedan = recId ? (await pedidos.request().input("i", sql.Int, recId)
    .query("SELECT (SELECT COUNT(*) FROM dbo.recaudos WHERE id=@i) r, (SELECT COUNT(*) FROM dbo.recaudos_documentos WHERE recaudo_id=@i) d, (SELECT COUNT(*) FROM dbo.evidencias_archivos WHERE recaudo_id=@i) e")).recordset[0] : null
  ok("al borrar el recaudo no queda nada suelto", quedan && quedan.r === 0 && quedan.d === 0 && quedan.e === 0, quedan && `rec=${quedan.r} doc=${quedan.d} img=${quedan.e}`)

  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "RECAUDO SOBRE CARTERA REAL OK\n" : "HAY FALLOS EN EL RECAUDO SOBRE CARTERA\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
