require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") })
const https = require("https")
const sql = require("mssql")
const { AlmacenImagenes } = require("../modules/productos/imagenes")

const SITIO = process.env.SITIO_IMAGENES || "https://oral-plus.com"
const FUENTE = `${SITIO}/compras.js`
const LISTAS = [
  "productosCepillos",
  "productosSeda",
  "productosKit",
  "productosCremas",
  "productosEnjuagues",
  "productosUniverso",
  "productosOrtodoncia",
]
const POR = "web oral-plus.com"
const soloVer = process.argv.includes("--solo-ver")

function bajar(url) {
  return new Promise((resolve, reject) => {
    https
      .get(encodeURI(url), (r) => {
        if (r.statusCode !== 200) {
          r.resume()
          return reject(new Error(`HTTP ${r.statusCode} en ${url}`))
        }
        const trozos = []
        r.on("data", (c) => trozos.push(c))
        r.on("end", () => resolve(Buffer.concat(trozos)))
      })
      .on("error", reject)
  })
}

function leerProductos(js) {
  const corte = js.indexOf("let carrito")
  const cuerpo = corte > 0 ? js.slice(0, corte) : js
  const fn = new Function(`${cuerpo}; return {${LISTAS.map((l) => `${l}:${l}`).join(",")}};`)
  const productos = []
  for (const lista of Object.values(fn())) {
    for (const p of lista) {
      if (!p.codigo1 || !p.img) continue
      productos.push({
        codigo: String(p.codigo1),
        par: p.codigo2 ? String(p.codigo2) : null,
        texturaPar: p.textura2 || null,
        img: p.img,
      })
    }
  }
  return productos
}

async function sincronizarPares(pool, productos) {
  let cambios = 0
  for (const p of productos) {
    if (!p.par) continue
    const prev = await pool.request().input("c", sql.NVarChar, p.par)
      .query("SELECT variante_de FROM dbo.productos_config WHERE item_code = @c")
    if (prev.recordset[0] && prev.recordset[0].variante_de === p.codigo) continue
    await pool
      .request()
      .input("c", sql.NVarChar, p.par)
      .input("v", sql.NVarChar, p.codigo)
      .input("t", sql.NVarChar, p.texturaPar)
      .input("por", sql.NVarChar, POR)
      .query(`
        MERGE dbo.productos_config AS t
        USING (SELECT @c AS item_code) AS s ON t.item_code = s.item_code
        WHEN MATCHED THEN UPDATE SET variante_de = @v, textura = ISNULL(@t, textura), actualizado_por = @por, actualizado_en = GETDATE()
        WHEN NOT MATCHED THEN INSERT (item_code, variante_de, textura, actualizado_por) VALUES (@c, @v, @t, @por);
      `)
    const antes = prev.recordset[0] ? prev.recordset[0].variante_de : "(sin fila)"
    process.stdout.write(`  par ${p.par}: ${antes} -> ${p.codigo}\n`)
    cambios++
  }
  return cambios
}

;(async () => {
  process.stdout.write(`Leyendo ${FUENTE}\n`)
  const productos = leerProductos((await bajar(FUENTE)).toString("utf8"))
  process.stdout.write(`${productos.length} productos, ${productos.filter((p) => p.par).length} con par medio/suave\n`)
  if (soloVer) {
    for (const p of productos) process.stdout.write(`  ${p.codigo}${p.par ? ` + ${p.par}` : ""}  ${p.img}\n`)
    return
  }

  const pool = await new sql.ConnectionPool({
    server: process.env.DB_SERVER,
    database: process.env.PEDIDOS_DB_NAME || "Pedidos",
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: parseInt(process.env.DB_PORT || "1433", 10),
    options: { encrypt: false, trustServerCertificate: true },
  }).connect()

  const cambios = await sincronizarPares(pool, productos)
  process.stdout.write(`Pares sincronizados: ${cambios}\n`)

  const imagenes = new AlmacenImagenes({ sql, getPool: () => pool })
  await imagenes.ensureTabla()
  await imagenes.cargarVersiones()

  let ok = 0
  const fallos = []
  for (const p of productos) {
    try {
      await imagenes.guardar(p.codigo, await bajar(`${SITIO}/${p.img}`), POR)
      ok++
    } catch (e) {
      fallos.push(`${p.codigo} ${p.img}: ${e.message}`)
    }
  }
  process.stdout.write(`Imagenes actualizadas: ${ok} de ${productos.length}\n`)
  for (const f of fallos) process.stdout.write(`  FALLA ${f}\n`)

  const t = await pool.request().query("SELECT COUNT(*) n, SUM(tamano) bytes FROM dbo.productos_imagenes")
  process.stdout.write(`Tabla: ${t.recordset[0].n} filas, ${Math.round(t.recordset[0].bytes / 1024)} KB\n`)
  await pool.close()
  process.exit(fallos.length === 0 ? 0 : 1)
})().catch((e) => {
  process.stdout.write(`ERROR ${e.message}\n`)
  process.exit(1)
})
