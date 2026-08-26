// Migración única del catálogo fijo de la app al catálogo dinámico:
//  - guarda las imágenes en la BD Pedidos (productos_imagenes) pasando por el
//    mismo recorte que usa Soporte TI al subirlas desde la app
//  - siembra productos_config con la categoría de la app y las variantes
//    (media/suave, niño/niña) tal como estaban en product_data_service.dart
// Uso: node scripts/migrar_catalogo.js [ruta a product_data_service.dart]
// Es idempotente: se puede ejecutar varias veces.

require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") })
const fs = require("fs")
const path = require("path")
const sql = require("mssql")
const { AlmacenImagenes } = require("../modules/productos/imagenes")
const { RepositorioProductos } = require("../modules/productos/repositorio")

const raizApp = path.join(__dirname, "..", "..")
const archivoDart = process.argv[2] || path.join(raizApp, "lib", "services", "product_data_service.dart")

// Nombres de categoría y textura tal como se ven en la app
const CATEGORIAS = { "Universo Nios": "Niños", "Universo Niños": "Niños" }
const TEXTURAS = { Nio: "Niño", Nia: "Niña" }

function leerProductosDart(texto) {
  const productos = []
  const bloques = texto.match(/^ {6}\{\n[\s\S]*?^ {6}\},?$/gm) || []
  const campo = (bloque, clave) => {
    const m = bloque.match(new RegExp(`'${clave}':\\s*'((?:[^'\\\\]|\\\\.)*)'`))
    return m ? m[1] : null
  }
  for (const b of bloques) {
    const codigo = campo(b, "codigoSap")
    if (!codigo) continue
    productos.push({
      codigo,
      titulo: campo(b, "title") || "",
      imagen: campo(b, "image") || "",
      categoria: campo(b, "category") || "",
      textura: campo(b, "textura"),
      codigoSuave: campo(b, "codigoSapSuave"),
      codigoAlternativo: campo(b, "codigoSapAlternativo"),
      texturaAlternativa: campo(b, "texturaAlternativa"),
    })
  }
  return productos
}

// La imagen original (PNG de 1000x1000) está en assets_originales/; si no,
// se usa el WebP que quedó en assets/
// Rutas que estaban mal escritas en el archivo fijo (carpeta NIÑOS sin la eñe
// y un kit ubicado en otra carpeta)
const RUTAS_CORREGIDAS = [
  [/^assets\/NIOS\/GOLNIO\.png$/, "assets/NIÑOS/GOLNIÑO.png"],
  [/^assets\/NIOS\/KITNIOS\.png$/, "assets/NIÑOS/KITNIÑOS.png"],
  [/^assets\/NIOS\/NIOS300\.png$/, "assets/NIÑOS/NIÑOS300.png"],
  [/^assets\/NIOS\//, "assets/NIÑOS/"],
  [/^assets\/KITS\/KITDACOTA\.png$/, "assets/CEPILLOS/KITDACOTA.png"],
]

function rutaImagenOriginal(imagen) {
  if (!imagen) return null
  for (const [patron, reemplazo] of RUTAS_CORREGIDAS) {
    if (patron.test(imagen)) {
      imagen = imagen.replace(patron, reemplazo)
      break
    }
  }
  const sinExt = imagen.replace(/\.(webp|png)$/i, "")
  const candidatos = [
    path.join(raizApp, sinExt.replace(/^assets\//, "assets_originales/") + ".png"),
    path.join(raizApp, sinExt + ".webp"),
    path.join(raizApp, sinExt + ".png"),
  ]
  return candidatos.find((c) => fs.existsSync(c)) || null
}

async function main() {
  const texto = fs.readFileSync(archivoDart, "utf8")
  const productos = leerProductosDart(texto)
  console.log(`Productos en el catálogo fijo: ${productos.length}`)

  const pedidosPool = await new sql.ConnectionPool({
    server: process.env.DB_SERVER,
    database: process.env.PEDIDOS_DB_NAME || "Pedidos",
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: Number.parseInt(process.env.DB_PORT || "1433", 10),
    options: { encrypt: false, trustServerCertificate: true, connectTimeout: 15000, requestTimeout: 60000 },
  }).connect()

  const imagenes = new AlmacenImagenes({ sql, getPool: () => pedidosPool })
  const repositorio = new RepositorioProductos({
    sql,
    getSapPool: async () => null,
    getPedidosPool: () => pedidosPool,
    imagenes,
    env: process.env,
    log: console,
  })
  await repositorio.ensureTabla()
  await imagenes.ensureTabla()
  await imagenes.cargarVersiones()

  let guardadas = 0
  const sinImagen = []
  let filas = 0
  for (const p of productos) {
    const origen = rutaImagenOriginal(p.imagen)
    if (origen) {
      await imagenes.guardar(p.codigo, fs.readFileSync(origen), "migracion")
      guardadas++
    } else {
      sinImagen.push(`${p.codigo} (${p.imagen || "sin ruta"})`)
    }

    const categoria = CATEGORIAS[p.categoria] || p.categoria || null
    const tieneVariante = Boolean(p.codigoSuave || p.codigoAlternativo)
    const texturaPadre = TEXTURAS[p.textura] || p.textura || (tieneVariante ? "Media" : null)

    await repositorio.guardarConfig(
      p.codigo,
      { categoriaApp: categoria, textura: tieneVariante ? texturaPadre : null },
      "migracion",
    )
    filas++

    // Variantes: cuelgan del principal y no salen como tarjeta propia
    const variantes = []
    if (p.codigoSuave) variantes.push({ codigo: p.codigoSuave, textura: "Suave" })
    if (p.codigoAlternativo) variantes.push({ codigo: p.codigoAlternativo, textura: TEXTURAS[p.texturaAlternativa] || p.texturaAlternativa || "Alternativa" })
    for (const v of variantes) {
      await repositorio.guardarConfig(v.codigo, { categoriaApp: categoria, varianteDe: p.codigo, textura: v.textura }, "migracion")
      filas++
    }
  }

  const total = await pedidosPool.request().query("SELECT COUNT(*) AS n, SUM(tamano) AS bytes FROM dbo.productos_imagenes")
  console.log(`Imágenes guardadas en la BD: ${guardadas} (tabla productos_imagenes: ${total.recordset[0].n} filas, ${Math.round(total.recordset[0].bytes / 1024)} KB)`)
  if (sinImagen.length) console.log(`Sin imagen: ${sinImagen.length}\n  ${sinImagen.join("\n  ")}`)
  console.log(`Filas de configuración escritas: ${filas}`)
  await pedidosPool.close()
}

main().catch((e) => {
  console.error("Error en la migración:", e.message)
  process.exit(1)
})
