const http = require("http")
const fs = require("fs")
const path = require("path")
require(path.join(process.cwd(), "node_modules", "dotenv")).config({ path: path.join(process.cwd(), ".env") })
const sql = require(path.join(process.cwd(), "node_modules", "mssql"))

const BASE = process.env.API_URL || "http://127.0.0.1:3000"
const USUARIO_PRUEBA = process.env.PRUEBAS_USUARIO || "SKV18"
const CLAVE_PRUEBA = process.env.PRUEBAS_CLAVE || "SKV1"
const RAIZ_APP = path.join(process.cwd(), "..")

function llamar(metodo, ruta, { body, token, headers = {}, raw = false } = {}) {
  return new Promise((resolve, reject) => {
    const datos = body ? (Buffer.isBuffer(body) ? body : JSON.stringify(body)) : null
    const h = { ...headers }
    if (datos && !Buffer.isBuffer(body)) h["Content-Type"] = "application/json"
    if (datos) h["Content-Length"] = datos.length
    if (token) h.Authorization = `Bearer ${token}`
    const req = (BASE.startsWith("https") ? require("https") : http).request(BASE + ruta, { method: metodo, headers: h }, (res) => {
      const trozos = []
      res.on("data", (c) => trozos.push(c))
      res.on("end", () => {
        const buf = Buffer.concat(trozos)
        if (raw) return resolve({ status: res.statusCode, headers: res.headers, buf })
        let json = null
        try { json = JSON.parse(buf.toString("utf8")) } catch (_) {}
        resolve({ status: res.statusCode, headers: res.headers, json })
      })
    })
    req.on("error", reject)
    if (datos) req.write(datos)
    req.end()
  })
}

function multipart(campo, nombre, contenido, mime) {
  const limite = "----prueba" + Date.now()
  const cabecera = Buffer.from(`--${limite}\r\nContent-Disposition: form-data; name="${campo}"; filename="${nombre}"\r\nContent-Type: ${mime}\r\n\r\n`)
  const pie = Buffer.from(`\r\n--${limite}--\r\n`)
  return { body: Buffer.concat([cabecera, contenido, pie]), headers: { "Content-Type": `multipart/form-data; boundary=${limite}` } }
}

async function esperar() {
  for (let i = 0; i < 120; i++) {
    try { await llamar("GET", "/api/test"); return true } catch (_) { await new Promise((r) => setTimeout(r, 500)) }
  }
  return false
}

