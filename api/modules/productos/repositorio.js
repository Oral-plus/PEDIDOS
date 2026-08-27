// Catálogo de productos: SAP (Service Layer o SQL) + configuración de
// presentación (BD Pedidos, tabla productos_config) + imágenes (BD Pedidos,
// tabla productos_imagenes).
// El catálogo vive en memoria y se refresca cada pocos minutos en segundo
// plano; si SAP falla se sigue sirviendo el último catálogo bueno.

const crypto = require("crypto")
const { ServiceLayer } = require("./serviceLayer")
const fuente = require("./fuenteSap")

// Grupo SAP (OITB.ItmsGrpNam) -> categoría que ve el vendedor
const CATEGORIA_POR_GRUPO = {
  "PT-CEPILLOS NACIONAL": "Cepillos",
  "PT-IMP CEPILLOS": "Cepillos",
  "PT-CREMA DENTAL": "Cremas",
  "PT-ENJUAGUE BUCAL": "Enjuagues",
  "PT-SEDAS": "Sedas",
  "PT KIT": "Kits",
  "PT-ORTODONCIA": "Ortodoncia",
  "PT-OTROS": "Otros",
  "PT-REFRESCANTE": "Otros",
}

// Orden de las pestañas; las categorías no listadas van después, alfabéticas
const ORDEN_CATEGORIAS = ["Cepillos", "Cremas", "Enjuagues", "Sedas", "Niños", "Kits", "Ortodoncia", "Otros"]

class RepositorioProductos {
  constructor({ sql, getSapPool, getPedidosPool, imagenes, env, log }) {
    this.sql = sql
    this.getSapPool = getSapPool
    this.getPedidosPool = getPedidosPool
    this.imagenes = imagenes
    this.log = log || console
    this.bodega = env.SAP_BODEGA || "50"
    this.grupos = fuente.gruposDesdeEnv(env.SAP_GRUPOS_PT)
    this.ttlMs = (Number.parseInt(env.CATALOGO_TTL_MIN, 10) || 5) * 60 * 1000
    this.modoFuente = (env.CATALOGO_FUENTE || "auto").toLowerCase() // auto | sl | sql
    this.sl = new ServiceLayer({
      url: env.SL_URL,
      companyDb: env.SL_COMPANY_DB || env.SAP_DB_NAME || "RBOSKY3",
      user: env.SL_USER,
      password: env.SL_PASSWORD,
      tlsInsecure: (env.SL_TLS_INSECURE || "true").toLowerCase() === "true",
    })

    this.catalogo = null // { items: Map codigo -> item SAP, actualizado, fuente }
    this.config = new Map() // item_code -> fila productos_config
    this.refrescando = null
    this.ultimoError = null
    this.listasCliente = new Map() // cardCode -> { lista, vence }
  }

  // Tabla de presentación (categoría, visibilidad, variantes, imagen, descripción)
  async ensureTabla() {
    const pool = this.getPedidosPool()
    await pool.request().query(`
      IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'productos_config')
      CREATE TABLE dbo.productos_config (
        item_code        NVARCHAR(50)  NOT NULL PRIMARY KEY,
        categoria_app    NVARCHAR(40)  NULL,
        visible          BIT           NOT NULL CONSTRAINT DF_prodcfg_visible DEFAULT (1),
        orden            INT           NULL,
        variante_de      NVARCHAR(50)  NULL,
        textura          NVARCHAR(20)  NULL,
        descripcion      NVARCHAR(MAX) NULL,
        actualizado_por  NVARCHAR(100) NULL,
        actualizado_en   DATETIME      NOT NULL CONSTRAINT DF_prodcfg_fecha DEFAULT (GETDATE())
      );
    `)
  }

  async cargarConfig() {
    const pool = this.getPedidosPool()
    const r = await pool.request().query("SELECT * FROM dbo.productos_config")
    const mapa = new Map()
    for (const fila of r.recordset) mapa.set(fila.item_code, fila)
    this.config = mapa
  }

  // Devuelve el catálogo en memoria. Si está vencido lanza un refresco en
  // segundo plano y responde con el anterior; la primera vez espera.
  async obtenerCatalogo({ forzar = false } = {}) {
    const vencido = !this.catalogo || Date.now() - this.catalogo.actualizado > this.ttlMs
    if (forzar || !this.catalogo) {
      await this.refrescar()
    } else if (vencido) {
      this.refrescar().catch(() => {})
    }
    if (!this.catalogo) throw new Error(this.ultimoError || "Catálogo no disponible")
    return this.catalogo
  }

