// Prueba de integración contra el backend (API_URL, por defecto http://127.0.0.1:3000) con BD reales.
// Sesiones de 12 h, cierre seguro, credenciales incorrectas y catálogo por lista del cliente.
const http = require("http")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const jwt = require(path.join(process.cwd(), "node_modules", "jsonwebtoken"))
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"

function llamar(metodo, ruta, { body, token } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? JSON.stringify(body) : null
    const h = { Accept: "application/json" }
    if (datos) { h["Content-Type"] = "application/json"; h["Content-Length"] = Buffer.byteLength(datos) }
    if (token) h.Authorization = `Bearer ${token}`
    const req = (BASE.startsWith("https") ? require("https") : http).request(BASE + ruta, { method: metodo, headers: h }, (res) => {
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

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })
  const sap = await new sql.ConnectionPool(cfgDb(process.env.SAP_DB_NAME || "RBOSKY3")).connect()
  const cli = async (lista) => (await sap.request().input("l", sql.Int, lista).query("SELECT TOP 1 CardCode FROM OCRD WHERE CardType='C' AND ListNum=@l AND frozenFor='N' AND validFor='Y' AND SlpCode>0 ORDER BY CardCode")).recordset[0].CardCode
  const cliente6 = await cli(6)
  const cliente43 = await cli(43)
  // Artículo con precio en la lista 6 pero sin stock en bodega 50
  const sinStock = await sap.request().query(`
    SELECT TOP 1 T0.ItemCode FROM OITM T0
    JOIN ITM1 p ON p.ItemCode=T0.ItemCode AND p.PriceList=6 AND p.Price>0
    LEFT JOIN OITW w ON w.ItemCode=T0.ItemCode AND w.WhsCode='50'
    WHERE T0.SellItem='Y' AND T0.frozenFor='N' AND T0.ItmsGrpCod IN (157,130,132,133,137,139,140,141,142) AND ISNULL(w.OnHand,0) <= 0
    ORDER BY T0.ItemCode`)
  const codigoSinStock = sinStock.recordset[0] ? sinStock.recordset[0].ItemCode : null
  await sap.close()

  const pedidosDisp = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const DISP = "SVC-PRUEBA-SESION"
  await pedidosDisp.request().input("d", sql.NVarChar, DISP).query("DELETE FROM dbo.dispositivos WHERE id_servicio=@d; INSERT INTO dbo.dispositivos (id_servicio, estado, activado_por, fecha_activacion) VALUES (@d, 'ACTIVO', 'prueba-sesion', GETDATE())")
  await pedidosDisp.close()

  // 1) Credenciales incorrectas
  const malo = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "clave-que-no-existe", id_servicio: DISP } })
  ok("login incorrecto: 401 con mensaje de credenciales", malo.status === 401 && /credenciales incorrectas/i.test(malo.json && malo.json.message), malo.json && malo.json.message)

  // 2) Login correcto: token con jti y vencimiento a 12 h
  const inicio = Date.now()
  const login = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "SKV1", plataforma: "prueba", id_servicio: DISP } })
  const data = (login.json && login.json.data) || {}
  const token = data.token
  ok("login correcto: 200 con token", login.status === 200 && token, login.json && login.json.message)
  const decoded = token ? jwt.decode(token) : {}
  ok("token: lleva jti (sesión registrada)", decoded && decoded.jti)
  const dur = decoded && decoded.exp - decoded.iat
  ok("token: vence en 12 h exactas aunque .env diga 24h", dur === 12 * 3600, `${dur} s`)
  const expira = Date.parse(data.expira)
  ok("respuesta: expira coincide con 12 h", Math.abs(expira - (inicio + 12 * 3600 * 1000)) < 60 * 1000 && data.duracionSeg === 43200, data.expira)

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const fila = await pedidos.request().input("j", sql.NVarChar, decoded.jti || "").query("SELECT usuario_codigo, tipo, plataforma, cerrada, DATEDIFF(minute, emitida, expira) AS minutos FROM dbo.sesiones WHERE jti=@j")
  ok("BD: fila en dbo.sesiones con 720 minutos y sin cerrar", fila.recordset[0] && fila.recordset[0].minutos === 720 && fila.recordset[0].cerrada === null && fila.recordset[0].usuario_codigo === "18", JSON.stringify(fila.recordset[0]))

  // 3) Catálogo: exige cliente y usa solo su lista
  const sinCliente = await llamar("GET", "/api/productos", { token })
  ok("catálogo sin cliente: 400", sinCliente.status === 400 && sinCliente.json.sinCliente === true, sinCliente.json && sinCliente.json.message)
  const noExiste = await llamar("GET", "/api/productos?cliente=CNOEXISTE999", { token })
  ok("catálogo cliente inexistente: 404", noExiste.status === 404, noExiste.json && noExiste.json.message)

  let c6
  for (let i = 0; i < 40; i++) {
    c6 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente6)}`, { token })
    if (c6.status === 200) break
    await new Promise((r) => setTimeout(r, 1500))
  }
  const p6 = (c6.json && c6.json.productos) || []
  const item6 = p6.find((p) => p.codigo === "50360168")
  ok("cliente lista 6: 50360168 a 3.883 y habilitado", c6.status === 200 && c6.json.listaPrecios === 6 && item6 && item6.precio === 3883 && item6.habilitado === true && item6.disponible === true, `cliente ${cliente6}`)
  const itemSinStock = codigoSinStock && p6.find((p) => p.codigo === codigoSinStock)
  ok("cliente lista 6: artículo sin stock sigue disponible (solo informa)", itemSinStock && itemSinStock.stock <= 0 && itemSinStock.disponible === true && /sin stock/i.test(itemSinStock.mensajeEstado), codigoSinStock)
  ok("cliente lista 6: todo lo que tiene precio está habilitado y viceversa", p6.every((p) => (p.precio > 0) === p.habilitado && p.disponible === p.habilitado))

  const c43 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente43)}`, { token })
  const p43 = (c43.json && c43.json.productos) || []
  const item43 = p43.find((p) => p.codigo === "50360168")
  ok("cliente lista 43: 50360168 en 0, visible pero no disponible", c43.status === 200 && c43.json.listaPrecios === 43 && item43 && item43.precio === 0 && item43.habilitado === false && item43.disponible === false && /no disponible/i.test(item43.mensajeEstado), `cliente ${cliente43}`)
  const calipso = p43.find((p) => p.codigo === "50360072")
  ok("cliente lista 43: 50360072 ya no muestra el precio viejo de la lista 1 (7.497)", calipso && calipso.precio === 0 && calipso.disponible === false, calipso && `precio ${calipso.precio}`)
  ok("cliente lista 43: ninguna variante usa respaldo (precio 0 => no disponible)", p43.every((p) => p.variantes.every((v) => (v.precio > 0) === v.disponible)))

  // 4) Cierre de sesión seguro
  const antes = await llamar("GET", "/api/clientes", { token })
  ok("antes del logout: /api/clientes responde 200", antes.status === 200)
  const logout = await llamar("POST", "/api/auth/logout", { token })
  ok("logout: 200", logout.status === 200 && logout.json.success === true)
  const despues = await llamar("GET", "/api/clientes", { token })
  ok("después del logout: el mismo token recibe 401 sesionCerrada", despues.status === 401 && despues.json.sesionCerrada === true, despues.json && despues.json.message)
  const cat = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente6)}`, { token })
  ok("después del logout: el catálogo también rechaza el token", cat.status === 401)
  const fila2 = await pedidos.request().input("j", sql.NVarChar, decoded.jti || "").query("SELECT cerrada, cierre_motivo FROM dbo.sesiones WHERE jti=@j")
  ok("BD: la sesión quedó cerrada con motivo logout", fila2.recordset[0] && fila2.recordset[0].cerrada && fila2.recordset[0].cierre_motivo === "logout")
  const logout2 = await llamar("POST", "/api/auth/logout", { token })
  ok("logout repetido: 401 (ya no hay sesión)", logout2.status === 401)
  await pedidos.close()

  // 5) Tokens que no deben servir
  const viejo = jwt.sign({ userId: 18, nombre: "VIEJO", tipo: "vendedor" }, process.env.JWT_SECRET, { expiresIn: "1h" })
  const rViejo = await llamar("GET", "/api/clientes", { token: viejo })
  ok("token sin jti (servidor anterior): 401", rViejo.status === 401)
  const vencido = jwt.sign({ userId: 18, nombre: "VENCIDO", tipo: "vendedor", jti: "x" }, process.env.JWT_SECRET, { expiresIn: -10 })
  const rVencido = await llamar("GET", "/api/clientes", { token: vencido })
  ok("token vencido: 401", rVencido.status === 401)
  const inventado = jwt.sign({ userId: 18, nombre: "INVENTADO", tipo: "vendedor", jti: "no-registrado" }, process.env.JWT_SECRET, { expiresIn: "1h" })
  const rInventado = await llamar("GET", "/api/clientes", { token: inventado })
  ok("token con jti no registrado: 401", rInventado.status === 401)

  // 6) Un segundo login sigue funcionando (la sesión cerrada no afecta al usuario)
  const login2 = await llamar("POST", "/api/auth/login", { body: { usuario: "SKV18", password: "SKV1", id_servicio: DISP } })
  const token2 = login2.json && login2.json.data && login2.json.data.token
  const r2 = await llamar("GET", "/api/clientes", { token: token2 })
  ok("nuevo login tras logout: sesión nueva válida", login2.status === 200 && r2.status === 200)
  await llamar("POST", "/api/auth/logout", { token: token2 })

  const limpieza = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  await limpieza.request().input("d", sql.NVarChar, DISP).query("DELETE FROM dbo.dispositivos WHERE id_servicio=@d")
  await limpieza.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write(todo ? "TODAS OK\n" : "HAY FALLOS\n")
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
