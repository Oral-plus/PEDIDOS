const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sesiones = require(path.join(process.cwd(), "modules", "sesiones"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const ts = Date.now()
const VEND = 99985
const OTRO_VEND = 99986
const NUM_PEDIDO_CLIENTE = "CLI-UBIC"

function llamar(metodo, ruta, { token, body } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body !== undefined ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) {
      h["Content-Type"] = "application/json"
      h["Content-Length"] = Buffer.byteLength(datos)
    }
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
const cfg = (database) => ({ server: process.env.DB_SERVER, database, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })
const hoyLocal = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }
const isoLocal = (d) => {
  const p = (n, l = 2) => String(n).padStart(l, "0")
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`
}

;(async () => {
  const out = []
  const ok = (nm, c, extra) => out.push([nm + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const pedidos = await new sql.ConnectionPool(cfg(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const ruta = await new sql.ConnectionPool(cfg(process.env.RUTA_DB_NAME || "Ruta")).connect()
  const sesion = async (codigo, nombre, extra = {}) => {
    const jti = await sesiones.registrar(pedidos, sql, { usuarioCodigo: `${codigo}`, usuarioNombre: nombre, tipo: extra.tipo || "vendedor", rol: extra.rol, plataforma: "prueba", duracionSeg: 900 })
    return { jti, token: jwt.sign({ userId: codigo, nombre, tipo: extra.tipo || "vendedor", ...(extra.rol ? { rol: extra.rol } : {}), jti }, process.env.JWT_SECRET, { expiresIn: 900 }) }
  }
  const yo = await sesion(VEND, "PRUEBA UBICACION")
  const otro = await sesion(OTRO_VEND, "OTRO UBICACION")
  const soporte = await sesion(99987, "SOPORTE UBICACION", { tipo: "usuario", rol: "soporte" })
  const token = yo.token

  let numeroPedido = null
  const limpiar = async () => {
    await pedidos.request().input("a", sql.NVarChar, `${VEND}`).input("b", sql.NVarChar, `${OTRO_VEND}`)
      .query("IF OBJECT_ID('dbo.ubicaciones_recorrido') IS NOT NULL DELETE FROM dbo.ubicaciones_recorrido WHERE usuario_codigo IN (@a, @b)")
    await ruta.request().input("a", sql.Int, VEND).input("b", sql.Int, OTRO_VEND)
      .query("DELETE FROM dbo.visitas_clientes WHERE vendedor_id IN (@a, @b)")
    if (numeroPedido) {
      await pedidos.request().input("n", sql.NVarChar, numeroPedido).query(`
        DELETE h FROM pedidos_historial h JOIN pedidos p ON p.id = h.pedido_id WHERE p.numero_pedido = @n;
        DELETE d FROM pedidos_detalle d JOIN pedidos p ON p.id = d.pedido_id WHERE p.numero_pedido = @n;
        DELETE FROM pedidos WHERE numero_pedido = @n;`)
    }
  }
  await limpiar()

  const geo = (await ruta.request().query(`
    SELECT TOP 1 cliente_codigo, CAST(latitud AS FLOAT) lat, CAST(longitud AS FLOAT) lng
    FROM dbo.geolocalizacion
    WHERE latitud IS NOT NULL AND longitud IS NOT NULL AND ABS(latitud) > 0.5 AND cliente_codigo LIKE 'C%'
    ORDER BY id`)).recordset[0]
  const CLIENTE = geo.cliente_codigo
  const LEJOS = { lat: geo.lat + 0.01, lng: geo.lng }

  const lote = [
    { idLocal: `u-${ts}-a`, latitud: geo.lat, longitud: geo.lng, precision: 8, clienteCodigo: CLIENTE, capturadoEnMs: Date.now() - 60000 },
    { idLocal: `u-${ts}-b`, latitud: LEJOS.lat, longitud: LEJOS.lng, precision: 5, simulada: true, clienteCodigo: CLIENTE, capturadoEnMs: Date.now() },
    { idLocal: `u-${ts}-c`, latitud: 999, longitud: -74 },
    { idLocal: `u-${ts}-d`, latitud: geo.lat + 0.0002, longitud: geo.lng, precision: 12, capturadoEn: isoLocal(new Date()) },
  ]
  const r1 = await llamar("POST", "/api/ubicaciones", { token, body: { puntos: lote } })
  const d1 = r1.json && r1.json.data
  ok("lote de ubicaciones: 200, guarda 3 validas y descarta la invalida",
    r1.status === 200 && d1 && d1.guardados === 3 && d1.descartados === 1 && d1.simuladas === 1,
    d1 && `guardados=${d1.guardados} descartados=${d1.descartados} simuladas=${d1.simuladas}`)
  const pA = d1 && d1.puntos.find((p) => p.idLocal === `u-${ts}-a`)
  const pB = d1 && d1.puntos.find((p) => p.idLocal === `u-${ts}-b`)
  const pD = d1 && d1.puntos.find((p) => p.idLocal === `u-${ts}-d`)
  ok("en cliente: el punto sobre las coordenadas del cliente de SAP queda EN CLIENTE",
    pA && pA.enCliente === true && pA.clienteCodigo === CLIENTE && pA.distanciaM <= 1, pA && `${pA.clienteCodigo} ${pA.distanciaM}m`)
  ok("en cliente: sin visita, un punto a ~22 m se asocia al cliente mas cercano",
    pD && pD.enCliente === true && pD.clienteCodigo && pD.distanciaM <= 30, pD && `${pD.clienteCodigo} ${pD.distanciaM}m`)
  ok("fuera de cliente: el punto a ~1.1 km del cliente no queda en cliente",
    pB && pB.enCliente === false && pB.clienteCodigo === CLIENTE && pB.distanciaM > 1000, pB && `${pB.clienteCodigo} ${pB.distanciaM}m`)

  const r2 = await llamar("POST", "/api/ubicaciones", { token, body: { puntos: lote } })
  const d2 = r2.json && r2.json.data
  ok("idempotencia: reenviar el mismo lote desde la cola no duplica puntos",
    r2.status === 200 && d2 && d2.guardados === 0 && d2.duplicados === 3, d2 && `guardados=${d2.guardados} duplicados=${d2.duplicados}`)

  const filas = (await pedidos.request().input("u", sql.NVarChar, `${VEND}`).query(`
    SELECT id_local, simulada, en_cliente, cliente_codigo, distancia_cliente_m, usuario_nombre, tipo_usuario, origen, CAST(latitud AS FLOAT) lat
    FROM dbo.ubicaciones_recorrido WHERE usuario_codigo = @u`)).recordset
  const fA = filas.find((f) => f.id_local === `u-${ts}-a`)
  const fB = filas.find((f) => f.id_local === `u-${ts}-b`)
  ok("BD: cada punto queda con usuario, coordenadas, cliente, distancia, en_cliente y origen",
    filas.length === 3 && fA && fA.en_cliente === true && fA.cliente_codigo === CLIENTE && fA.usuario_nombre === "PRUEBA UBICACION" &&
    fA.tipo_usuario === "vendedor" && fA.origen === "periodico" && Math.abs(fA.lat - geo.lat) < 0.000001,
    `${filas.length} filas`)
  ok("BD: la ubicacion simulada por otra app queda marcada", fB && fB.simulada === true && fB.en_cliente === false)
  const horas = (await pedidos.request().input("u", sql.NVarChar, `${VEND}`)
    .query("SELECT id_local, DATEDIFF(second, fecha_captura, GETDATE()) seg FROM dbo.ubicaciones_recorrido WHERE usuario_codigo = @u")).recordset
  const seg = (sufijo) => { const h = horas.find((x) => x.id_local === `u-${ts}-${sufijo}`); return h ? h.seg : null }
  ok("BD: la hora de captura del telefono queda en hora local del servidor, sin desfase de zona horaria",
    Math.abs(seg("a") - 60) <= 30 && Math.abs(seg("b")) <= 30 && Math.abs(seg("d")) <= 30,
    `a=${seg("a")}s b=${seg("b")}s d=${seg("d")}s`)

  const cerca = await llamar("GET", `/api/ubicaciones/en-cliente?cliente=${encodeURIComponent(CLIENTE)}&lat=${geo.lat}&lng=${geo.lng}`, { token })
  const lejos = await llamar("GET", `/api/ubicaciones/en-cliente?cliente=${encodeURIComponent(CLIENTE)}&lat=${LEJOS.lat}&lng=${LEJOS.lng}`, { token })
  ok("consulta en cliente: sobre la direccion del cliente responde enCliente=true",
    cerca.status === 200 && cerca.json.data.enCliente === true && cerca.json.data.distanciaM === 0 && cerca.json.data.radioM > 0,
    cerca.json && JSON.stringify(cerca.json.data))
  ok("consulta en cliente: a ~1.1 km responde enCliente=false con la distancia",
    lejos.status === 200 && lejos.json.data.enCliente === false && lejos.json.data.distanciaM > 1000 && lejos.json.data.distanciaM < 1200,
    lejos.json && `${lejos.json.data.distanciaM}m`)
  const sinCoord = await llamar("GET", `/api/ubicaciones/en-cliente?cliente=CLI-UBIC-NO-EXISTE-${ts}&lat=${geo.lat}&lng=${geo.lng}`, { token })
  ok("consulta en cliente: cliente sin coordenadas ni direccion en SAP responde sinCoordenadas",
    sinCoord.status === 200 && sinCoord.json.data.sinCoordenadas === true && sinCoord.json.data.enCliente === null)
  const malas = await llamar("GET", `/api/ubicaciones/en-cliente?cliente=${CLIENTE}&lat=abc&lng=1`, { token })
  ok("consulta en cliente: coordenadas invalidas responden 400", malas.status === 400)

  const rec = await llamar("GET", `/api/ubicaciones/recorrido?fecha=${hoyLocal()}`, { token })
  ok("recorrido propio: devuelve los puntos del dia con su resumen",
    rec.status === 200 && rec.json.data.length === 3 && rec.json.resumen.simuladas === 1 && rec.json.resumen.enCliente === 2,
    rec.json && JSON.stringify(rec.json.resumen))
  const ajeno = await llamar("GET", `/api/ubicaciones/recorrido?usuario=${VEND}`, { token: otro.token })
  ok("recorrido ajeno: un vendedor no puede ver el recorrido de otro (403)", ajeno.status === 403)
  const deSoporte = await llamar("GET", `/api/ubicaciones/recorrido?usuario=${VEND}&fecha=${hoyLocal()}`, { token: soporte.token })
  ok("recorrido desde soporte: puede consultar a cualquier usuario", deSoporte.status === 200 && deSoporte.json.data.length === 3)
  const usuariosVend = await llamar("GET", "/api/ubicaciones/usuarios", { token })
  const usuariosSop = await llamar("GET", `/api/ubicaciones/usuarios?fecha=${hoyLocal()}`, { token: soporte.token })
  const filaSop = usuariosSop.json && (usuariosSop.json.data || []).find((u) => u.usuarioCodigo === `${VEND}`)
  ok("usuarios con recorrido: solo soporte (403 para vendedor)", usuariosVend.status === 403)
  ok("usuarios con recorrido: soporte ve al usuario con su alerta de ubicacion simulada",
    usuariosSop.status === 200 && filaSop && filaSop.puntos === 3 && filaSop.simuladas === 1,
    filaSop && JSON.stringify(filaSop))

  const hoyAntes = await llamar("GET", `/api/clientes/${encodeURIComponent(CLIENTE)}/visitas-hoy`, { token })
  const totalAntes = hoyAntes.json && hoyAntes.json.data ? hoyAntes.json.data.total : -1
  const inicio = new Date(Date.now() - 10 * 60 * 1000)
  const abrir = () => llamar("POST", `/api/clientes/${encodeURIComponent(CLIENTE)}/visita/iniciar`, {
    token,
    body: { horaInicio: isoLocal(inicio), duracionSegundos: 600, ubicacion: { idLocal: `v-${ts}-ini`, latitud: geo.lat, longitud: geo.lng, precision: 9 } },
  })
  const ab = await abrir()
  const visitaId = ab.json && ab.json.data && ab.json.data.id
  ok("abrir visita: 200 con id y en cliente", ab.status === 200 && visitaId > 0 && ab.json.data.enCliente === true && ab.json.data.reutilizada === false,
    ab.json && JSON.stringify(ab.json.data))
  const filaAbierta = visitaId ? (await ruta.request().input("id", sql.Int, visitaId).query(`
    SELECT estado_visita, hora_inicio, hora_fin, duracion_segundos, en_cliente_inicio, distancia_cliente_inicio_m, CAST(lat_inicio AS FLOAT) lat, vendedor_id
    FROM dbo.visitas_clientes WHERE id=@id`)).recordset[0] : null
  ok("BD: al ABRIR la visita ya queda insertada con hora de inicio, tiempo y ubicacion",
    filaAbierta && filaAbierta.estado_visita === "abierta" && filaAbierta.hora_inicio && !filaAbierta.hora_fin &&
    filaAbierta.duracion_segundos === 600 && filaAbierta.en_cliente_inicio === true && filaAbierta.vendedor_id === VEND &&
    Math.abs(filaAbierta.lat - geo.lat) < 0.000001, filaAbierta && JSON.stringify(filaAbierta))
  const ab2 = await abrir()
  ok("abrir visita: reintentar la misma apertura reutiliza la fila", ab2.status === 200 && ab2.json.data.id === visitaId && ab2.json.data.reutilizada === true)

  const hoyAbierta = await llamar("GET", `/api/clientes/${encodeURIComponent(CLIENTE)}/visitas-hoy`, { token })
  ok("visitas-hoy: una visita abierta no cuenta como visitada (no dispara segunda visita)",
    hoyAbierta.status === 200 && hoyAbierta.json.data.total === totalAntes, `${totalAntes} -> ${hoyAbierta.json && hoyAbierta.json.data.total}`)

  const pulso = await llamar("PUT", `/api/clientes/${encodeURIComponent(CLIENTE)}/visita/${visitaId}/actividad`, { token, body: { duracionSegundos: 900 } })
  const durPulso = (await ruta.request().input("id", sql.Int, visitaId).query("SELECT duracion_segundos d, ultima_actividad u FROM dbo.visitas_clientes WHERE id=@id")).recordset[0]
  ok("pulso: mientras esta abierta se va guardando el tiempo transcurrido", pulso.status === 200 && durPulso.d === 900 && durPulso.u, `dur=${durPulso.d}`)
  const pulsoAjeno = await llamar("PUT", `/api/clientes/${encodeURIComponent(CLIENTE)}/visita/${visitaId}/actividad`, { token: otro.token, body: { duracionSegundos: 5 } })
  ok("pulso: otro vendedor no puede tocar la visita (404)", pulsoAjeno.status === 404)

  const cierre = await llamar("POST", `/api/clientes/${encodeURIComponent(CLIENTE)}/visita`, {
    token,
    body: {
      visitaId, motivo: "Otro", observacion: "prueba ubicaciones", horaInicio: isoLocal(inicio), horaFin: isoLocal(new Date()),
      duracionSegundos: 915, ubicacion: { idLocal: `v-${ts}-fin`, latitud: LEJOS.lat, longitud: LEJOS.lng, precision: 7 },
    },
  })
  const cerrada = (await ruta.request().input("id", sql.Int, visitaId).query(`
    SELECT estado_visita, hora_fin, duracion_segundos, motivo_no_gestion, en_cliente_fin, distancia_cliente_fin_m, en_cliente_inicio
    FROM dbo.visitas_clientes WHERE id=@id`)).recordset[0]
  const filasVisita = (await ruta.request().input("v", sql.Int, VEND).input("c", sql.NVarChar, CLIENTE)
    .query("SELECT COUNT(*) n FROM dbo.visitas_clientes WHERE vendedor_id=@v AND cliente_id=@c")).recordset[0].n
  ok("cerrar visita: actualiza la MISMA fila (sin duplicar) con fin, duracion y motivo",
    cierre.status === 200 && cierre.json.data.id === visitaId && filasVisita === 1 && cerrada.estado_visita === "cerrada" &&
    cerrada.hora_fin && cerrada.duracion_segundos === 915 && cerrada.motivo_no_gestion === "Otro",
    `filas=${filasVisita} ${JSON.stringify(cerrada)}`)
  ok("cerrar visita: guarda si al cerrar estaba en el cliente",
    cerrada.en_cliente_fin === false && cerrada.distancia_cliente_fin_m > 1000 && cerrada.en_cliente_inicio === true && cierre.json.data.enCliente === false)
  const hoyDespues = await llamar("GET", `/api/clientes/${encodeURIComponent(CLIENTE)}/visitas-hoy`, { token })
  ok("visitas-hoy: al cerrarla ya cuenta como visitada", hoyDespues.json.data.total === totalAntes + 1, `${totalAntes} -> ${hoyDespues.json.data.total}`)
  const puntosVisita = (await pedidos.request().input("u", sql.NVarChar, `${VEND}`).input("v", sql.Int, visitaId)
    .query("SELECT origen FROM dbo.ubicaciones_recorrido WHERE usuario_codigo=@u AND visita_id=@v ORDER BY id")).recordset.map((f) => f.origen)
  ok("recorrido: la apertura y el cierre de la visita quedan como puntos del recorrido",
    puntosVisita.length === 2 && puntosVisita[0] === "visita_inicio" && puntosVisita[1] === "visita_fin", puntosVisita.join(","))

  const legado = await llamar("POST", `/api/clientes/${encodeURIComponent(CLIENTE)}/visita`, {
    token, body: { motivo: "Otro", horaInicio: isoLocal(inicio), horaFin: isoLocal(new Date()), duracionSegundos: 42 },
  })
  const filaLegado = legado.json && legado.json.data ? (await ruta.request().input("id", sql.Int, legado.json.data.id)
    .query("SELECT estado_visita, duracion_segundos FROM dbo.visitas_clientes WHERE id=@id")).recordset[0] : null
  ok("compatibilidad: una app vieja que solo cierra la visita sigue insertando la fila",
    legado.status === 200 && legado.json.data.id !== visitaId && filaLegado && filaLegado.estado_visita === "cerrada" && filaLegado.duracion_segundos === 42)

  const rPed = await llamar("POST", "/api/orders", {
    token,
    body: {
      cedula: NUM_PEDIDO_CLIENTE, nombre: "PRUEBA UBICACION", correo: "p@oral-plus.com", codigoCliente: NUM_PEDIDO_CLIENTE, vendedor: "PRUEBA UBICACION",
      comentarioDespacho: "Entregar en la bodega trasera antes de las 10", comentarioComercial: "Cliente pidio precio especial la proxima vez",
      productos: [{ codigo: "PRB1", nombre: "Prod prueba", cantidad: 1, precio: 1000 }],
    },
  })
  numeroPedido = rPed.json && rPed.json.docNum
  const fPed = numeroPedido ? (await pedidos.request().input("n", sql.NVarChar, numeroPedido)
    .query("SELECT comentario_despacho, comentario_comercial, observaciones FROM pedidos WHERE numero_pedido=@n")).recordset[0] : null
  ok("pedido: guarda comentario de despachos y comentario comercial por separado (observaciones intacta)",
    rPed.status === 200 && fPed && fPed.comentario_despacho === "Entregar en la bodega trasera antes de las 10" &&
    fPed.comentario_comercial === "Cliente pidio precio especial la proxima vez" && fPed.observaciones === null,
    fPed && JSON.stringify(fPed))
  const hist = await llamar("GET", "/api/indicadores/pedidos", { token })
  const enHist = hist.json && (hist.json.data || []).find((p) => p.numeroPedido === numeroPedido)
  ok("historial de pedidos: devuelve los dos comentarios",
    enHist && enHist.comentarioDespacho.startsWith("Entregar") && enHist.comentarioComercial.startsWith("Cliente"))

  await limpiar()
  const restos = (await pedidos.request().input("a", sql.NVarChar, `${VEND}`).query("SELECT COUNT(*) n FROM dbo.ubicaciones_recorrido WHERE usuario_codigo=@a")).recordset[0].n +
    (await ruta.request().input("a", sql.Int, VEND).query("SELECT COUNT(*) n FROM dbo.visitas_clientes WHERE vendedor_id=@a")).recordset[0].n
  ok("limpieza: no quedan datos de prueba", restos === 0, `restos=${restos}`)
  for (const s of [yo, otro, soporte]) { try { await sesiones.cerrar(pedidos, sql, s.jti, "prueba") } catch (_) {} }
  await pedidos.close()
  await ruta.close()

  for (const [nm, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + nm + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write("\n" + (todo ? "UBICACIONES OK\n" : "HAY FALLOS EN UBICACIONES\n"))
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n" + e.stack + "\n"); process.exit(1) })