  refrescar() {
    if (this.refrescando) return this.refrescando
    this.refrescando = this._leerDeSap()
      .then(async ({ items, fuenteUsada }) => {
        await this.cargarConfig()
        this.catalogo = {
          items: new Map(items.map((i) => [i.codigo, i])),
          actualizado: Date.now(),
          fuente: fuenteUsada,
        }
        this.ultimoError = null
        this.log.info(`Catálogo SAP: ${items.length} artículos (${fuenteUsada}, bodega ${this.bodega})`)
      })
      .catch((e) => {
        this.ultimoError = e.message
        this.log.error("No se pudo refrescar el catálogo SAP:", e.message)
        if (!this.catalogo) throw e
      })
      .finally(() => {
        this.refrescando = null
      })
    return this.refrescando
  }

  async _leerDeSap() {
    const opciones = { bodega: this.bodega, grupos: this.grupos }
    const usarSl = this.modoFuente !== "sql" && this.sl.configurado
    if (usarSl) {
      try {
        const items = await fuente.leerPorServiceLayer(this.sl, opciones)
        return { items, fuenteUsada: "service layer" }
      } catch (e) {
        if (this.modoFuente === "sl") throw e
        this.log.error("Service Layer no disponible, se usa SQL:", e.message)
      }
    }
    const pool = await this.getSapPool()
    const items = await fuente.leerPorSql(pool, this.sql, opciones)
    return { items, fuenteUsada: "sql" }
  }

  // Lista de precios del cliente (OCRD.ListNum), en caché 10 minutos.
  // Devuelve null si el cliente no existe.
  async listaPreciosDe(cardCode) {
    if (!cardCode) return null
    const c = this.listasCliente.get(cardCode)
    if (c && Date.now() < c.vence) return c.lista
    const pool = await this.getSapPool()
    const r = await pool
      .request()
      .input("cardCode", this.sql.VarChar, cardCode)
      .query("SELECT ISNULL(ListNum, 1) AS lista FROM OCRD WHERE CardCode = @cardCode")
    const lista = r.recordset[0] ? Number(r.recordset[0].lista) || 1 : null
    this.listasCliente.set(cardCode, { lista, vence: Date.now() + 10 * 60 * 1000 })
    return lista
  }

  categoriaDe(item, cfg) {
    if (cfg && cfg.categoria_app) return cfg.categoria_app
    return CATEGORIA_POR_GRUPO[item.grupoNombre] || item.grupoNombre || "Otros"
  }

  urlImagen(codigo) {
    if (!this.imagenes.existe(codigo)) return null
    return `/api/productos/imagen/${encodeURIComponent(codigo)}?v=${this.imagenes.version(codigo)}`
  }

  // Catálogo para el vendedor: productos visibles con el precio de la lista dada
  async paraVendedor(listaPrecios) {
    const catalogo = await this.obtenerCatalogo()
    const items = catalogo.items

    // Variantes (media/suave) cuelgan del producto padre y no salen como tarjeta
    const variantesPor = new Map()
    for (const cfg of this.config.values()) {
      if (cfg.variante_de && items.has(cfg.item_code)) {
        if (!variantesPor.has(cfg.variante_de)) variantesPor.set(cfg.variante_de, [])
        variantesPor.get(cfg.variante_de).push(cfg)
      }
    }

    const productos = []
    for (const item of items.values()) {
      const cfg = this.config.get(item.codigo)
      if (cfg && (cfg.visible === false || cfg.variante_de)) continue
      productos.push(this._proyectar(item, cfg, listaPrecios, variantesPor.get(item.codigo) || [], items))
    }

    const categorias = ordenarCategorias(new Set(productos.map((p) => p.categoria)))
    productos.sort((a, b) => {
      const ca = categorias.indexOf(a.categoria) - categorias.indexOf(b.categoria)
      if (ca !== 0) return ca
      const oa = a.orden ?? 9999, ob = b.orden ?? 9999
      if (oa !== ob) return oa - ob
      return a.nombre.localeCompare(b.nombre, "es")
    })

    const version = crypto
      .createHash("sha1")
      .update(JSON.stringify(productos.map((p) => [p.codigo, p.precio, p.stock, p.imagenUrl, p.variantes])))
      .digest("hex")
      .slice(0, 16)

    return {
      version,
      actualizado: new Date(catalogo.actualizado).toISOString(),
      fuente: catalogo.fuente,
      listaPrecios,
      categorias: categorias.map((c, i) => ({ id: c, nombre: c, orden: i })),
      productos,
    }
  }

