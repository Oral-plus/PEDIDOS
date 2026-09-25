const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))
const sharp = require(path.join(process.cwd(), "node_modules", "sharp"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99992
const OTRO_VEND = 99993
const CLIENTE = "CLI-TAREA-PRUEBA"
const OTRO_CLIENTE = "CLI-TAREA-OTRO"
const MARCA = `PRUEBA AUTOMATICA ${ts}`

const FIN = "\r\n"
function multipart(campos, archivos) {
  const limite = "----tareas" + Math.random().toString(16).slice(2)
  const partes = []
  for (const [clave, valor] of Object.entries(campos)) {
    partes.push(Buffer.from(`--${limite}${FIN}Content-Disposition: form-data; name="${clave}"${FIN}${FIN}${valor}${FIN}`))
  }
  for (const a of archivos) {
    partes.push(Buffer.from(`--${limite}${FIN}Content-Disposition: form-data; name="fotos"; filename="${a.nombre}"${FIN}Content-Type: image/png${FIN}${FIN}`))
    partes.push(a.contenido)
    partes.push(Buffer.from(FIN))
  }
  partes.push(Buffer.from(`--${limite}--${FIN}`))
  return { body: Buffer.concat(partes), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

const imagenPrueba = (color) => sharp({ create: { width: 900, height: 700, channels: 3, background: color } }).png().toBuffer()

function llamar(metodo, ruta, { token, body, mp } = {}) {
  return new Promise((resolve, reject) => {
    const datos = mp ? mp.body : body !== undefined ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (mp) Object.assign(h, mp.headers)
    else if (datos) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = Buffer.byteLength(datos)
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
const cfg = { server: process.env.DB_SERVER, database: process.env.PEDIDOS_DB_NAME || "Pedidos", user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } }

;(async () => {
  const out = []
  const ok = (nm, c, extra) => out.push([nm + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg).connect()
  const sesion = async (codigo, nombre) => {
    const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${codigo}`, usuarioNombre: nombre, tipo: "vendedor", plataforma: "prueba", duracionSeg: 900 })
    return { jti, token: jwt.sign({ userId: codigo, nombre, tipo: "vendedor", jti }, process.env.JWT_SECRET, { expiresIn: 900 }) }
  }
  const yo = await sesion(VEND, "PRUEBA TAREAS")
  const otro = await sesion(OTRO_VEND, "OTRO GESTOR")

  const limpiar = async () => {
    await pedidos.request().input("m", sql.NVarChar, `${MARCA}%`).query(`
      DELETE e FROM dbo.evidencias_archivos e
        JOIN dbo.tareas_respuestas r ON r.id = e.tarea_respuesta_id
        WHERE r.cliente_codigo IN ('${CLIENTE}', '${OTRO_CLIENTE}');
      DELETE FROM dbo.tareas_respuestas WHERE cliente_codigo IN ('${CLIENTE}', '${OTRO_CLIENTE}');
      DELETE g FROM dbo.tareas_gestores g JOIN dbo.tareas t ON t.id = g.tarea_id WHERE t.nombre LIKE @m;
      DELETE c FROM dbo.tareas_clientes c JOIN dbo.tareas t ON t.id = c.tarea_id WHERE t.nombre LIKE @m;
      DELETE FROM dbo.tareas WHERE nombre LIKE @m;`)
  }
  await limpiar()

  const crearTarea = async (sufijo, { estado = "PENDIENTE", indefinido = 0, dias = 3, cliente = CLIENTE, vendedor = VEND } = {}) => {
    const r = await pedidos.request()
      .input("n", sql.NVarChar, `${MARCA} ${sufijo}`)
      .input("d", sql.NVarChar, "Tarea creada por la suite de integracion")
      .input("ind", sql.Bit, indefinido)
      .input("est", sql.NVarChar, estado)
      .input("dias", sql.Int, dias)
      .query(`
        INSERT INTO dbo.tareas (nombre, descripcion, area, fecha_limite, indefinido, estado, usuario, fecha_creacion)
        OUTPUT INSERTED.id
        VALUES (@n, @d, 'VENTAS', DATEADD(day, @dias, CAST(GETDATE() AS DATE)), @ind, @est, 'suite', GETDATE())`)
    const id = r.recordset[0].id
    await pedidos.request().input("t", sql.Int, id).input("v", sql.Int, vendedor)
      .query("INSERT INTO dbo.tareas_gestores (tarea_id, vendedor_codigo, vendedor_nombre) VALUES (@t, @v, 'PRUEBA TAREAS')")
    await pedidos.request().input("t", sql.Int, id).input("c", sql.NVarChar, cliente)
      .query("INSERT INTO dbo.tareas_clientes (tarea_id, cliente_codigo, cliente_nombre) VALUES (@t, @c, 'CLIENTE DE PRUEBA')")
    return id
  }

  const tPendiente = await crearTarea("pendiente")
  const tVencida = await crearTarea("vencida", { dias: -4 })
  const tIndefinida = await crearTarea("indefinida", { indefinido: 1 })
  const tHecha = await crearTarea("terminada", { estado: "COMPLETADA" })
  const tOtroCliente = await crearTarea("otro-cliente", { cliente: OTRO_CLIENTE })
  const tAjena = await crearTarea("de-otro-gestor", { vendedor: OTRO_VEND })

  const mias = await llamar("GET", "/api/tareas", { token: yo.token })
  const ids = ((mias.json && mias.json.data) || []).map((t) => t.id)
  ok("el gestor ve las tareas que le asignaron, y solo esas",
    mias.status === 200 && [tPendiente, tVencida, tIndefinida, tHecha, tOtroCliente].every((id) => ids.includes(id)) && !ids.includes(tAjena),
    `${ids.length} tarea(s)`)

  const r = mias.json.resumen || {}
  ok("el resumen separa pendientes, vencidas y terminadas",
    r.pendientes >= 4 && r.vencidas >= 1 && r.terminadas >= 1, JSON.stringify(r))

  const detalle = ((mias.json && mias.json.data) || []).find((t) => t.id === tPendiente)
  ok("cada tarea trae su descripcion, area, plazo y el cliente asociado",
    detalle && detalle.area === "VENTAS" && detalle.descripcion.length > 0 && detalle.diasRestantes === 3 &&
      detalle.clientes.length === 1 && detalle.clientes[0].codigo === CLIENTE,
    detalle && `${detalle.diasRestantes} dias, cliente ${detalle.clientes[0] && detalle.clientes[0].codigo}`)

  const indef = ((mias.json && mias.json.data) || []).find((t) => t.id === tIndefinida)
  const venc = ((mias.json && mias.json.data) || []).find((t) => t.id === tVencida)
  ok("la tarea sin fecha limite no aparece como vencida", indef && indef.indefinido === true && indef.fechaLimite === null && indef.vencida === false)
  ok("la tarea con el plazo pasado sale marcada como vencida", venc && venc.vencida === true && venc.diasRestantes === -4)

  const delCliente = await llamar("GET", `/api/tareas?cliente=${encodeURIComponent(CLIENTE)}`, { token: yo.token })
  const idsCliente = ((delCliente.json && delCliente.json.data) || []).map((t) => t.id)
  ok("al abrir la visita, solo llegan las tareas de ese cliente",
    delCliente.status === 200 && idsCliente.includes(tPendiente) && !idsCliente.includes(tOtroCliente),
    `${idsCliente.length} tarea(s) para ${CLIENTE}`)
  ok("el servidor avisa cuantas tareas faltan por registrar (lo que bloquea el cierre)",
    delCliente.json.pendientesPorResponder === 3, `${delCliente.json.pendientesPorResponder} por responder`)

  const sinCliente = await llamar("POST", `/api/tareas/${tPendiente}/respuesta`, { token: yo.token, body: { cumplida: true } })
  ok("responder sin indicar el cliente: 400", sinCliente.status === 400, sinCliente.json && sinCliente.json.message)

  const resp = await llamar("POST", `/api/tareas/${tPendiente}/respuesta`, {
    token: yo.token,
    body: { clienteCodigo: CLIENTE, visitaId: 987654, cumplida: false, observacion: "El cliente no tenia espacio en gondola" },
  })
  ok("se registra la informacion de la tarea en la visita", resp.status === 200 && resp.json.data && resp.json.data.id > 0)

  const fila = (await pedidos.request().input("t", sql.Int, tPendiente).query(`
    SELECT cliente_codigo, vendedor_codigo, visita_id, cumplida, observacion FROM dbo.tareas_respuestas WHERE tarea_id=@t`)).recordset[0]
  ok("BD: queda guardado quien respondio, en que visita, si se cumplio y el motivo",
    fila && fila.cliente_codigo === CLIENTE && fila.vendedor_codigo === VEND && fila.visita_id === 987654 &&
      fila.cumplida === false && fila.observacion.startsWith("El cliente no tenia"),
    fila && `visita ${fila.visita_id} cumplida ${fila.cumplida}`)

  const tras = await llamar("GET", `/api/tareas?cliente=${encodeURIComponent(CLIENTE)}`, { token: yo.token })
  const respondida = ((tras.json && tras.json.data) || []).find((t) => t.id === tPendiente)
  ok("la tarea respondida deja de bloquear y muestra lo que se registro",
    tras.json.pendientesPorResponder === 2 && respondida && respondida.respondida === true &&
      respondida.respuesta && respondida.respuesta.cumplida === false,
    `${tras.json.pendientesPorResponder} por responder`)

  const laTarea = (await pedidos.request().input("t", sql.Int, tPendiente).query("SELECT estado FROM dbo.tareas WHERE id=@t")).recordset[0]
  ok("responder NO altera la tarea original (la comparten otros gestores y clientes)",
    laTarea && laTarea.estado === "PENDIENTE", laTarea && laTarea.estado)

  const fotos = [
    { nombre: "gondola1.png", contenido: await imagenPrueba({ r: 200, g: 40, b: 40 }) },
    { nombre: "gondola2.png", contenido: await imagenPrueba({ r: 40, g: 200, b: 40 }) },
  ]
  const conFotos = await llamar("POST", `/api/tareas/${tVencida}/respuesta`, {
    token: yo.token,
    mp: multipart({ clienteCodigo: CLIENTE, visitaId: "987654", cumplida: "true", observacion: "Exhibicion montada" }, fotos),
  })
  ok("se puede responder adjuntando fotos de la tarea",
    conFotos.status === 200 && conFotos.json.data && conFotos.json.data.evidencias === 2,
    conFotos.json && conFotos.json.data && `${conFotos.json.data.evidencias} foto(s)`)

  const guardadas = (await pedidos.request().input("r", sql.Int, conFotos.json.data.id).query(`
    SELECT origen, cliente_id, vendedor_id, tamano, ancho, DATALENGTH(contenido) bytes
    FROM dbo.evidencias_archivos WHERE tarea_respuesta_id = @r`)).recordset
  ok("BD: cada foto queda ligada a la respuesta, comprimida y con su cliente",
    guardadas.length === 2 && guardadas.every((f) => f.origen === "tarea" && f.cliente_id === CLIENTE && Number(f.vendedor_id) === VEND && f.bytes > 0 && f.bytes < 100000 && f.ancho > 0),
    guardadas.map((f) => `${f.ancho}px ${f.bytes}B`).join(" · "))

  const conRespuesta = await llamar("GET", `/api/tareas?cliente=${encodeURIComponent(CLIENTE)}`, { token: yo.token })
  const conEvidencia = ((conRespuesta.json && conRespuesta.json.data) || []).find((t) => t.id === tVencida)
  ok("al volver a abrir la visita se ve cuantas fotos quedaron adjuntas",
    conEvidencia && conEvidencia.respuesta && conEvidencia.respuesta.evidencias === 2 && conEvidencia.respuesta.cumplida === true,
    conEvidencia && conEvidencia.respuesta && `${conEvidencia.respuesta.evidencias} foto(s)`)

  // Reintento del gestor cuando la red se cae despues de que el servidor ya guardo.
  const clave = `clave-prueba-${ts}`
  const envio = () => llamar("POST", `/api/tareas/${tHecha}/respuesta`, {
    token: yo.token,
    mp: multipart({ clienteCodigo: CLIENTE, cumplida: "true", observacion: "Reintento", claveLocal: clave }, fotos),
  })
  const primero = await envio()
  const segundo = await envio()
  const filas = (await pedidos.request().input("c", sql.NVarChar, clave)
    .query("SELECT COUNT(*) n FROM dbo.tareas_respuestas WHERE clave_local = @c")).recordset[0].n
  const fotosClave = (await pedidos.request().input("r", sql.Int, primero.json.data.id)
    .query("SELECT COUNT(*) n FROM dbo.evidencias_archivos WHERE tarea_respuesta_id = @r")).recordset[0].n
  ok("reenviar la misma respuesta no la duplica: devuelve la que ya estaba",
    primero.status === 200 && segundo.status === 200 &&
      segundo.json.data.id === primero.json.data.id && segundo.json.data.repetida === true &&
      filas === 1 && fotosClave === 2,
    `${filas} respuesta(s), ${fotosClave} foto(s)`)

  const demasiadas = await llamar("POST", `/api/tareas/${tIndefinida}/respuesta`, {
    token: yo.token,
    mp: multipart({ clienteCodigo: CLIENTE, cumplida: "true" }, [...fotos, ...fotos]),
  })
  const huerfanas = (await pedidos.request().input("c", sql.NVarChar, CLIENTE).query(`
    SELECT COUNT(*) n FROM dbo.tareas_respuestas WHERE tarea_id = ${tIndefinida} AND cliente_codigo = @c`)).recordset[0].n
  ok("con mas fotos de las permitidas se rechaza entero, sin dejar la respuesta a medias",
    demasiadas.status === 400 && huerfanas === 0, `${demasiadas.status}, ${huerfanas} respuesta(s)`)

  const ajena = await llamar("GET", "/api/tareas", { token: otro.token })
  const idsAjenos = ((ajena.json && ajena.json.data) || []).map((t) => t.id)
  ok("otro gestor no ve las tareas ajenas", idsAjenos.includes(tAjena) && !idsAjenos.includes(tPendiente))

  await limpiar()
  const restos = (await pedidos.request().input("m", sql.NVarChar, `${MARCA}%`).input("c", sql.NVarChar, CLIENTE)
    .query(`SELECT (SELECT COUNT(*) FROM dbo.tareas WHERE nombre LIKE @m) +
                   (SELECT COUNT(*) FROM dbo.evidencias_archivos WHERE origen='tarea' AND cliente_id=@c) n`)).recordset[0].n
  ok("limpieza: no quedan tareas ni fotos de prueba", restos === 0, `restos=${restos}`)

  for (const s of [yo, otro]) { try { await sesiones.cerrar(pedidos, sql, s.jti, "prueba") } catch (_) {} }
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "TAREAS OK\n" : "HAY FALLOS EN TAREAS\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n" + e.stack + "\n"); process.exit(1) })
