// =============================================================================
//  Módulo: Control de dispositivos por "ID de servicio"
// -----------------------------------------------------------------------------
//  - Cada instalación de la app genera un ID de servicio único (SVC-XXXX-XXXX).
//  - El login estampa la identidad del vendedor en el dispositivo (asociación
//    automática) y solo permite entrar si el dispositivo está en estado ACTIVO.
//  - El rol "soporte" NO usa cuentas propias: lo asigna server.js en el login
//    normal a los usuarios designados en SOPORTE_USUARIOS (.env). Ese rol no
//    pasa por el gate de dispositivo y administra la activación/desactivación.
//
//  Tablas (BD Pedidos): dispositivos.
//  Todas las dependencias (sql, jwt, JWT_SECRET, pool) se inyectan desde
//  server.js para mantener el módulo desacoplado.
// =============================================================================

const ESTADOS = ["PENDIENTE", "ACTIVO", "DESACTIVADO"]

// -----------------------------------------------------------------------------
//  Creación de tablas (idempotente, mismo patrón que el resto del server.js)
// -----------------------------------------------------------------------------
async function ensureTablas(pool) {
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dispositivos')
    CREATE TABLE dbo.dispositivos (
      id INT IDENTITY(1,1) PRIMARY KEY,
      id_servicio         NVARCHAR(60)  NOT NULL UNIQUE,
      estado              NVARCHAR(20)  NOT NULL CONSTRAINT DF_disp_estado DEFAULT ('PENDIENTE'),
      usuario_documento   NVARCHAR(60)  NULL,
      usuario_nombre      NVARCHAR(200) NULL,
      usuario_codigo      NVARCHAR(60)  NULL,
      usuario_telefono    NVARCHAR(60)  NULL,
      usuario_email       NVARCHAR(200) NULL,
      plataforma          NVARCHAR(40)  NULL,
      fecha_registro      DATETIME NOT NULL CONSTRAINT DF_disp_freg DEFAULT (GETDATE()),
      fecha_ultimo_acceso DATETIME NULL,
      activado_por        NVARCHAR(200) NULL,
      fecha_activacion    DATETIME NULL
    );
  `)
}

// -----------------------------------------------------------------------------
//  Registra el dispositivo (si es nuevo) y le asocia la identidad de la persona
//  (sin sobreescribir datos previos con nulos). Devuelve el estado actual.
//  persona puede ser null (registro pre-login, sin identidad todavía).
// -----------------------------------------------------------------------------
async function registrarYAsociar(pool, sql, idServicio, persona, plataforma) {
  await pool
    .request()
    .input("id_servicio", sql.NVarChar, idServicio)
    .input("doc", sql.NVarChar, (persona && persona.documento) || null)
    .input("nom", sql.NVarChar, (persona && persona.nombre) || null)
    .input("cod", sql.NVarChar, (persona && persona.codigo) || null)
    .input("tel", sql.NVarChar, (persona && persona.telefono) || null)
    .input("email", sql.NVarChar, (persona && persona.email) || null)
    .input("plat", sql.NVarChar, plataforma || null)
    .query(`
      MERGE dbo.dispositivos AS t
      USING (SELECT @id_servicio AS id_servicio) AS s ON t.id_servicio = s.id_servicio
      WHEN MATCHED THEN UPDATE SET
        usuario_documento   = COALESCE(@doc,   t.usuario_documento),
        usuario_nombre      = COALESCE(@nom,   t.usuario_nombre),
        usuario_codigo      = COALESCE(@cod,   t.usuario_codigo),
        usuario_telefono    = COALESCE(@tel,   t.usuario_telefono),
        usuario_email       = COALESCE(@email, t.usuario_email),
        plataforma          = COALESCE(@plat,  t.plataforma),
        fecha_ultimo_acceso = GETDATE()
      WHEN NOT MATCHED THEN
        INSERT (id_servicio, usuario_documento, usuario_nombre, usuario_codigo, usuario_telefono, usuario_email, plataforma, fecha_ultimo_acceso)
        VALUES (@id_servicio, @doc, @nom, @cod, @tel, @email, @plat, GETDATE());
    `)

  const r = await pool
    .request()
    .input("id_servicio", sql.NVarChar, idServicio)
    .query("SELECT TOP 1 estado FROM dbo.dispositivos WHERE id_servicio = @id_servicio")
  return (r.recordset[0] && r.recordset[0].estado) || "PENDIENTE"
}

// -----------------------------------------------------------------------------
//  Middleware: exige token de rol "soporte".
// -----------------------------------------------------------------------------
function soporteMiddleware(jwt, JWT_SECRET) {
  return (req, res, next) => {
    const h = req.headers.authorization
    if (!h || !h.startsWith("Bearer ")) {
      return res.status(401).json({ success: false, message: "No autorizado" })
    }
    try {
      const decoded = jwt.verify(h.slice(7), JWT_SECRET)
      if (decoded.rol !== "soporte") {
        return res.status(403).json({ success: false, message: "Requiere permisos de soporte TI" })
      }
      req.user = decoded
      next()
    } catch (_) {
      return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
    }
  }
}

// -----------------------------------------------------------------------------
//  Registro de rutas. getPool() devuelve el pool vivo (BD Pedidos) en cada request.
// -----------------------------------------------------------------------------
function registrarRutas(app, getPool, sql, requireSoporte) {
  // App (pre-login, sin auth): registra el dispositivo y devuelve su estado.
  app.post("/api/dispositivos/registrar", async (req, res) => {
    try {
      const idServicio = (req.body.id_servicio || "").toString().trim()
      if (!idServicio) {
        return res.status(400).json({ success: false, message: "id_servicio requerido" })
      }
      const estado = await registrarYAsociar(getPool(), sql, idServicio, null, (req.body.plataforma || "").toString())
      res.json({ success: true, id_servicio: idServicio, estado })
    } catch (e) {
      console.error("Error registrando dispositivo:", e.message)
      res.status(500).json({ success: false, message: "Error al registrar dispositivo" })
    }
  })

  // Soporte: listar dispositivos (con buscador por ID, nombre, documento o código).
  app.get("/api/dispositivos", requireSoporte, async (req, res) => {
    try {
      const buscar = (req.query.buscar || "").toString().trim()
      const reqDb = getPool().request()
      let where = ""
      if (buscar) {
        where =
          "WHERE id_servicio LIKE @b OR usuario_nombre LIKE @b OR usuario_documento LIKE @b OR usuario_codigo LIKE @b"
        reqDb.input("b", sql.NVarChar, `%${buscar}%`)
      }
      const r = await reqDb.query(
        `SELECT * FROM dbo.dispositivos ${where} ORDER BY fecha_ultimo_acceso DESC, fecha_registro DESC`
      )
      res.json({ success: true, data: r.recordset, total: r.recordset.length })
    } catch (e) {
      console.error("Error listando dispositivos:", e.message)
      res.status(500).json({ success: false, message: "Error al listar dispositivos", data: [] })
    }
  })

  // Soporte: cambiar estado (ACTIVO / DESACTIVADO / PENDIENTE).
  app.post("/api/dispositivos/:idServicio/estado", requireSoporte, async (req, res) => {
    try {
      const idServicio = (req.params.idServicio || "").toString().trim()
      const nuevo = (req.body.estado || "").toString().toUpperCase()
      if (!ESTADOS.includes(nuevo)) {
        return res.status(400).json({ success: false, message: "Estado inválido" })
      }
      const r = await getPool()
        .request()
        .input("id_servicio", sql.NVarChar, idServicio)
        .input("estado", sql.NVarChar, nuevo)
        .input("por", sql.NVarChar, (req.user && (req.user.nombre || req.user.usuario)) || "soporte")
        .query(`
          UPDATE dbo.dispositivos
          SET estado = @estado,
              activado_por = @por,
              fecha_activacion = CASE WHEN @estado = 'ACTIVO' THEN GETDATE() ELSE fecha_activacion END
          WHERE id_servicio = @id_servicio;
          SELECT @@ROWCOUNT AS afectados;
        `)
      if (((r.recordset[0] && r.recordset[0].afectados) || 0) === 0) {
        return res.status(404).json({ success: false, message: "Dispositivo no encontrado" })
      }
      res.json({ success: true, id_servicio: idServicio, estado: nuevo })
    } catch (e) {
      console.error("Error cambiando estado de dispositivo:", e.message)
      res.status(500).json({ success: false, message: "Error al cambiar estado" })
    }
  })

  // Soporte: eliminar un dispositivo del registro.
  app.delete("/api/dispositivos/:idServicio", requireSoporte, async (req, res) => {
    try {
      const idServicio = (req.params.idServicio || "").toString().trim()
      const r = await getPool()
        .request()
        .input("id_servicio", sql.NVarChar, idServicio)
        .query(`
          DELETE FROM dbo.dispositivos WHERE id_servicio = @id_servicio;
          SELECT @@ROWCOUNT AS afectados;
        `)
      if (((r.recordset[0] && r.recordset[0].afectados) || 0) === 0) {
        return res.status(404).json({ success: false, message: "Dispositivo no encontrado" })
      }
      res.json({ success: true, id_servicio: idServicio })
    } catch (e) {
      console.error("Error eliminando dispositivo:", e.message)
      res.status(500).json({ success: false, message: "Error al eliminar dispositivo" })
    }
  })
}

module.exports = {
  ESTADOS,
  ensureTablas,
  registrarYAsociar,
  soporteMiddleware,
  registrarRutas,
}
