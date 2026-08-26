// Imágenes de producto guardadas en la BD Pedidos (tabla productos_imagenes),
// una por código SAP, como WebP de máximo 400x400. Todas pasan por el mismo
// recorte (procesar), vengan de la migración o de Soporte TI desde la app.
// Las versiones se mantienen en memoria para armar las URL sin consultar la
// BD, y los bytes más pedidos se guardan en una caché pequeña.

const sharp = require("sharp")

const TAMANO = 400
const CALIDAD = 85

class AlmacenImagenes {
  constructor({ sql, getPool, maxCache = 300 }) {
    this.sql = sql
    this.getPool = getPool
    this.maxCache = maxCache
    this.versiones = new Map() // codigo -> version
    this.cache = new Map() // codigo -> { contenido, mime, version }
  }

  async ensureTabla() {
    await this.getPool().request().query(`
      IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'productos_imagenes')
      CREATE TABLE dbo.productos_imagenes (
        item_code       NVARCHAR(50)   NOT NULL PRIMARY KEY,
        contenido       VARBINARY(MAX) NOT NULL,
        mime            NVARCHAR(40)   NOT NULL CONSTRAINT DF_prodimg_mime DEFAULT ('image/webp'),
        tamano          INT            NOT NULL,
        ancho           INT            NULL,
        alto            INT            NULL,
        version         BIGINT         NOT NULL,
        actualizado_por NVARCHAR(100)  NULL,
        actualizado_en  DATETIME       NOT NULL CONSTRAINT DF_prodimg_fecha DEFAULT (GETDATE())
      );
    `)
  }

  async cargarVersiones() {
    const r = await this.getPool().request().query("SELECT item_code, version FROM dbo.productos_imagenes")
    this.versiones = new Map(r.recordset.map((f) => [f.item_code, Number(f.version)]))
    this.cache.clear()
  }

  existe(codigo) {
    return this.versiones.has(codigo)
  }

  version(codigo) {
    return this.versiones.get(codigo) || 0
  }

  listar() {
    return new Set(this.versiones.keys())
  }

  // Recorte único para todas las imágenes: WebP, máximo 400x400, sin ampliar
  async procesar(buffer) {
    const { data, info } = await sharp(buffer)
      .rotate()
      .resize(TAMANO, TAMANO, { fit: "inside", withoutEnlargement: true })
      .webp({ quality: CALIDAD })
      .toBuffer({ resolveWithObject: true })
    return { contenido: data, ancho: info.width, alto: info.height }
  }

  async guardar(codigo, buffer, por) {
    const { contenido, ancho, alto } = await this.procesar(buffer)
    const version = Date.now()
    const s = this.sql
    await this.getPool()
      .request()
      .input("codigo", s.NVarChar, codigo)
      .input("contenido", s.VarBinary(s.MAX), contenido)
      .input("tamano", s.Int, contenido.length)
      .input("ancho", s.Int, ancho)
      .input("alto", s.Int, alto)
      .input("version", s.BigInt, version)
      .input("por", s.NVarChar, por || null)
      .query(`
        MERGE dbo.productos_imagenes AS t
        USING (SELECT @codigo AS item_code) AS s ON t.item_code = s.item_code
        WHEN MATCHED THEN UPDATE SET
          contenido = @contenido, mime = 'image/webp', tamano = @tamano, ancho = @ancho, alto = @alto,
          version = @version, actualizado_por = @por, actualizado_en = GETDATE()
        WHEN NOT MATCHED THEN
          INSERT (item_code, contenido, mime, tamano, ancho, alto, version, actualizado_por)
          VALUES (@codigo, @contenido, 'image/webp', @tamano, @ancho, @alto, @version, @por);
      `)
    this.versiones.set(codigo, version)
    this.cache.delete(codigo)
    return version
  }

  // Bytes de la imagen (null si no existe)
  async obtener(codigo) {
    if (!this.versiones.has(codigo)) return null
    const enCache = this.cache.get(codigo)
    if (enCache) return enCache
    const r = await this.getPool()
      .request()
      .input("codigo", this.sql.NVarChar, codigo)
      .query("SELECT contenido, mime, version FROM dbo.productos_imagenes WHERE item_code = @codigo")
    if (r.recordset.length === 0) {
      this.versiones.delete(codigo)
      return null
    }
    const fila = r.recordset[0]
    const imagen = { contenido: fila.contenido, mime: fila.mime || "image/webp", version: Number(fila.version) }
    if (this.cache.size >= this.maxCache) this.cache.delete(this.cache.keys().next().value)
    this.cache.set(codigo, imagen)
    return imagen
  }

  async eliminar(codigo) {
    const r = await this.getPool()
      .request()
      .input("codigo", this.sql.NVarChar, codigo)
      .query("DELETE FROM dbo.productos_imagenes WHERE item_code = @codigo")
    this.versiones.delete(codigo)
    this.cache.delete(codigo)
    return (r.rowsAffected[0] || 0) > 0
  }
}

// Solo letras, números, guion y guion bajo en el código
function limpiar(codigo) {
  return String(codigo || "").replace(/[^A-Za-z0-9_-]/g, "")
}

module.exports = { AlmacenImagenes, limpiar, TAMANO, CALIDAD }
