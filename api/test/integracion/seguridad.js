// Prueba de seguridad contra el backend local (puerto 3000):
//  - ninguna ruta de datos responde sin sesión
//  - el login exige dispositivo activado (REQUIRE_DEVICE_ID=true)
//  - el registro de usuarios solo lo puede usar Soporte TI
//  - con sesión válida todo sigue funcionando
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const DISPOSITIVO = "SVC-PRUEBA-SEGURIDAD"

function llamar(metodo, ruta, { body, token } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) { h["Content-Type"] = "application/json"; h["Content-Length"] = Buffer.byteLength(datos) }
    if (token) h.Authorization = `Bearer ${token}`
    const req = http.request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const trozos = []
      res.on("data", (c) => trozos.push(c))
      res.on("end", () => {
        let json = null
        try { json = JSON.parse(Buffer.concat(trozos).toString("utf8")) } catch (_) {}
        resolve({ status: res.statusCode, json })
      })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}

async function esperar() {
  for (let i = 0; i < 120; i++) {
    try { const r = await llamar("GET", "/api/test"); if (r.status === 200) return true } catch (_) {}
    await new Promise((r) => setTimeout(r, 1000))
  }
  return false
}

// Rutas de datos: todas deben responder 401 sin token (se envía cuerpo válido
// para que el rechazo sea por sesión y no por validación)
const RUTAS = [
  ["GET", "/api/clientes"],
  ["GET", "/api/clientes/C1000100148"],
  ["POST", "/api/clientes/C1000100148/actualizar-datos", { telefono: "1" }],
  ["GET", "/api/clientes/cartera/C1000100148"],
  ["GET", "/api/clientes/C1000100148/documentos"],
  ["POST", "/api/recaudos", { cliente: "C1000100148", facturas: [] }],
  ["POST", "/api/orders", { cedula: "1", nombre: "x", correo: "x@x.com", items: [] }],
  ["GET", "/api/orders/C1000100148"],
  ["GET", "/api/orders/detail/PED-1"],
  ["GET", "/api/orders?cliente=C1000100148"],
  ["GET", "/api/orders/1/detail"],
  ["GET", "/api/orders/vendedor/PRUEBA"],
  ["GET", "/api/rutas/mias"],
  ["POST", "/api/rutas/extra", { cliente: "C1000100148" }],
  ["GET", "/api/clientes/C1000100148/tareas"],
  ["GET", "/api/clientes/C1000100148/visitas-hoy"],
  ["GET", "/api/clientes/C1000100148/ultimo-pedido"],
  ["POST", "/api/clientes/C1000100148/visita", { tipo: "x" }],
  ["POST", "/api/pedidos/gestion", { cliente: "C1000100148" }],
  ["GET", "/api/encuestas"],
  ["GET", "/api/clientes/C1000100148/pedidos-total"],
  ["GET", "/api/clientes/C1000100148/visita/ultima"],
  ["GET", "/api/clientes/C1000100148/rutas"],
  ["GET", "/api/clientes/C1000100148/geocode"],
  ["POST", "/api/clientes/C1000100148/ia/sugerencias", {}],
  ["POST", "/api/clientes/C1000100148/ia/chat", { mensaje: "hola" }],
  ["POST", "/api/auth/register", { nombre: "a", apellido: "b", telefono: "1", pin: "1", documento: "1" }],
  ["POST", "/api/auth/logout"],
  ["GET", "/api/productos?cliente=C1000100148"],
  ["GET", "/api/productos/admin"],
  ["GET", "/api/usuarios"],
  ["GET", "/api/dispositivos"],
]

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no escucha en 3000\n"); process.exit(1) }

  // 1) Sin token: todo 401
  let abiertas = []
  for (const [m, ruta, body] of RUTAS) {
    const r = await llamar(m, ruta, { body })
    if (r.status !== 401) abiertas.push(`${m} ${ruta} -> ${r.status}`)
  }
  ok(`sin token: las ${RUTAS.length} rutas de datos responden 401`, abiertas.length === 0, abiertas.join("; "))
  const test = await llamar("GET", "/api/test")
  const health = await llamar("GET", "/api/health")
  ok("sin token: /api/test y /api/health siguen abiertos (monitoreo)", test.status === 200 && health.status === 200)

  // 2) Login sin dispositivo: rechazado
  const sinDisp = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "SKV1" } })
  ok("login sin ID de servicio: 400 (REQUIRE_DEVICE_ID)", sinDisp.status === 400, sinDisp.json && sinDisp.json.message)

  // 3) Login con dispositivo nuevo: queda pendiente, sin token
  const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })
  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  await pedidos.request().input("d", sql.NVarChar, DISPOSITIVO).query("DELETE FROM dbo.dispositivos WHERE id_servicio = @d")
  const pendiente = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "SKV1", id_servicio: DISPOSITIVO, plataforma: "prueba" } })
  ok("login con dispositivo nuevo: needsActivation y sin token", pendiente.status === 200 && pendiente.json.needsActivation === true && !(pendiente.json.data && pendiente.json.data.token))

  // 4) Soporte TI entra (sin dispositivo) y activa el dispositivo por la ruta
  //    real de la app; después el login del gestor funciona
  const usuarioSoporte = (process.env.SOPORTE_USUARIOS || "").split(",")[0].trim()
  const loginSoporte = await llamar("POST", "/api/auth/login", { body: { usuario: usuarioSoporte, password: "SKV1", plataforma: "prueba" } })
  const tokenSoporte = loginSoporte.json && loginSoporte.json.data && loginSoporte.json.data.token
  const rolSoporte = tokenSoporte ? (jwt.decode(tokenSoporte) || {}).rol : null
  ok(`soporte ${usuarioSoporte}: entra sin ID de servicio y con rol soporte`, loginSoporte.status === 200 && tokenSoporte && rolSoporte === "soporte", loginSoporte.json && loginSoporte.json.message)
  const lista = await llamar("GET", `/api/dispositivos?buscar=${encodeURIComponent(DISPOSITIVO)}`, { token: tokenSoporte })
  const fila = lista.json && Array.isArray(lista.json.data) ? lista.json.data.find((d) => d.id_servicio === DISPOSITIVO) : null
  ok("soporte: ve el dispositivo PENDIENTE asociado al gestor", lista.status === 200 && fila && fila.estado === "PENDIENTE" && fila.usuario_codigo === "18", fila && `${fila.estado} ${fila.usuario_nombre}`)
  const activar = await llamar("POST", `/api/dispositivos/${encodeURIComponent(DISPOSITIVO)}/estado`, { token: tokenSoporte, body: { estado: "ACTIVO" } })
  ok("soporte: activa el dispositivo por la ruta de la app", activar.status === 200 && activar.json && activar.json.estado === "ACTIVO", activar.json && (activar.json.message || activar.json.estado))
  const login = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "SKV1", id_servicio: DISPOSITIVO, plataforma: "prueba" } })
  const token = login.json && login.json.data && login.json.data.token
  ok("login con dispositivo activado: 200 con token", login.status === 200 && token, login.json && login.json.message)
  const decoded = token ? jwt.decode(token) : {}
  ok("token: lleva id_servicio y jti", decoded.id_servicio === DISPOSITIVO && decoded.jti)

  // 5) Con sesión, las rutas funcionan (lectura) y el registro sigue vedado a no-soporte
  const cartera = await llamar("GET", "/api/clientes/cartera/C1000100148", { token })
  const clientes = await llamar("GET", "/api/clientes", { token })
  const pedidosCli = await llamar("GET", "/api/orders?cliente=C1000100148", { token })
  const detalleVend = await llamar("GET", "/api/orders/vendedor/PRUEBA", { token })
  ok("con sesión: cartera, clientes y pedidos responden 200", cartera.status === 200 && clientes.status === 200 && pedidosCli.status === 200 && detalleVend.status === 200, `${cartera.status}/${clientes.status}/${pedidosCli.status}/${detalleVend.status}`)
  const reg = await llamar("POST", "/api/auth/register", { token, body: { nombre: "a", apellido: "b", telefono: "1", pin: "1", documento: "1" } })
  ok("con sesión de vendedor: /api/auth/register responde 403", reg.status === 403 && decoded.rol !== "soporte" || (decoded.rol === "soporte" && reg.status !== 401), `rol=${decoded.rol || "vendedor"} status=${reg.status}`)

  // 6) Soporte desactiva el dispositivo por la ruta de la app: la sesión cae
  const desactivar = await llamar("POST", `/api/dispositivos/${encodeURIComponent(DISPOSITIVO)}/estado`, { token: tokenSoporte, body: { estado: "DESACTIVADO" } })
  ok("soporte: desactiva el dispositivo por la ruta de la app", desactivar.status === 200 && desactivar.json && desactivar.json.estado === "DESACTIVADO", desactivar.json && (desactivar.json.message || desactivar.json.estado))
  // La ruta de soporte invalida la caché de estado (60 s); por si acaso se espera
  let caida = null
  for (let i = 0; i < 70; i++) {
    caida = await llamar("GET", "/api/clientes", { token })
    if (caida.status === 401) break
    await new Promise((r) => setTimeout(r, 1000))
  }
  ok("dispositivo desactivado: la sesión recibe 401 en menos de 70 s", caida.status === 401 && caida.json.dispositivoDesactivado === true, caida.json && caida.json.message)

  // Limpieza: el dispositivo se elimina por la ruta de Soporte (como en la app)
  // y, por si la ruta fallara, también en la BD
  const eliminar = await llamar("DELETE", `/api/dispositivos/${encodeURIComponent(DISPOSITIVO)}`, { token: tokenSoporte })
  ok("soporte: elimina el dispositivo de prueba", eliminar.status === 200, eliminar.json && eliminar.json.message)
  await pedidos.request().input("d", sql.NVarChar, DISPOSITIVO).query("DELETE FROM dbo.dispositivos WHERE id_servicio = @d")
  await pedidos.request().input("j", sql.NVarChar, decoded.jti || "").query("UPDATE dbo.sesiones SET cerrada = GETDATE(), cierre_motivo = 'prueba' WHERE jti = @j AND cerrada IS NULL")
  await llamar("POST", "/api/auth/logout", { token: tokenSoporte })
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write(todo ? "TODAS OK\n" : "HAY FALLOS\n")
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
