// Rutas del catálogo de productos.
//   GET  /api/productos?cliente=          catálogo para el vendedor (precio de su lista)
//   GET  /api/productos/imagen/:codigo    imagen WebP (caché larga, URL versionada)
//   GET  /api/productos/admin             soporte: todos los artículos con su configuración
//   PUT  /api/productos/:codigo/imagen    soporte: sube o reemplaza la imagen (multipart "imagen")
//   DELETE /api/productos/:codigo/imagen  soporte: quita la imagen
//   PUT  /api/productos/:codigo/config    soporte: categoría, visible, orden, variante, textura, descripción
//   POST /api/productos/refrescar         soporte: vuelve a leer SAP ahora

const multer = require("multer")
const { limpiar } = require("./imagenes")

function registrarRutas(app, { repositorio, imagenes, requireAuth, requireSoporte }) {
  const subida = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 12 * 1024 * 1024, files: 1 },
  })

  app.get("/api/productos", requireAuth, async (req, res) => {
    try {
      const cliente = (req.query.cliente || "").toString().trim()
      if (!cliente) {
        return res.status(400).json({ success: false, sinCliente: true, message: "Selecciona un cliente para ver el catálogo con sus precios", productos: [] })
      }
      const lista = await repositorio.listaPreciosDe(cliente)
      if (lista == null) {
        return res.status(404).json({ success: false, message: `El cliente ${cliente} no existe en SAP`, productos: [] })
      }
      const catalogo = await repositorio.paraVendedor(lista)
      const etag = `"${catalogo.version}-${lista}"`
      res.set("ETag", etag)
      res.set("Cache-Control", "private, no-cache")
      if (req.headers["if-none-match"] === etag) return res.status(304).end()
      res.json({ success: true, ...catalogo })
    } catch (e) {
      console.error("Error entregando catálogo:", e.message)
      res.status(503).json({ success: false, message: "Catálogo no disponible por ahora", productos: [] })
    }
  })

  // Sin auth: la app la pide por URL y esa URL ya lleva la versión.
  app.get("/api/productos/imagen/:codigo", async (req, res) => {
    try {
      const codigo = limpiar(req.params.codigo)
      const imagen = codigo ? await imagenes.obtener(codigo) : null
      if (!imagen) {
        return res.status(404).json({ success: false, message: "Sin imagen" })
      }
      const etag = `"${codigo}-${imagen.version}"`
      if (req.headers["if-none-match"] === etag) return res.status(304).end()
      res.set("ETag", etag)
      res.set("Cache-Control", "public, max-age=31536000, immutable")
      res.type(imagen.mime)
      res.send(imagen.contenido)
    } catch (e) {
      console.error("Error entregando imagen de producto:", e.message)
      res.status(500).json({ success: false, message: "No se pudo leer la imagen" })
    }
  })

  app.get("/api/productos/admin", requireSoporte, async (req, res) => {
    try {
      const datos = await repositorio.paraSoporte()
      res.json({ success: true, ...datos })
    } catch (e) {
      console.error("Error listando productos (soporte):", e.message)
      res.status(503).json({ success: false, message: e.message, productos: [] })
    }
  })

  app.put("/api/productos/:codigo/imagen", requireSoporte, subida.single("imagen"), async (req, res) => {
    try {
      const codigo = limpiar(req.params.codigo)
      if (!codigo) return res.status(400).json({ success: false, message: "Código inválido" })
      if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
        return res.status(400).json({ success: false, message: "Adjunta la imagen en el campo 'imagen'" })
      }
      await imagenes.guardar(codigo, req.file.buffer, req.user && (req.user.nombre || req.user.usuario))
      res.json({ success: true, codigo, imagenUrl: repositorio.urlImagen(codigo) })
    } catch (e) {
      console.error("Error guardando imagen de producto:", e.message)
      res.status(500).json({ success: false, message: "No se pudo guardar la imagen" })
    }
  })

  app.delete("/api/productos/:codigo/imagen", requireSoporte, async (req, res) => {
    try {
      const codigo = limpiar(req.params.codigo)
      const habia = await imagenes.eliminar(codigo)
      res.json({ success: true, codigo, eliminada: habia })
    } catch (e) {
      console.error("Error eliminando imagen de producto:", e.message)
      res.status(500).json({ success: false, message: "No se pudo eliminar la imagen" })
    }
  })

  app.put("/api/productos/:codigo/config", requireSoporte, async (req, res) => {
    try {
      const codigo = limpiar(req.params.codigo)
      const b = req.body || {}
      const cambios = {}
      if ("categoriaApp" in b) cambios.categoriaApp = b.categoriaApp == null ? null : String(b.categoriaApp).trim().slice(0, 40)
      if ("visible" in b) cambios.visible = b.visible !== false
      if ("orden" in b) cambios.orden = b.orden == null || b.orden === "" ? null : Number.parseInt(b.orden, 10)
      if ("varianteDe" in b) cambios.varianteDe = b.varianteDe ? limpiar(b.varianteDe) : null
      if ("textura" in b) cambios.textura = b.textura == null ? null : String(b.textura).trim().slice(0, 20)
      if ("descripcion" in b) cambios.descripcion = b.descripcion == null ? null : String(b.descripcion).trim()
      if (cambios.varianteDe && cambios.varianteDe === codigo) {
        return res.status(400).json({ success: false, message: "Un producto no puede ser variante de sí mismo" })
      }
      await repositorio.guardarConfig(codigo, cambios, req.user && (req.user.nombre || req.user.usuario))
      res.json({ success: true, codigo })
    } catch (e) {
      console.error("Error guardando configuración de producto:", e.message)
      res.status(500).json({ success: false, message: "No se pudo guardar la configuración" })
    }
  })

  app.post("/api/productos/refrescar", requireSoporte, async (req, res) => {
    try {
      const catalogo = await repositorio.obtenerCatalogo({ forzar: true })
      res.json({ success: true, articulos: catalogo.items.size, fuente: catalogo.fuente })
    } catch (e) {
      res.status(503).json({ success: false, message: e.message })
    }
  })
}

module.exports = { registrarRutas }