  // El precio es el de la lista del cliente, sin respaldo a otra lista: si su
  // lista no tiene el artículo, a ese cliente no se le vende y el producto se
  // muestra pero no se puede agregar. El stock solo informa, no bloquea.
  _proyectar(item, cfg, listaPrecios, variantesCfg, items) {
    const precio = item.precios[listaPrecios] ?? 0
    const habilitado = precio > 0
    const variantes = variantesCfg.map((v) => {
      const it = items.get(v.item_code)
      const precioVariante = it ? it.precios[listaPrecios] ?? 0 : 0
      return {
        codigo: v.item_code,
        textura: v.textura || "",
        precio: precioVariante,
        stock: it ? it.stock : 0,
        habilitado: precioVariante > 0,
        disponible: precioVariante > 0,
      }
    })
    return {
      codigo: item.codigo,
      nombre: item.nombre,
      categoria: this.categoriaDe(item, cfg),
      grupoSap: item.grupoNombre,
      precio,
      stock: item.stock,
      habilitado,
      disponible: habilitado,
      mensajeEstado: mensajeEstado(habilitado, item.stock),
      descripcion: (cfg && cfg.descripcion) || item.descripcion || "",
      textura: (cfg && cfg.textura) || (variantes.length > 0 ? "Media" : null),
      orden: cfg && cfg.orden != null ? cfg.orden : null,
      imagenUrl: this.urlImagen(item.codigo),
      variantes,
    }
  }

  // Vista completa para soporte: todos los artículos con su configuración
  async paraSoporte() {
    const catalogo = await this.obtenerCatalogo()
    const lista = []
    for (const item of catalogo.items.values()) {
      const cfg = this.config.get(item.codigo) || null
      lista.push({
        codigo: item.codigo,
        nombre: item.nombre,
        grupoSap: item.grupoNombre,
        categoria: this.categoriaDe(item, cfg),
        categoriaApp: cfg ? cfg.categoria_app : null,
        visible: cfg ? cfg.visible !== false : true,
        orden: cfg ? cfg.orden : null,
        varianteDe: cfg ? cfg.variante_de : null,
        textura: cfg ? cfg.textura : null,
        descripcion: (cfg && cfg.descripcion) || item.descripcion || "",
        descripcionSap: item.descripcion,
        stock: item.stock,
        imagenUrl: this.urlImagen(item.codigo),
        actualizadoPor: cfg ? cfg.actualizado_por : null,
      })
    }
    lista.sort((a, b) => a.nombre.localeCompare(b.nombre, "es"))
    return { actualizado: new Date(catalogo.actualizado).toISOString(), fuente: catalogo.fuente, productos: lista, categorias: ORDEN_CATEGORIAS }
  }

  async guardarConfig(codigo, cambios, por) {
    const pool = this.getPedidosPool()
    const s = this.sql
    const req = pool.request().input("codigo", s.NVarChar, codigo).input("por", s.NVarChar, por || null)
    const columnas = {
      categoriaApp: ["categoria_app", s.NVarChar],
      visible: ["visible", s.Bit],
      orden: ["orden", s.Int],
      varianteDe: ["variante_de", s.NVarChar],
      textura: ["textura", s.NVarChar],
      descripcion: ["descripcion", s.NVarChar],
    }
    const sets = []
    const colsInsert = []
    const valores = []
    for (const [clave, [columna, tipo]] of Object.entries(columnas)) {
      if (!(clave in cambios)) continue
      req.input(clave, tipo, cambios[clave] === "" ? null : cambios[clave])
      sets.push(`${columna} = @${clave}`)
      colsInsert.push(columna)
      valores.push(`@${clave}`)
    }
    if (sets.length === 0) return
    await req.query(`
      MERGE dbo.productos_config AS t
      USING (SELECT @codigo AS item_code) AS s ON t.item_code = s.item_code
      WHEN MATCHED THEN UPDATE SET ${sets.join(", ")}, actualizado_por = @por, actualizado_en = GETDATE()
      WHEN NOT MATCHED THEN INSERT (item_code, ${colsInsert.join(", ")}, actualizado_por)
        VALUES (@codigo, ${valores.join(", ")}, @por);
    `)
    await this.cargarConfig()
  }
}

function mensajeEstado(habilitado, stock) {
  if (!habilitado) return "No disponible para este cliente"
  return stock > 0 ? "Producto disponible" : "Sin stock en bodega"
}

function ordenarCategorias(conjunto) {
  const conocidas = ORDEN_CATEGORIAS.filter((c) => conjunto.has(c))
  const otras = [...conjunto].filter((c) => !ORDEN_CATEGORIAS.includes(c)).sort((a, b) => a.localeCompare(b, "es"))
  return [...conocidas, ...otras]
}

module.exports = { RepositorioProductos, CATEGORIA_POR_GRUPO, ORDEN_CATEGORIAS }
