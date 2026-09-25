const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99992
const OTRO_VEND = 99993
const CLIENTE = "CLI-TAREA-PRUEBA"
const OTRO_CLIENTE = "CLI-TAREA-OTRO"
const MARCA = `PRUEBA AUTOMATICA ${ts}`

function llamar(metodo, ruta, { token, body } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body !== undefined ? JSON.stringify(body) : null
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

  const ajena = await llamar("GET", "/api/tareas", { token: otro.token })
  const idsAjenos = ((ajena.json && ajena.json.data) || []).map((t) => t.id)
  ok("otro gestor no ve las tareas ajenas", idsAjenos.includes(tAjena) && !idsAjenos.includes(tPendiente))

  await limpiar()
  const restos = (await pedidos.request().input("m", sql.NVarChar, `${MARCA}%`)
    .query("SELECT COUNT(*) n FROM dbo.tareas WHERE nombre LIKE @m")).recordset[0].n
  ok("limpieza: no quedan tareas de prueba", restos === 0, `restos=${restos}`)

  for (const s of [yo, otro]) { try { await sesiones.cerrar(pedidos, sql, s.jti, "prueba") } catch (_) {} }
  await pedidos.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "TAREAS OK\n" : "HAY FALLOS EN TAREAS\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n" + e.stack + "\n"); process.exit(1) })
