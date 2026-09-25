const TABLAS = ["tareas", "tareas_gestores", "tareas_clientes"]
const LOTE_IDS = 400
const MAX_FOTOS = 3

function codigoDeSesion(decoded) {
  if (!decoded) return null
  const n = Number.parseInt(decoded.userId, 10)
  return Number.isFinite(n) ? n : null
}

const texto = (v) => (v == null ? "" : String(v)).trim()

const esPendiente = (estado) => {
  const e = texto(estado).toUpperCase()
  return e === "" || e.startsWith("PEND") || e.startsWith("EN PROC") || e.startsWith("ABIERT")
}

function filaTarea(t, clientes) {
  const indefinido = t.indefinido === true || t.indefinido === 1
  const pendiente = esPendiente(t.estado)
  const dias = t.dias == null ? null : Number(t.dias)
  return {
    id: t.id,
    nombre: texto(t.nombre),
    descripcion: texto(t.descripcion),
    area: texto(t.area),
    estado: texto(t.estado) || "PENDIENTE",
    usuario: texto(t.usuario),
    fechaLimite: indefinido ? null : t.fecha_limite || null,
    indefinido,
    fechaCreacion: t.fecha_creacion || null,
    pendiente,
    vencida: pendiente && !indefinido && dias != null && dias < 0,
    diasRestantes: indefinido ? null : dias,
    clientes: clientes || [],
  }
}

function resumen(tareas) {
  const pendientes = tareas.filter((t) => t.pendiente)
  return {
    total: tareas.length,
    pendientes: pendientes.length,
    vencidas: tareas.filter((t) => t.vencida).length,
    porVencer: pendientes.filter((t) => t.diasRestantes != null && t.diasRestantes >= 0 && t.diasRestantes <= 3).length,
    terminadas: tareas.length - pendientes.length,
  }
}