;(async () => {
  const out = []
  const ok = (n, c, extra) => out.push([n + (extra ? `  [${extra}]` : ""), !!c])
  if (!(await esperar())) { process.stdout.write("FALLA el servidor no responde en " + BASE + "\n"); process.exit(1) }

  const cfgDb = (db) => ({ server: process.env.DB_SERVER, database: db, user: process.env.DB_USER, password: process.env.DB_PASSWORD, port: 1433, options: { encrypt: false, trustServerCertificate: true } })
  const sap = await new sql.ConnectionPool(cfgDb(process.env.SAP_DB_NAME || "RBOSKY3")).connect()
  const c = await sap.request().query("SELECT TOP 1 CardCode, ListNum FROM OCRD WHERE CardType='C' AND ListNum = 6 AND frozenFor='N' AND validFor='Y' AND SlpCode > 0 ORDER BY CardCode")
  await sap.close()
  const cliente = c.recordset[0] ? c.recordset[0].CardCode : ""
  const listaEsperada = c.recordset[0] ? c.recordset[0].ListNum : 1

  const DISP = "SVC-PRUEBA-CATALOGO"
  const pedidosDisp = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  await pedidosDisp.request().input("d", sql.NVarChar, DISP).query("DELETE FROM dbo.dispositivos WHERE id_servicio=@d; INSERT INTO dbo.dispositivos (id_servicio, estado, activado_por, fecha_activacion) VALUES (@d, 'ACTIVO', 'prueba-catalogo', GETDATE())")
  await pedidosDisp.close()
  const usuarioSoporte = (process.env.SOPORTE_USUARIOS || "").split(",")[0].trim()
  const entrar = async (usuario, extra) => {
    const r = await llamar("POST", "/api/auth/login", { body: { usuario, password: CLAVE_PRUEBA, plataforma: "prueba", ...extra } })
    return r.json && r.json.data && r.json.data.token
  }
  const vendedor = await entrar(USUARIO_PRUEBA, { id_servicio: DISP })
  const soporte = await entrar(usuarioSoporte, {})
  ok("sesiones de prueba: vendedor y soporte entran", vendedor && soporte, `soporte ${usuarioSoporte}`)

  let r1
  for (let i = 0; i < 40; i++) {
    r1 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente)}`, { token: vendedor })
    if (r1.status === 200) break
    await new Promise((r) => setTimeout(r, 1500))
  }
  let cat = r1.json || {}
  for (let i = 0; i < 2 && cat.fuente !== "service layer"; i++) {
    await llamar("POST", "/api/productos/refrescar", { token: soporte })
    r1 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente)}`, { token: vendedor })
    cat = r1.json || {}
  }
  const productos = cat.productos || []
  ok("catálogo: 200 y success", r1.status === 200 && cat.success === true)
  ok("catálogo: viene del Service Layer (usuario manager)", cat.fuente === "service layer", `fuente ${cat.fuente}`)
  ok("catálogo: al menos 100 productos con precio para la lista del cliente", productos.length >= 100, `${productos.length} productos`)
  ok("catálogo: lista de precios del cliente", cat.listaPrecios === listaEsperada, `cliente ${cliente} lista ${cat.listaPrecios}`)
  const cats = (cat.categorias || []).map((x) => x.nombre)
  ok("catálogo: categorías con Cepillos, Niños y Ortodoncia", ["Cepillos", "Niños", "Ortodoncia"].every((x) => cats.includes(x)), cats.join(", "))
  ok("catálogo: todos los productos entregados tienen precio en la lista del cliente y están disponibles", productos.length >= 100 && productos.every((p) => p.precio > 0 && p.disponible === true), productos.length + " productos con precio")
  const conImagen = productos.filter((p) => p.imagenUrl).length
  ok("catálogo: al menos 60 productos con imagen migrada (desde la BD)", conImagen >= 60, `${conImagen} con imagen`)
  ok("catálogo: ortodoncia presente", productos.some((p) => p.codigo === "50360269" && p.categoria === "Ortodoncia"))
  const original = productos.find((p) => p.codigo === "50360251")
  ok("catálogo: Cepillo Original con variante Suave", original && original.variantes.some((v) => v.codigo === "50360256"))
  ok("catálogo: los artículos sin stock se entregan (disponibles, con aviso de sin stock)", productos.every((p) => typeof p.disponible === "boolean") && productos.some((p) => p.stock <= 0 && p.disponible === true && /sin stock/i.test(p.mensajeEstado)))
  const r304 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente)}`, { token: vendedor, headers: { "If-None-Match": r1.headers.etag } })
  ok("catálogo: If-None-Match responde 304", r304.status === 304)

  const pedidos = await new sql.ConnectionPool(cfgDb(process.env.PEDIDOS_DB_NAME || "Pedidos")).connect()
  const t = await pedidos.request().query("SELECT COUNT(*) AS n, MIN(ancho) AS minAncho, MAX(ancho) AS maxAncho, MAX(tamano) AS maxTam FROM dbo.productos_imagenes")
  ok("BD: tabla productos_imagenes con las 76 fotos migradas", t.recordset[0].n >= 76, `${t.recordset[0].n} filas, ancho ${t.recordset[0].minAncho}-${t.recordset[0].maxAncho} px, máx ${Math.round(t.recordset[0].maxTam / 1024)} KB`)
  ok("BD: ninguna foto supera 400 px", t.recordset[0].maxAncho <= 400)
  const img1 = await llamar("GET", original.imagenUrl, { raw: true })
  ok("imagen migrada: 200 image/webp desde la BD con caché larga", img1.status === 200 && /image\/webp/.test(img1.headers["content-type"]) && /immutable/.test(img1.headers["cache-control"]), `${img1.buf.length} bytes`)
  const img304 = await llamar("GET", original.imagenUrl, { raw: true, headers: { "If-None-Match": img1.headers.etag } })
  ok("imagen: If-None-Match responde 304", img304.status === 304)

  const codigoPrueba = "50360269"
  const rutaPng = path.join(RAIZ_APP, "assets_originales", "CEPILLOS", "RISTRACEPILLO.png")
  const hayOriginal = fs.existsSync(rutaPng)
  const png = hayOriginal
    ? fs.readFileSync(rutaPng)
    : await require(path.join(process.cwd(), "node_modules", "sharp"))({ create: { width: 600, height: 600, channels: 3, background: { r: 200, g: 200, b: 200 } } }).png().toBuffer()
  const mp = multipart("imagen", "foto.png", png, "image/png")
  const up = await llamar("PUT", `/api/productos/${codigoPrueba}/imagen`, { token: soporte, body: mp.body, headers: mp.headers })
  ok("soporte: subida de foto 200", up.status === 200 && up.json.imagenUrl, up.json && up.json.imagenUrl)
  const img2 = await llamar("GET", up.json.imagenUrl, { raw: true })
  if (hayOriginal) ok("paridad: la foto subida por Soporte es byte a byte igual a la migrada", img2.status === 200 && img1.buf.equals(img2.buf), `${img1.buf.length} vs ${img2.buf.length} bytes`)
  else ok("subida: la foto de prueba se sirve como webp (paridad omitida, sin PNG original)", img2.status === 200 && String(img2.headers["content-type"]).includes("image/webp"))
  const fila = await pedidos.request().input("c", sql.NVarChar, codigoPrueba).query("SELECT tamano, ancho, alto, mime, actualizado_por FROM dbo.productos_imagenes WHERE item_code = @c")
  ok("BD: la subida quedó con mime webp, 400 px y usuario", fila.recordset[0] && fila.recordset[0].mime === "image/webp" && fila.recordset[0].ancho === 400 && fila.recordset[0].actualizado_por && fila.recordset[0].actualizado_por !== "migracion", JSON.stringify(fila.recordset[0]))
  const r2 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente)}`, { token: vendedor })
  const cera = (r2.json.productos || []).find((p) => p.codigo === codigoPrueba)
  ok("catálogo: refleja la foto nueva y cambió el ETag", cera && cera.imagenUrl && r2.headers.etag !== r1.headers.etag)

  const del = await llamar("DELETE", `/api/productos/${codigoPrueba}/imagen`, { token: soporte })
  const quedo = await pedidos.request().input("c", sql.NVarChar, codigoPrueba).query("SELECT COUNT(*) AS n FROM dbo.productos_imagenes WHERE item_code = @c")
  const r3 = await llamar("GET", `/api/productos?cliente=${encodeURIComponent(cliente)}`, { token: vendedor })
  const cera3 = (r3.json.productos || []).find((p) => p.codigo === codigoPrueba)
  ok("limpieza: foto de prueba eliminada de la BD y del catálogo", del.status === 200 && quedo.recordset[0].n === 0 && cera3 && !cera3.imagenUrl)
  ok("no existe carpeta api/data (todo en BD)", !fs.existsSync(path.join(process.cwd(), "data")))
  const adm = await llamar("GET", "/api/productos/admin", { token: soporte })
  ok("admin: lista completa", adm.status === 200 && adm.json.productos.length >= 200, `${adm.json && adm.json.productos.length} artículos`)

  await llamar("POST", "/api/auth/logout", { token: vendedor })
  await llamar("POST", "/api/auth/logout", { token: soporte })
  await pedidos.request().input("d", sql.NVarChar, DISP).query("DELETE FROM dbo.dispositivos WHERE id_servicio=@d")
  await pedidos.close()

  for (const [n, b] of out) process.stdout.write((b ? "OK    " : "FALLA ") + n + "\n")
  const todo = out.every(([, b]) => b)
  process.stdout.write(todo ? "TODAS OK\n" : "HAY FALLOS\n")
  process.exit(todo ? 0 : 1)
})().catch((e) => { process.stdout.write("ERROR " + e.message + "\n"); process.exit(1) })
