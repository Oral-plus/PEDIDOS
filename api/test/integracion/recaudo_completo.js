// Prueba REST de un RECAUDO COMPLETO: cabecera con todos sus campos documentados,
// sus documentos aplicados, sus imagenes de evidencia; verificacion campo por campo
// en la BD; y borrado con verificacion de la cascada (no debe quedar nada).
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const CLIENTE = `RECFULL${ts % 1000000}`
const NUM_RECAUDO = `REC-FULL-${ts}`

function llamar(metodo, ruta, { body, token, mp, raw } = {}) {
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

function multipart(campos, archivo) {
  const limite = "----full" + Math.random().toString(16).slice(2)
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
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: "0", usuarioNombre: "PRUEBA RECAUDO", tipo: "usuario", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: 0, nombre: "PRUEBA RECAUDO", tipo: "usuario", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const uno = async (q, i) => { const r = pedidos.request(); for (const [k, t, v] of i) r.input(k, t, v); return (await r.query(q)).recordset[0] }

  // ── 1) Recaudo con TODOS los campos documentados + 3 documentos aplicados ──
  const documentos = [
    { docEntry: 101, docNum: "FV-1001", numFactura: "FE1001", saldo: 500000, abono: 300000, dueDate: "2026-09-15" },
    { docEntry: 102, docNum: "FV-1002", numFactura: "FE1002", saldo: 250000, abono: 250000, dueDate: "2026-09-20" },
    { docEntry: 103, docNum: "FV-1003", numFactura: "FE1003", saldo: 150000, abono: 100000, dueDate: "2026-10-01" },
  ]
  const cuerpo = {
    numeroRecaudo: NUM_RECAUDO,
    clienteId: CLIENTE,
    clienteNombre: "CLIENTE PRUEBA RECAUDO COMPLETO",
    formaPago: "Transferencia",
    bancoPago: "Bancolombia",
    referenciaPago: "TRF-998877",
    totalDocumentos: 900000,
    totalAplicado: 650000,
    totalRecaudo: 650000,
    saldo: 250000,
    notas: "Recaudo de prueba con todos los campos y evidencias",
    documentos,
  }
  const rRec = await llamar("POST", "/api/recaudos", { token, body: cuerpo })
  const recId = rRec.json && rRec.json.data && rRec.json.data.id
  ok("REST: recaudo creado (POST /api/recaudos)", rRec.status === 200 && rRec.json.success === true && recId, `id=${recId} num=${rRec.json && rRec.json.data && rRec.json.data.numeroRecaudo}`)

  // ── 2) Cabecera: verificar CADA campo documentado ──
  const c = recId ? await uno(`SELECT numero_recaudo, cliente_id, cliente_nombre, vendedor_id, vendedor_nombre,
      forma_pago, banco_pago, referencia_pago, total_documentos, total_aplicado, total_recaudo, saldo, notas,
      CONVERT(VARCHAR(19), fecha, 120) fecha FROM dbo.recaudos WHERE id=@id`, [["id", sql.Int, recId]]) : null
  const num = (v) => Number(v)
  const campos = c ? {
    numero_recaudo: c.numero_recaudo === NUM_RECAUDO,
    cliente_id: c.cliente_id === CLIENTE,
    cliente_nombre: c.cliente_nombre === cuerpo.clienteNombre,
    vendedor_id: c.vendedor_id === 0,
    vendedor_nombre: c.vendedor_nombre === "PRUEBA RECAUDO",
    forma_pago: c.forma_pago === "Transferencia",
    banco_pago: c.banco_pago === "Bancolombia",
    referencia_pago: c.referencia_pago === "TRF-998877",
    total_documentos: num(c.total_documentos) === 900000,
    total_aplicado: num(c.total_aplicado) === 650000,
    total_recaudo: num(c.total_recaudo) === 650000,
    saldo: num(c.saldo) === 250000,
    notas: c.notas === cuerpo.notas,
    fecha: !!c.fecha,
  } : {}
  const malos = Object.entries(campos).filter(([, v]) => !v).map(([k]) => k)
  ok(`cabecera: los ${Object.keys(campos).length} campos documentados guardados`, c && malos.length === 0, malos.length ? "fallan: " + malos.join(",") : "todos correctos")

  // ── 3) Documentos aplicados: cantidad y cada campo ──
  const docs = recId ? (await pedidos.request().input("id", sql.Int, recId)
    .query("SELECT doc_entry, doc_num, num_factura, saldo, abono, due_date FROM dbo.recaudos_documentos WHERE recaudo_id=@id ORDER BY doc_entry")).recordset : []
  const docsOk = docs.length === 3 && docs.every((d, i) => {
    const e = documentos[i]
    return d.doc_entry === e.docEntry && d.doc_num === e.docNum && d.num_factura === e.numFactura &&
      num(d.saldo) === e.saldo && num(d.abono) === e.abono && d.due_date === e.dueDate
  })
  ok("documentos: 3 filas con docEntry, docNum, factura, saldo, abono y vencimiento", docsOk, `${docs.length} docs, abonos=${docs.map((d) => num(d.abono)).join("+")}`)

  const sumaAbonos = docs.reduce((s, d) => s + num(d.abono), 0)
  ok("documentos: la suma de abonos coincide con total_aplicado", sumaAbonos === 650000, `${sumaAbonos} vs 650000`)

  // ── 4) Evidencias: 2 imagenes subidas por REST y ligadas al recaudo ──
  const imgs = []
  for (const [i, color] of [[1, { r: 200, g: 30, b: 30 }], [2, { r: 30, g: 140, b: 60 }]]) {
    const png = await sharp({ create: { width: 800 + i * 100, height: 600, channels: 3, background: color } }).png().toBuffer()
    const r = await llamar("POST", "/api/evidencias", { token, mp: multipart({ origen: "recaudo", numeroRecaudo: NUM_RECAUDO, clienteId: CLIENTE }, { campo: "foto", nombre: `evidencia${i}.png`, mime: "image/png", contenido: png }) })
    imgs.push({ status: r.status, id: r.json && r.json.data && r.json.data.id })
  }
  ok("REST: 2 evidencias subidas (POST /api/evidencias)", imgs.every((x) => x.status === 200 && x.id), imgs.map((x) => "id=" + x.id).join(" "))

  const evid = recId ? (await pedidos.request().input("id", sql.Int, recId)
    .query("SELECT id, origen, numero_recaudo, recaudo_id, cliente_id, vendedor_nombre, mime, tamano, ancho, alto FROM dbo.evidencias_archivos WHERE recaudo_id=@id ORDER BY id")).recordset : []
  const evidOk = evid.length === 2 && evid.every((e) => e.recaudo_id === recId && e.numero_recaudo === NUM_RECAUDO &&
    e.origen === "recaudo" && e.cliente_id === CLIENTE && e.mime === "image/webp" && e.tamano > 0 && e.ancho > 0 && e.alto > 0)
  ok("evidencias: 2 filas ligadas por recaudo_id, en webp y con dimensiones", evidOk, evid.map((e) => `${e.ancho}x${e.alto} ${e.tamano}b`).join(" | "))

  // ── 5) Las imagenes se recuperan integras por REST ──
  let descOk = true, det = []
  for (const e of evid) {
    const f = await llamar("GET", `/api/evidencias/${e.id}/foto`, { token, raw: true })
    const bien = f.status === 200 && /image\/webp/.test(f.headers["content-type"] || "") && f.buf.length === e.tamano
    if (!bien) descOk = false
    det.push(`${e.id}:${f.status}/${f.buf ? f.buf.length : 0}b`)
  }
  ok("evidencias: se descargan integras por REST (bytes coinciden con la BD)", evid.length === 2 && descOk, det.join(" "))

  // ── 6) El listado por REST devuelve las evidencias del recaudo ──
  const lista = await llamar("GET", `/api/evidencias?numeroRecaudo=${encodeURIComponent(NUM_RECAUDO)}`, { token })
  ok("REST: listado por numeroRecaudo devuelve las 2 evidencias", lista.status === 200 && lista.json.total === 2, `total=${lista.json && lista.json.total}`)

  // ── 7) BORRADO: al borrar el recaudo, la cascada limpia documentos y evidencias ──
  await pedidos.request().input("id", sql.Int, recId).query("DELETE FROM dbo.recaudos WHERE id=@id")
  const qN = async (t, col) => (await uno(`SELECT COUNT(*) n FROM ${t} WHERE ${col}=@id`, [["id", sql.Int, recId]])).n
  const nRec = await qN("dbo.recaudos", "id")
  const nDoc = await qN("dbo.recaudos_documentos", "recaudo_id")
  const nEvi = await qN("dbo.evidencias_archivos", "recaudo_id")
  ok("borrado: el recaudo y en cascada sus documentos y evidencias quedan en cero", nRec === 0 && nDoc === 0 && nEvi === 0, `rec=${nRec} doc=${nDoc} evi=${nEvi}`)

  // barrido por si quedara algo por numero
  await pedidos.request().input("n", sql.NVarChar, NUM_RECAUDO).query("DELETE FROM dbo.evidencias_archivos WHERE numero_recaudo=@n")
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "RECAUDO COMPLETO OK\n" : "HAY FALLOS EN EL RECAUDO\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