function crear({ sql, getPedidosPool, asegurarEvidencias, log }) {
  const logger = log || console
  let tablasDisponibles = null
  let respuestasListas = false

  async function asegurarRespuestas() {
    if (respuestasListas) return
    await getPedidosPool().request().query(`
      IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'tareas_respuestas')
      CREATE TABLE dbo.tareas_respuestas (
        id              INT IDENTITY(1,1) PRIMARY KEY,
        tarea_id        INT           NOT NULL,
        cliente_codigo  NVARCHAR(50)  NOT NULL,
        vendedor_codigo INT           NULL,
        vendedor_nombre NVARCHAR(200) NULL,
        visita_id       INT           NULL,
        cumplida        BIT           NOT NULL CONSTRAINT DF_tarearesp_cumplida DEFAULT (0),
        observacion     NVARCHAR(1000) NULL,
        fecha           DATETIME      NOT NULL CONSTRAINT DF_tarearesp_fecha DEFAULT (GETDATE())
      );
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tarearesp_tarea_cliente' AND object_id = OBJECT_ID('dbo.tareas_respuestas'))
        CREATE INDEX IX_tarearesp_tarea_cliente ON dbo.tareas_respuestas(tarea_id, cliente_codigo, vendedor_codigo);
    `)
    // Las fotos se guardan en la tabla de evidencias, que es de otro modulo.
    if (asegurarEvidencias) await asegurarEvidencias(getPedidosPool())
    // La columna y su indice van en consultas aparte: SQL Server resuelve los
    // nombres al compilar el lote, y el indice no veria una columna recien creada.
    await getPedidosPool().request().query(`
      IF OBJECT_ID('dbo.evidencias_archivos') IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='tarea_respuesta_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
        ALTER TABLE dbo.evidencias_archivos ADD tarea_respuesta_id INT NULL;
    `)
    await getPedidosPool().request().query(`
      IF EXISTS (SELECT 1 FROM sys.columns WHERE Name='tarea_respuesta_id' AND Object_ID=Object_ID('dbo.evidencias_archivos'))
         AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_evid_tarea_respuesta' AND object_id = OBJECT_ID('dbo.evidencias_archivos'))
        CREATE INDEX IX_evid_tarea_respuesta ON dbo.evidencias_archivos(tarea_respuesta_id);
    `)
    respuestasListas = true
  }

  async function hayTablas() {
    if (tablasDisponibles !== null) return tablasDisponibles
    try {
      const r = await getPedidosPool()
        .request()
        .query(`SELECT COUNT(*) AS n FROM sys.tables WHERE name IN ('${TABLAS.join("','")}')`)
      tablasDisponibles = (r.recordset[0].n || 0) === TABLAS.length
      if (!tablasDisponibles) logger.error("Tareas: faltan tablas en la base Pedidos, el modulo responde vacio")
    } catch (e) {
      logger.error("Tareas: no se pudo comprobar las tablas:", e.message)
      tablasDisponibles = false
    }
    return tablasDisponibles
  }

  // SQL Server admite 2100 parametros por consulta: los ids van por lotes.
  async function porLotes(ids, consulta) {
    const filas = []
    for (let i = 0; i < ids.length; i += LOTE_IDS) {
      filas.push(...(await consulta(ids.slice(i, i + LOTE_IDS))))
    }
    return filas
  }

  async function clientesDe(ids) {
    const porTarea = new Map()
    if (ids.length === 0) return porTarea
    const filas = await porLotes(ids, async (lote) => {
      const req = getPedidosPool().request()
      const marcadores = lote.map((id, i) => {
        req.input(`t${i}`, sql.Int, id)
        return `@t${i}`
      })
      const r = await req.query(`
        SELECT tarea_id, cliente_codigo, cliente_nombre
        FROM dbo.tareas_clientes
        WHERE tarea_id IN (${marcadores.join(",")})
        ORDER BY cliente_nombre
      `)
      return r.recordset
    })
    for (const f of filas) {
      if (!porTarea.has(f.tarea_id)) porTarea.set(f.tarea_id, [])
      porTarea.get(f.tarea_id).push({
        codigo: texto(f.cliente_codigo),
        nombre: texto(f.cliente_nombre),
      })
    }
    return porTarea
  }

  async function respuestasDe(vendedorCodigo, ids, clienteCodigo) {
    const mapa = new Map()
    if (ids.length === 0) return mapa
    await asegurarRespuestas()
    const filas = await porLotes(ids, async (lote) => {
      const req = getPedidosPool().request().input("vend", sql.Int, vendedorCodigo)
      const marcadores = lote.map((id, i) => {
        req.input(`t${i}`, sql.Int, id)
        return `@t${i}`
      })
      let filtroCliente = ""
      if (clienteCodigo) {
        req.input("cli", sql.NVarChar, clienteCodigo)
        filtroCliente = "AND r.cliente_codigo = @cli"
      }
      const r = await req.query(`
        SELECT r.id, r.tarea_id, r.cliente_codigo, r.cumplida, r.observacion,
               CONVERT(VARCHAR(19), r.fecha, 120) AS fecha,
               (SELECT COUNT(*) FROM dbo.evidencias_archivos e WHERE e.tarea_respuesta_id = r.id) AS evidencias
        FROM dbo.tareas_respuestas r
        WHERE r.tarea_id IN (${marcadores.join(",")}) AND r.vendedor_codigo = @vend ${filtroCliente}
        ORDER BY r.fecha DESC, r.id DESC
      `)
      return r.recordset
    })
    for (const f of filas) {
      const clave = `${f.tarea_id}|${texto(f.cliente_codigo)}`
      if (mapa.has(clave)) continue
      mapa.set(clave, {
        id: f.id,
        clienteCodigo: texto(f.cliente_codigo),
        cumplida: f.cumplida === true || f.cumplida === 1,
        observacion: texto(f.observacion),
        evidencias: Number(f.evidencias) || 0,
        fecha: f.fecha,
      })
    }
    return mapa
  }

  async function misTareas(vendedorCodigo, { limite = 1000, clienteCodigo = null } = {}) {
    if (!(await hayTablas())) return []
    const req = getPedidosPool().request().input("vend", sql.Int, vendedorCodigo).input("limite", sql.Int, limite)
    let filtroCliente = ""
    if (clienteCodigo) {
      req.input("cli", sql.NVarChar, clienteCodigo)
      filtroCliente = `
        AND EXISTS (
          SELECT 1 FROM dbo.tareas_clientes c
          WHERE c.tarea_id = t.id AND c.cliente_codigo = @cli
        )`
    }
    const r = await req.query(`
      SELECT TOP (@limite) t.id, t.nombre, t.descripcion, t.area, t.indefinido, t.estado, t.usuario,
             CONVERT(VARCHAR(10), t.fecha_limite, 120) AS fecha_limite,
             CONVERT(VARCHAR(19), t.fecha_creacion, 120) AS fecha_creacion,
             DATEDIFF(day, CAST(GETDATE() AS DATE), t.fecha_limite) AS dias
      FROM dbo.tareas t
      WHERE EXISTS (
        SELECT 1 FROM dbo.tareas_gestores g
        WHERE g.tarea_id = t.id AND g.vendedor_codigo = @vend
      ) ${filtroCliente}
      ORDER BY t.fecha_creacion DESC, t.id DESC
    `)
    const ids = r.recordset.map((t) => t.id)
    const [clientes, respuestas] = await Promise.all([
      clientesDe(ids),
      respuestasDe(vendedorCodigo, ids, clienteCodigo).catch((e) => {
        logger.error("Tareas: no se pudieron leer las respuestas:", e.message)
        return new Map()
      }),
    ])
    return r.recordset.map((t) => {
      const tarea = filaTarea(t, clientes.get(t.id))
      if (!clienteCodigo) return tarea
      const respuesta = respuestas.get(`${t.id}|${clienteCodigo}`) || null
      return { ...tarea, respondida: !!respuesta, respuesta }
    })
  }

  // La respuesta y sus fotos entran juntas: si algo falla, no queda ni una cosa ni la otra.
  async function responder(vendedorCodigo, { tareaId, clienteCodigo, vendedorNombre, visitaId, cumplida, observacion }, imagenes = []) {
    await asegurarRespuestas()
    const transaccion = getPedidosPool().transaction()
    await transaccion.begin()
    try {
      const r = await transaccion
        .request()
        .input("tarea", sql.Int, tareaId)
        .input("cli", sql.NVarChar, clienteCodigo)
        .input("vend", sql.Int, vendedorCodigo)
        .input("vendNom", sql.NVarChar, texto(vendedorNombre) || null)
        .input("visita", sql.Int, Number.isFinite(visitaId) ? visitaId : null)
        .input("cumplida", sql.Bit, cumplida ? 1 : 0)
        .input("obs", sql.NVarChar, texto(observacion).slice(0, 1000) || null)
        .query(`
          INSERT INTO dbo.tareas_respuestas
            (tarea_id, cliente_codigo, vendedor_codigo, vendedor_nombre, visita_id, cumplida, observacion)
          OUTPUT INSERTED.id, CONVERT(VARCHAR(19), INSERTED.fecha, 120) AS fecha
          VALUES (@tarea, @cli, @vend, @vendNom, @visita, @cumplida, @obs)
        `)
      const fila = r.recordset[0]

      for (const imagen of imagenes) {
        await transaccion
          .request()
          .input("origen", sql.NVarChar, "tarea")
          .input("cliente", sql.NVarChar, clienteCodigo)
          .input("vendId", sql.Int, vendedorCodigo)
          .input("vendNom", sql.NVarChar, texto(vendedorNombre) || null)
          .input("respuesta", sql.Int, fila.id)
          .input("contenido", sql.VarBinary(sql.MAX), imagen.contenido)
          .input("tamano", sql.Int, imagen.contenido.length)
          .input("ancho", sql.Int, imagen.ancho || null)
          .input("alto", sql.Int, imagen.alto || null)
          .query(`
            INSERT INTO dbo.evidencias_archivos
              (origen, cliente_id, vendedor_id, vendedor_nombre, tarea_respuesta_id, contenido, tamano, ancho, alto)
            VALUES (@origen, @cliente, @vendId, @vendNom, @respuesta, @contenido, @tamano, @ancho, @alto)
          `)
      }

      await transaccion.commit()
      return { ...fila, evidencias: imagenes.length }
    } catch (e) {
      try { await transaccion.rollback() } catch (_) {}
      throw e
    }
  }

  function registrarRutas(app, { requireAuth, subida, procesarImagen }) {
    // Sin multer el modulo sigue funcionando, solo que sin fotos.
    const recibirFotos = subida
      ? (req, res, next) => {
          subida.fields([{ name: "fotos", maxCount: MAX_FOTOS }])(req, res, (err) => {
            if (!err) return next()
            logger.error("Tareas: no se pudieron recibir las fotos:", err.message)
            res.status(400).json({ success: false, message: `Adjunta maximo ${MAX_FOTOS} imagenes` })
          })
        }
      : (req, res, next) => next()

    app.get("/api/tareas", requireAuth, async (req, res) => {
      try {
        const vendedor = codigoDeSesion(req.user)
        if (vendedor === null) {
          return res.json({ success: true, data: [], resumen: resumen([]) })
        }
        const clienteCodigo = texto(req.query.cliente) || null
        const tareas = await misTareas(vendedor, { clienteCodigo })
        res.set("Cache-Control", "private, no-cache")
        res.json({
          success: true,
          data: tareas,
          total: tareas.length,
          resumen: resumen(tareas),
          ...(clienteCodigo ? { pendientesPorResponder: tareas.filter((t) => t.pendiente && !t.respondida).length } : {}),
        })
      } catch (error) {
        logger.error("Error listando tareas del gestor:", error.message)
        res.status(500).json({ success: false, message: "No se pudieron cargar las tareas", data: [] })
      }
    })

    app.post("/api/tareas/:id/respuesta", requireAuth, recibirFotos, async (req, res) => {
      try {
        const tareaId = Number.parseInt(req.params.id, 10)
        const b = req.body || {}
        const clienteCodigo = texto(b.clienteCodigo)
        if (!Number.isFinite(tareaId) || !clienteCodigo) {
          return res.status(400).json({ success: false, message: "Indica la tarea y el cliente" })
        }
        const archivos = ((req.files && req.files.fotos) || []).slice(0, MAX_FOTOS)
        const imagenes = procesarImagen
          ? await Promise.all(archivos.map((f) => procesarImagen(f.buffer)))
          : []
        const visitaId = Number.parseInt(b.visitaId, 10)
        const fila = await responder(
          codigoDeSesion(req.user),
          {
            tareaId,
            clienteCodigo,
            vendedorNombre: req.user && req.user.nombre,
            visitaId,
            cumplida: b.cumplida === true || b.cumplida === 1 || b.cumplida === "true",
            observacion: b.observacion,
          },
          imagenes,
        )
        logger.log(
          `Tarea ${tareaId} respondida para ${clienteCodigo}: cumplida=${fila.cumplida === 1 || b.cumplida === true || b.cumplida === "true"} ` +
            `fotos=${imagenes.length} visita=${Number.isFinite(visitaId) ? visitaId : "-"}`,
        )
        res.json({ success: true, data: { id: fila.id, fecha: fila.fecha, evidencias: fila.evidencias, tareaId, clienteCodigo } })
      } catch (error) {
        logger.error("Error registrando la respuesta de la tarea:", error.message)
        res.status(500).json({ success: false, message: "No se pudo guardar la información de la tarea" })
      }
    })
  }

  return { registrarRutas, misTareas, responder }
}

module.exports = { crear, filaTarea, resumen, esPendiente }
