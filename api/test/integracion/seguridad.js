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

  // 4) Soporte activa el dispositivo (simulado en BD) y el login funciona
  await pedidos.request().input("d", sql.NVarChar, DISPOSITIVO).query("UPDATE dbo.dispositivos SET estado = 'ACTIVO', activado_por = 'prueba-seguridad', fecha_activacion = GETDATE() WHERE id_servicio = @d")
  // Esperar a que venza la caché de estado del dispositivo (60 s) no hace
  // falta: el estado se consulta al iniciar sesión sin caché
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

  // 6) Soporte desactiva el dispositivo: la sesión cae
  await pedidos.request().input("d", sql.NVarChar, DISPOSITIVO).query("UPDATE dbo.dispositivos SET estado = 'DESACTIVADO' WHERE id_servicio = @d")
  // El estado del dispositivo se cachea 60 s en el backend; la ruta de soporte lo invalida, aquí se espera
  let caida = null
  for (let i = 0; i < 70; i++) {
    caida = await llamar("GET", "/api/clientes", { token })
    if (caida.status === 401) break
    await new Promise((r) => setTimeout(r, 1000))
  }
  ok("dispositivo desactivado: la sesión recibe 401 en menos de 70 s", caida.status === 401 && caida.json.dispositivoDesactivado === true, caida.json && caida.json.message)

  // Limpieza
  await pedidos.request().input("d", sql.NVarChar, DISPOSITIVO).query("DELETE FROM dbo.dispositivos WHERE id_servicio = @d")
  await pedidos.request().input("j", sql.NVarChar, decoded.jti || "").query("UPDATE dbo.sesiones SET cerrada = GETDATE(), cierre_motivo = 'prueba' WHERE jti = @j AND cerrada IS NULL")
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write(todo ? "TODAS OK\n" : "HAY FALLOS\n")
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
