const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99983
const OTRO_VEND = 99984
const CLIENTE = "CLI-CUADRE"
const CLIENTE_B = "CLI-CUADRE-B"
const PREFIJO = `SKV${VEND}`

function multipart(campos, archivos) {
  const limite = "----cua" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [k, v] of Object.entries(campos)) partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`))
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${a.campo}"; filename="${a.nombre}"\r\nContent-Type: image/png\r\n\r\n`))
    partes.push(a.contenido); partes.push(Buffer.from("\r\n"))
  }
  partes.push(Buffer.from(`--${limite}--\r\n`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

function llamar(metodo, ruta, { token, body, mp } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : body !== undefined ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
    else if (datos) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = Buffer.byteLength(datos)
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
  const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${VEND}`, usuarioNombre: "PRUEBA CUADRE", tipo: "vendedor", plataforma: "prueba", duracionSeg: 900 })
  const token = jwt.sign({ userId: VEND, nombre: "PRUEBA CUADRE", tipo: "vendedor", jti }, process.env.JWT_SECRET, { expiresIn: 900 })
  const jtiOtro = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${OTRO_VEND}`, usuarioNombre: "OTRO GESTOR", tipo: "vendedor", plataforma: "prueba", duracionSeg: 900 })
  const tokenOtro = jwt.sign({ userId: OTRO_VEND, nombre: "OTRO GESTOR", tipo: "vendedor", jti: jtiOtro }, process.env.JWT_SECRET, { expiresIn: 900 })
  const foto = await sharp({ create: { width: 900, height: 620, channels: 3, background: { r: 20, g: 120, b: 200 } } }).png().toBuffer()

  const limpiar = async () => {
    await pedidos.request().input("a", sql.Int, VEND).input("b", sql.Int, OTRO_VEND)
      .query("DELETE FROM dbo.recaudos WHERE vendedor_id IN (@a, @b)")
  }
  await limpiar()

  const crearRecaudo = async (sufijo, { formaPago = "Efectivo", cliente = CLIENTE, nombre = "CLIENTE DE PRUEBA", valor = 150000, vendedor = VEND, recibo = null } = {}) => {
    const r = await pedidos.request()
      .input("num", sql.NVarChar, `REC-CUA-${ts}-${sufijo}`)
      .input("cli", sql.NVarChar, cliente)
      .input("cliNom", sql.NVarChar, nombre)
      .input("v", sql.Int, vendedor)
      .input("vn", sql.NVarChar, "PRUEBA CUADRE")
      .input("fp", sql.NVarChar, formaPago)
      .input("val", sql.Decimal(18, 2), valor)
      .input("rc", sql.BigInt, recibo)
      .input("rp", sql.NVarChar, recibo == null ? null : PREFIJO)
      .query(`
        INSERT INTO dbo.recaudos
          (numero_recaudo, cliente_id, cliente_nombre, vendedor_id, vendedor_nombre, forma_pago,
           total_documentos, total_aplicado, total_recaudo, saldo, recibo_caja, recibo_prefijo)
        OUTPUT INSERTED.id
        VALUES (@num, @cli, @cliNom, @v, @vn, @fp, @val, @val, @val, 0, @rc, @rp)
      `)
    const id = r.recordset[0].id
    await pedidos.request().input("id", sql.Int, id).query(`
      INSERT INTO dbo.recaudos_documentos (recaudo_id, doc_entry, doc_num, num_factura, saldo, abono, due_date)
      VALUES (@id, 1, 'F-CUA', 'FE-CUA-${sufijo}', 150000, 150000, '2026-12-31')
    `)
    return id
  }

  const cuadrar = (campos, conFoto = true) => llamar("POST", "/api/cuadres", conFoto
    ? { token, mp: multipart(campos, [{ campo: "foto", nombre: "consignacion.png", contenido: foto }]) }
    : { token, mp: multipart(campos, []) })
  const listar = (estado) => llamar("GET", `/api/cuadres/recaudos?estado=${estado}`, { token })

  const efectivoA = await crearRecaudo("a", { recibo: 41 })
  const efectivoB = await crearRecaudo("b", { cliente: CLIENTE_B, nombre: "SEGUNDO CLIENTE", valor: 90000, recibo: 42 })
  const transferencia = await crearRecaudo("t", { formaPago: "Transferencia", recibo: 43 })
  const ajeno = await crearRecaudo("x", { vendedor: OTRO_VEND, recibo: 44 })

  await listar("pendiente")
  const cols = (await pedidos.request().query("SELECT COLUMN_NAME c, IS_NULLABLE n FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='cuadres_caja'")).recordset
  const nombres = cols.map((c) => c.c)
  const requeridas = ["recaudo_id", "numero_recaudo", "recibo_caja", "cliente_id", "cliente_nombre", "valor", "banco", "numero_recibo", "observaciones", "usuario_codigo", "usuario_nombre", "fecha"]
  ok("BD: cuadres_caja guarda recaudo, recibo de caja, cliente, valor, banco, numero de recibo, observacion, usuario y fecha",
    requeridas.every((c) => nombres.includes(c)), nombres.join(","))
  const obligatorias = cols.filter((c) => ["banco", "numero_recibo", "fecha"].includes(c.c) && c.n === "NO").map((c) => c.c)
  ok("BD: banco, numero de recibo y fecha son obligatorios en la tabla", obligatorias.length === 3, obligatorias.join(","))
  const uq = (await pedidos.request().query("SELECT name FROM sys.indexes WHERE name='UQ_cuadre_recaudo'")).recordset
  ok("BD: un recaudo no se puede cuadrar dos veces (indice unico)", uq.length === 1)
  const fks = (await pedidos.request().query("SELECT name FROM sys.foreign_keys WHERE name IN ('FK_cuadre_recaudo','FK_evid_cuadre')")).recordset.map((r) => r.name)
  ok("BD: integridad referencial del cuadre y de su comprobante",
    fks.includes("FK_cuadre_recaudo") && fks.includes("FK_evid_cuadre"), fks.join(","))

  const pend = await listar("pendiente")
  const filas = (pend.json && pend.json.data) || []
  const ids = filas.map((f) => f.recaudoId)
  ok("listado: solo aparecen los recaudos en efectivo del gestor",
    pend.status === 200 && ids.includes(efectivoA) && ids.includes(efectivoB) &&
    !ids.includes(transferencia) && !ids.includes(ajeno), `${filas.length} pendientes`)
  ok("listado: es cliente a cliente, un renglon por recaudo (sin agrupar)",
    new Set(ids).size === ids.length && filas.filter((f) => f.recaudoId === efectivoA).length === 1)
  const filaA = filas.find((f) => f.recaudoId === efectivoA)
  ok("listado: cada renglon trae cliente, numero de recaudo, recibo de caja y valor",
    filaA && filaA.clienteNombre === "CLIENTE DE PRUEBA" && filaA.numeroRecaudo === `REC-CUA-${ts}-a` &&
    n(filaA.reciboCaja) === 41 && n(filaA.valor) === 150000 && filaA.cuadrado === false,
    filaA && `${filaA.numeroRecaudo} recibo ${filaA.reciboCaja} ${filaA.valor}`)

  const det = await llamar("GET", `/api/cuadres/recaudos/${efectivoA}`, { token })
  const d = det.json && det.json.data
  ok("detalle: entrega la informacion principal del recaudo y sus facturas cruzadas",
    det.status === 200 && d && d.numeroRecaudo === `REC-CUA-${ts}-a` && d.formaPago === "Efectivo" &&
    n(d.valor) === 150000 && Array.isArray(d.documentos) && d.documentos.length === 1 &&
    d.documentos[0].numFactura === "FE-CUA-a", d && `${d.documentos && d.documentos.length} factura(s)`)
  const detAjeno = await llamar("GET", `/api/cuadres/recaudos/${ajeno}`, { token })
  ok("detalle: el recaudo de otro gestor responde 404", detAjeno.status === 404, detAjeno.json && detAjeno.json.message)

  const sinBanco = await cuadrar({ recaudoId: efectivoA, numeroRecibo: "9001" })
  const sinRecibo = await cuadrar({ recaudoId: efectivoA, banco: "Bancolombia" })
  const sinFoto = await cuadrar({ recaudoId: efectivoA, banco: "Bancolombia", numeroRecibo: "9001" }, false)
  ok("obligatorio el banco: 400", sinBanco.status === 400, sinBanco.json && sinBanco.json.message)
  ok("obligatorio el numero del recibo: 400", sinRecibo.status === 400, sinRecibo.json && sinRecibo.json.message)
  ok("obligatoria la imagen del comprobante: 400", sinFoto.status === 400, sinFoto.json && sinFoto.json.message)
  const traIntentos = (await pedidos.request().input("id", sql.Int, efectivoA)
    .query("SELECT COUNT(*) n FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0].n
  ok("los intentos incompletos no escriben nada", traIntentos === 0, `registros=${traIntentos}`)

  const noEfectivo = await cuadrar({ recaudoId: transferencia, banco: "Davivienda", numeroRecibo: "9002" })
  ok("solo se cuadran los recaudos en efectivo: 409", noEfectivo.status === 409, noEfectivo.json && noEfectivo.json.message)
  const deOtro = await cuadrar({ recaudoId: ajeno, banco: "Davivienda", numeroRecibo: "9003" })
  ok("no se puede cuadrar el recaudo de otro gestor: 404", deOtro.status === 404, deOtro.json && deOtro.json.message)

  const reloj = async () => (await pedidos.request().query("SELECT GETDATE() f")).recordset[0].f
  const antes = await reloj()
  const OBS = "Consignado en la sucursal del centro"
  const hecho = await cuadrar({ recaudoId: efectivoA, banco: "Bancolombia", numeroRecibo: "9001", observaciones: OBS, fecha: "2000-01-01T00:00:00.000Z" })
  const despues = await reloj()
  ok("cuadre completo: 200 con el cuadre registrado",
    hecho.status === 200 && hecho.json.success === true && hecho.json.data && hecho.json.data.cuadreId > 0,
    hecho.json && hecho.json.message)

  const reg = (await pedidos.request().input("id", sql.Int, efectivoA).query(`
    SELECT TOP 1 id, recaudo_id, numero_recaudo, recibo_caja, recibo_prefijo, cliente_id, cliente_nombre,
           valor, banco, numero_recibo, observaciones, usuario_codigo, usuario_nombre, fecha
    FROM dbo.cuadres_caja WHERE recaudo_id=@id ORDER BY id DESC
  `)).recordset[0]
  ok("BD: el cuadre guarda banco, numero de recibo, observacion, recaudo, recibo de caja, cliente, valor y gestor",
    reg && reg.banco === "Bancolombia" && reg.numero_recibo === "9001" && reg.observaciones === OBS &&
    reg.numero_recaudo === `REC-CUA-${ts}-a` && n(reg.recibo_caja) === 41 && reg.recibo_prefijo === PREFIJO &&
    reg.cliente_id === CLIENTE && reg.cliente_nombre === "CLIENTE DE PRUEBA" && n(reg.valor) === 150000 &&
    reg.usuario_codigo === `${VEND}` && reg.usuario_nombre === "PRUEBA CUADRE",
    reg && `${reg.banco} recibo ${reg.numero_recibo} recaudo ${reg.numero_recaudo}`)
  ok("la fecha la pone el servidor y se ignora la que mande el dispositivo",
    reg && reg.fecha >= antes && reg.fecha <= despues,
    reg && reg.fecha && reg.fecha.toISOString())

  const evi = reg ? (await pedidos.request().input("c", sql.Int, reg.id)
    .query("SELECT origen, mime, tamano, ancho, alto, recaudo_id FROM dbo.evidencias_archivos WHERE cuadre_id=@c")).recordset : []
  ok("BD: la imagen del comprobante queda ligada al cuadre",
    evi.length === 1 && evi[0].origen === "cuadre" && evi[0].mime === "image/webp" && evi[0].tamano > 0 && evi[0].recaudo_id === efectivoA,
    evi[0] && `${evi[0].tamano} bytes ${evi[0].ancho}x${evi[0].alto}`)

  const repetido = await cuadrar({ recaudoId: efectivoA, banco: "Davivienda", numeroRecibo: "9009" })
  const cuantos = (await pedidos.request().input("id", sql.Int, efectivoA)
    .query("SELECT COUNT(*) n FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0].n
  ok("un recaudo ya cuadrado no se vuelve a cuadrar: 409 y sigue habiendo un solo cuadre",
    repetido.status === 409 && cuantos === 1, `${repetido.status} · registros=${cuantos}`)

  const simultaneos = await Promise.all([
    cuadrar({ recaudoId: efectivoB, banco: "Nequi", numeroRecibo: "7001" }),
    cuadrar({ recaudoId: efectivoB, banco: "Nequi", numeroRecibo: "7002" }),
  ])
  const exitosos = simultaneos.filter((r) => r.status === 200).length
  const cuantosB = (await pedidos.request().input("id", sql.Int, efectivoB)
    .query("SELECT COUNT(*) n FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0].n
  ok("concurrencia: dos cuadres a la vez sobre el mismo recaudo dejan uno solo",
    exitosos === 1 && cuantosB === 1, `ok=${exitosos} registros=${cuantosB}`)
  const eviB = (await pedidos.request().input("id", sql.Int, efectivoB)
    .query("SELECT COUNT(*) n FROM dbo.evidencias_archivos WHERE recaudo_id=@id")).recordset[0].n
  ok("transacciones: el intento perdido no deja comprobantes sueltos", eviB === 1, `comprobantes=${eviB}`)

  const pend2 = await listar("pendiente")
  const cuad2 = await listar("cuadrado")
  const idsPend = ((pend2.json && pend2.json.data) || []).map((f) => f.recaudoId)
  const cuadrados = (cuad2.json && cuad2.json.data) || []
  const filaCuadrada = cuadrados.find((f) => f.recaudoId === efectivoA)
  ok("tras cuadrar, el recaudo sale de pendientes", !idsPend.includes(efectivoA) && !idsPend.includes(efectivoB))
  ok("el listado de cuadrados muestra banco, numero de recibo, observacion y comprobante",
    filaCuadrada && filaCuadrada.cuadrado === true && filaCuadrada.cuadre &&
    filaCuadrada.cuadre.banco === "Bancolombia" && filaCuadrada.cuadre.numeroRecibo === "9001" &&
    filaCuadrada.cuadre.observaciones === OBS && n(filaCuadrada.cuadre.evidencias) === 1,
    filaCuadrada && filaCuadrada.cuadre && `${filaCuadrada.cuadre.banco} ${filaCuadrada.cuadre.numeroRecibo}`)

  const sinObs = await crearRecaudo("c", { valor: 33000, recibo: 45 })
  const hechoSinObs = await cuadrar({ recaudoId: sinObs, banco: "Davivienda", numeroRecibo: "9005" })
  const regSinObs = (await pedidos.request().input("id", sql.Int, sinObs)
    .query("SELECT observaciones, banco FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0]
  ok("la observacion es opcional: el cuadre se registra sin ella",
    hechoSinObs.status === 200 && regSinObs && regSinObs.banco === "Davivienda" && regSinObs.observaciones === null,
    hechoSinObs.json && hechoSinObs.json.message)

  const otroVe = await llamar("GET", "/api/cuadres/recaudos?estado=cuadrado", { token: tokenOtro })
  const idsOtro = ((otroVe.json && otroVe.json.data) || []).map((f) => f.recaudoId)
  ok("cada gestor solo ve sus propios recaudos", otroVe.status === 200 && !idsOtro.includes(efectivoA) && !idsOtro.includes(efectivoB))

  const totalPend = (pend.json && pend.json.valorTotal) || 0
  ok("el listado informa el total pendiente por cuadrar", totalPend >= 240000, `${totalPend}`)

  const antesBorrar = (await pedidos.request().input("id", sql.Int, sinObs)
    .query("SELECT COUNT(*) n FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0].n
  await pedidos.request().input("id", sql.Int, sinObs).query("DELETE FROM dbo.recaudos WHERE id=@id")
  const despuesBorrar = (await pedidos.request().input("id", sql.Int, sinObs)
    .query("SELECT COUNT(*) n FROM dbo.cuadres_caja WHERE recaudo_id=@id")).recordset[0].n
  const eviHuerfana = (await pedidos.request().input("id", sql.Int, sinObs)
    .query("SELECT COUNT(*) n FROM dbo.evidencias_archivos WHERE recaudo_id=@id")).recordset[0].n
  ok("integridad: al borrar el recaudo se van su cuadre y su comprobante",
    antesBorrar === 1 && despuesBorrar === 0 && eviHuerfana === 0, `${antesBorrar} -> ${despuesBorrar}`)

  await limpiar()
  try { await sesiones.cerrar(pedidos, sql, jti, "prueba") } catch (_) {}
  try { await sesiones.cerrar(pedidos, sql, jtiOtro, "prueba") } catch (_) {}
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "CUADRES OK\n" : "HAY FALLOS EN CUADRES\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
