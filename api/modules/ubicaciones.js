const RADIO_TIERRA_M = 6371000
const ORIGENES = new Set(["periodico", "visita_inicio", "visita_fin", "pedido", "inicio_sesion", "manual"])
const MAX_PUNTOS = 500
const PUNTOS_POR_LOTE = 100

function codigoDeSesion(decoded) {
  if (!decoded) return null
  if (decoded.userId != null) return String(decoded.userId)
  return (decoded.documento || "").toString().trim() || null
}

function usuarioDeSesion(decoded, idServicio) {
  const d = decoded || {}
  return {
    codigo: codigoDeSesion(d),
    nombre: (d.nombre || "").toString().trim().slice(0, 200) || null,
    tipo: (d.rol === "soporte" ? "soporte" : d.tipo || "usuario").toString().slice(0, 20),
    idServicio: (d.id_servicio || idServicio || "").toString().trim().slice(0, 100) || null,
  }
}

const numero = (v) => {
  if (v === null || v === undefined || v === "") return null
  const n = Number.parseFloat(v)
  return Number.isFinite(n) ? n : null
}

const texto = (v, max) => {
  const t = (v == null ? "" : String(v)).trim()
  return t ? t.slice(0, max) : null
}

function coordenadaValida(lat, lng) {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180 &&
    !(lat === 0 && lng === 0)
  )
}

function distanciaMetros(lat1, lng1, lat2, lng2) {
  const rad = (g) => (g * Math.PI) / 180
  const dLat = rad(lat2 - lat1)
  const dLng = rad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2
  return 2 * RADIO_TIERRA_M * Math.asin(Math.min(1, Math.sqrt(a)))
}

function milisegundosDesde(valor) {
  const n = typeof valor === "number" ? valor : Number.parseFloat(valor)
  return Number.isFinite(n) && n > 946684800000 && n < 4102444800000 ? Math.trunc(n) : null
}

function textoDeFecha(valor) {
  const t = (valor || "").toString().trim()
  return /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/.test(t) ? t.slice(0, 23).replace(" ", "T") : null
}

function fechaValida(valor) {
  const t = (valor || "").toString().trim()
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null
}

const esVerdadero = (v) => v === true || v === 1 || v === "1" || v === "true"

function normalizarPunto(p) {
  if (!p || typeof p !== "object") return null
  const lat = numero(p.latitud ?? p.lat)
  const lng = numero(p.longitud ?? p.lng)
  if (!coordenadaValida(lat, lng)) return null
  const origen = (p.origen || "").toString().trim().toLowerCase()
  const visitaId = Number.parseInt(p.visitaId, 10)
  const limitar = (v, max) => (v == null ? null : Math.max(-max, Math.min(max, v)))
  return {
    latitud: lat,
    longitud: lng,
    precision: limitar(numero(p.precision), 99999999),
    altitud: limitar(numero(p.altitud), 99999999),
    velocidad: limitar(numero(p.velocidad), 99999999),
    rumbo: limitar(numero(p.rumbo), 9999),
    simulada: esVerdadero(p.simulada),
    origen: ORIGENES.has(origen) ? origen : "periodico",
    capturadoMs: milisegundosDesde(p.capturadoEnMs),
    capturadoTexto: textoDeFecha(p.capturadoEn),
    idLocal: texto(p.idLocal, 64),
    clienteCodigo: texto(p.clienteCodigo, 50),
    visitaId: Number.isNaN(visitaId) ? null : visitaId,
    appVersion: texto(p.appVersion, 30),
  }
}

function resumenRecorrido(puntos) {
  let distancia = 0
  let previo = null
  const clientes = new Set()
  let simuladas = 0
  let enCliente = 0
  for (const p of puntos) {
    if (p.enCliente) {
      enCliente++
      if (p.clienteCodigo) clientes.add(p.clienteCodigo)
    }
    if (p.simulada) {
      simuladas++
      continue
    }
    if (previo) distancia += distanciaMetros(previo.latitud, previo.longitud, p.latitud, p.longitud)
    previo = p
  }
  return {
    puntos: puntos.length,
    simuladas,
    enCliente,
    clientes: clientes.size,
    distanciaKm: Math.round(distancia / 10) / 100,
    primera: puntos.length ? puntos[0].fecha : null,
    ultima: puntos.length ? puntos[puntos.length - 1].fecha : null,
  }
}

function filaPunto(f) {
  return {
    id: Number(f.id),
    latitud: numero(f.latitud),
    longitud: numero(f.longitud),
    precisionM: numero(f.precision_m),
    velocidadMs: numero(f.velocidad_ms),
    simulada: f.simulada === true || f.simulada === 1,
    origen: f.origen,
    clienteCodigo: f.cliente_codigo || null,
    distanciaClienteM: f.distancia_cliente_m == null ? null : Number(f.distancia_cliente_m),
    enCliente: f.en_cliente == null ? null : f.en_cliente === true || f.en_cliente === 1,
    visitaId: f.visita_id == null ? null : Number(f.visita_id),
    fecha: f.fecha,
  }
}

function crearDirectorioClientes({ getRutaPool, geocodificarCliente, ttlMs, logger }) {
  let cargado = null
  let cargando = null
  const geocodificados = new Map()

  async function cargar() {
    const pool = await getRutaPool()
    const r = await pool.request().query(`
      SELECT cliente_codigo, latitud, longitud, precision_geocodificacion, fuente_geocodificacion
      FROM dbo.geolocalizacion
      WHERE latitud IS NOT NULL AND longitud IS NOT NULL
    `)
    const porCodigo = new Map()
    const lista = []
    for (const f of r.recordset) {
      const codigo = (f.cliente_codigo || "").toString().trim()
      const lat = numero(f.latitud)
      const lng = numero(f.longitud)
      if (!codigo || !coordenadaValida(lat, lng)) continue
      const cliente = {
        codigo,
        lat,
        lng,
        precision: numero(f.precision_geocodificacion),
        fuente: (f.fuente_geocodificacion || "geolocalizacion").toString(),
      }
      porCodigo.set(codigo.toUpperCase(), cliente)
      lista.push(cliente)
    }
    return { porCodigo, lista, vence: Date.now() + ttlMs }
  }

  async function datos() {
    if (cargado && Date.now() < cargado.vence) return cargado
    if (!cargando) {
      cargando = cargar()
        .then((d) => {
          cargado = d
          return d
        })
        .catch((e) => {
          logger.error("No se pudieron cargar las coordenadas de clientes:", e.message)
          if (cargado) return cargado
          throw e
        })
        .finally(() => {
          cargando = null
        })
    }
    return cargando
  }

  async function coordenadasDe(codigo) {
    const clave = (codigo || "").toString().trim().toUpperCase()
    if (!clave) return null
    const d = await datos()
    const propia = d.porCodigo.get(clave)
    if (propia) return propia
    if (!geocodificarCliente) return null
    const guardada = geocodificados.get(clave)
    if (guardada && Date.now() < guardada.vence) return guardada.valor
    let valor = null
    try {
      const g = await geocodificarCliente(codigo)
      const lat = g ? numero(g.lat) : null
      const lng = g ? numero(g.lng) : null
      if (g && coordenadaValida(lat, lng) && g.precision !== "ciudad") {
        valor = { codigo: codigo.toString().trim(), lat, lng, precision: null, fuente: `geocodificacion_${g.precision || "sap"}` }
      }
    } catch (_) {}
    if (geocodificados.size >= 2000) geocodificados.delete(geocodificados.keys().next().value)
    geocodificados.set(clave, { valor, vence: Date.now() + ttlMs })
    return valor
  }

  async function masCercano(lat, lng, radioM) {
    const d = await datos()
    const margenLat = radioM / 111320
    const margenLng = radioM / (111320 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01))
    let mejor = null
    for (const c of d.lista) {
      if (Math.abs(c.lat - lat) > margenLat || Math.abs(c.lng - lng) > margenLng) continue
      const distancia = distanciaMetros(lat, lng, c.lat, c.lng)
      if (distancia <= radioM && (!mejor || distancia < mejor.distancia)) mejor = { cliente: c, distancia }
    }
    return mejor
  }

  return { coordenadasDe, masCercano }
}

function crear({ sql, getPedidosPool, getRutaPool, geocodificarCliente, env, log }) {
  const logger = log || console
  const variables = env || {}
  const radioM = Math.max(10, Number.parseInt(variables.RADIO_EN_CLIENTE_M, 10) || 150)
  const directorio = crearDirectorioClientes({
    getRutaPool,
    geocodificarCliente,
    ttlMs: 6 * 60 * 60 * 1000,
    logger,
  })
  let tablaLista = false

  async function asegurarTabla() {
    if (tablaLista) return
    await getPedidosPool().request().query(`
      IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ubicaciones_recorrido')
      CREATE TABLE dbo.ubicaciones_recorrido (
        id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        usuario_codigo      NVARCHAR(50)  NOT NULL,
        usuario_nombre      NVARCHAR(200) NULL,
        tipo_usuario        NVARCHAR(20)  NULL,
        id_servicio         NVARCHAR(100) NULL,
        id_local            NVARCHAR(64)  NULL,
        latitud             DECIMAL(9,6)  NOT NULL,
        longitud            DECIMAL(9,6)  NOT NULL,
        precision_m         DECIMAL(10,2) NULL,
        altitud_m           DECIMAL(10,2) NULL,
        velocidad_ms        DECIMAL(10,2) NULL,
        rumbo               DECIMAL(6,2)  NULL,
        simulada            BIT           NOT NULL CONSTRAINT DF_ubic_simulada DEFAULT (0),
        origen              NVARCHAR(30)  NOT NULL CONSTRAINT DF_ubic_origen DEFAULT ('periodico'),
        visita_id           INT           NULL,
        cliente_codigo      NVARCHAR(50)  NULL,
        distancia_cliente_m INT           NULL,
        en_cliente          BIT           NULL,
        app_version         NVARCHAR(30)  NULL,
        fecha_captura       DATETIME      NOT NULL,
        fecha_registro      DATETIME      NOT NULL CONSTRAINT DF_ubic_registro DEFAULT (GETDATE())
      );
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ubic_usuario_fecha' AND object_id = OBJECT_ID('dbo.ubicaciones_recorrido'))
        CREATE INDEX IX_ubic_usuario_fecha ON dbo.ubicaciones_recorrido(usuario_codigo, fecha_captura);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ubic_fecha' AND object_id = OBJECT_ID('dbo.ubicaciones_recorrido'))
        CREATE INDEX IX_ubic_fecha ON dbo.ubicaciones_recorrido(fecha_captura) INCLUDE (usuario_codigo, simulada, en_cliente);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_ubic_id_local' AND object_id = OBJECT_ID('dbo.ubicaciones_recorrido'))
        CREATE UNIQUE INDEX UQ_ubic_id_local ON dbo.ubicaciones_recorrido(usuario_codigo, id_local) WHERE id_local IS NOT NULL;
    `)
    tablaLista = true
  }

  async function evaluar({ lat, lng, clienteCodigo }) {
    if (!coordenadaValida(lat, lng)) return null
    try {
      if (clienteCodigo) {
        const c = await directorio.coordenadasDe(clienteCodigo)
        if (!c) {
          return { clienteCodigo, sinCoordenadas: true, enCliente: null, distanciaM: null, radioM }
        }
        const distanciaM = Math.round(distanciaMetros(lat, lng, c.lat, c.lng))
        return {
          clienteCodigo,
          sinCoordenadas: false,
          enCliente: distanciaM <= radioM,
          distanciaM,
          radioM,
          clienteLat: c.lat,
          clienteLng: c.lng,
          fuente: c.fuente,
          precisionCliente: c.precision,
        }
      }
      const cercano = await directorio.masCercano(lat, lng, radioM)
      if (!cercano) return { clienteCodigo: null, sinCoordenadas: false, enCliente: false, distanciaM: null, radioM }
      return {
        clienteCodigo: cercano.cliente.codigo,
        sinCoordenadas: false,
        enCliente: true,
        distanciaM: Math.round(cercano.distancia),
        radioM,
        clienteLat: cercano.cliente.lat,
        clienteLng: cercano.cliente.lng,
        fuente: cercano.cliente.fuente,
        precisionCliente: cercano.cliente.precision,
      }
    } catch (e) {
      logger.error("No se pudo evaluar si la ubicacion esta en el cliente:", e.message)
      return null
    }
  }

  async function insertarLote(usuario, lote) {
    const req = getPedidosPool()
      .request()
      .input("u", sql.NVarChar, usuario.codigo)
      .input("un", sql.NVarChar, usuario.nombre)
      .input("ut", sql.NVarChar, usuario.tipo)
      .input("us", sql.NVarChar, usuario.idServicio)
    const sentencias = lote.map(({ punto: p, evaluacion: e }, i) => {
      req
        .input(`l${i}`, sql.NVarChar, p.idLocal)
        .input(`la${i}`, sql.Decimal(9, 6), p.latitud)
        .input(`lo${i}`, sql.Decimal(9, 6), p.longitud)
        .input(`pr${i}`, sql.Decimal(10, 2), p.precision)
        .input(`al${i}`, sql.Decimal(10, 2), p.altitud)
        .input(`ve${i}`, sql.Decimal(10, 2), p.velocidad)
        .input(`ru${i}`, sql.Decimal(6, 2), p.rumbo)
        .input(`si${i}`, sql.Bit, p.simulada ? 1 : 0)
        .input(`or${i}`, sql.NVarChar, p.origen)
        .input(`vi${i}`, sql.Int, p.visitaId)
        .input(`cc${i}`, sql.NVarChar, e ? e.clienteCodigo : p.clienteCodigo)
        .input(`di${i}`, sql.Int, e && e.distanciaM != null ? e.distanciaM : null)
        .input(`ec${i}`, sql.Bit, e && e.enCliente != null ? (e.enCliente ? 1 : 0) : null)
        .input(`av${i}`, sql.NVarChar, p.appVersion)
        .input(`fs${i}`, sql.Int, p.capturadoMs == null ? null : Math.floor(p.capturadoMs / 1000))
        .input(`fm${i}`, sql.Int, p.capturadoMs == null ? null : p.capturadoMs % 1000)
        .input(`ft${i}`, sql.VarChar, p.capturadoTexto)
      return `
        IF @l${i} IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.ubicaciones_recorrido WHERE usuario_codigo = @u AND id_local = @l${i})
        BEGIN
          INSERT INTO dbo.ubicaciones_recorrido
            (usuario_codigo, usuario_nombre, tipo_usuario, id_servicio, id_local, latitud, longitud, precision_m, altitud_m,
             velocidad_ms, rumbo, simulada, origen, visita_id, cliente_codigo, distancia_cliente_m, en_cliente, app_version, fecha_captura)
          VALUES (@u, @un, @ut, @us, @l${i}, @la${i}, @lo${i}, @pr${i}, @al${i}, @ve${i}, @ru${i}, @si${i}, @or${i}, @vi${i},
                  @cc${i}, @di${i}, @ec${i}, @av${i},
                  COALESCE(
                    DATEADD(minute, @desfase, DATEADD(millisecond, @fm${i}, DATEADD(second, @fs${i}, CAST('19700101' AS DATETIME)))),
                    TRY_CONVERT(DATETIME, @ft${i}, 126),
                    GETDATE()));
          SET @guardados = @guardados + 1;
        END`
    })
    const r = await req.query(`
      DECLARE @guardados INT = 0;
      DECLARE @desfase INT = DATEDIFF(minute, GETUTCDATE(), GETDATE());
      ${sentencias.join("\n")}
      SELECT @guardados AS guardados;
    `)
    return Number(r.recordset[0].guardados) || 0
  }

  async function registrarPuntos(usuario, crudos) {
    await asegurarTabla()
    const lista = (Array.isArray(crudos) ? crudos : [crudos]).slice(0, MAX_PUNTOS)
    const vistos = new Set()
    const validos = []
    let descartados = 0
    let repetidos = 0
    for (const crudo of lista) {
      const punto = normalizarPunto(crudo)
      if (!punto) {
        descartados++
        continue
      }
      if (punto.idLocal) {
        if (vistos.has(punto.idLocal)) {
          repetidos++
          continue
        }
        vistos.add(punto.idLocal)
      }
      validos.push(punto)
    }

    const evaluados = []
    for (const punto of validos) {
      const evaluacion = await evaluar({ lat: punto.latitud, lng: punto.longitud, clienteCodigo: punto.clienteCodigo })
      evaluados.push({ punto, evaluacion })
    }

    let guardados = 0
    for (let i = 0; i < evaluados.length; i += PUNTOS_POR_LOTE) {
      const lote = evaluados.slice(i, i + PUNTOS_POR_LOTE)
      try {
        guardados += await insertarLote(usuario, lote)
      } catch (e) {
        if (e.number !== 2601 && e.number !== 2627) throw e
        for (const item of lote) {
          try {
            guardados += await insertarLote(usuario, [item])
          } catch (e2) {
            if (e2.number !== 2601 && e2.number !== 2627) throw e2
          }
        }
      }
    }

    return {
      recibidos: lista.length,
      guardados,
      duplicados: evaluados.length - guardados + repetidos,
      descartados,
      simuladas: validos.filter((p) => p.simulada).length,
      radioM,
      puntos: evaluados.map(({ punto, evaluacion }) => ({
        idLocal: punto.idLocal,
        origen: punto.origen,
        simulada: punto.simulada,
        clienteCodigo: evaluacion ? evaluacion.clienteCodigo : punto.clienteCodigo,
        enCliente: evaluacion ? evaluacion.enCliente : null,
        distanciaM: evaluacion ? evaluacion.distanciaM : null,
      })),
    }
  }

  async function recorrido(usuarioCodigo, fecha) {
    await asegurarTabla()
    const req = getPedidosPool().request().input("u", sql.NVarChar, usuarioCodigo)
    let filtroFecha = "fecha_captura >= CAST(GETDATE() AS DATE) AND fecha_captura < DATEADD(day, 1, CAST(GETDATE() AS DATE))"
    if (fecha) {
      req.input("f", sql.VarChar, fecha)
      filtroFecha = "fecha_captura >= CONVERT(DATE, @f) AND fecha_captura < DATEADD(day, 1, CONVERT(DATE, @f))"
    }
    const r = await req.query(`
      SELECT TOP 3000 id, latitud, longitud, precision_m, velocidad_ms, simulada, origen, cliente_codigo,
             distancia_cliente_m, en_cliente, visita_id, usuario_nombre,
             CONVERT(VARCHAR(19), fecha_captura, 120) AS fecha
      FROM dbo.ubicaciones_recorrido
      WHERE usuario_codigo = @u AND ${filtroFecha}
      ORDER BY fecha_captura, id
    `)
    const nombre = r.recordset.length ? r.recordset[r.recordset.length - 1].usuario_nombre : null
    return { nombre, puntos: r.recordset.map(filaPunto) }
  }

  async function usuariosDelDia(fecha) {
    await asegurarTabla()
    const req = getPedidosPool().request()
    let filtroFecha = "fecha_captura >= CAST(GETDATE() AS DATE) AND fecha_captura < DATEADD(day, 1, CAST(GETDATE() AS DATE))"
    if (fecha) {
      req.input("f", sql.VarChar, fecha)
      filtroFecha = "fecha_captura >= CONVERT(DATE, @f) AND fecha_captura < DATEADD(day, 1, CONVERT(DATE, @f))"
    }
    const r = await req.query(`
      SELECT usuario_codigo,
             MAX(usuario_nombre) AS usuario_nombre,
             MAX(tipo_usuario) AS tipo_usuario,
             COUNT(*) AS puntos,
             SUM(CASE WHEN simulada = 1 THEN 1 ELSE 0 END) AS simuladas,
             SUM(CASE WHEN en_cliente = 1 THEN 1 ELSE 0 END) AS en_cliente,
             CONVERT(VARCHAR(19), MIN(fecha_captura), 120) AS primera,
             CONVERT(VARCHAR(19), MAX(fecha_captura), 120) AS ultima
      FROM dbo.ubicaciones_recorrido
      WHERE ${filtroFecha}
      GROUP BY usuario_codigo
      ORDER BY SUM(CASE WHEN simulada = 1 THEN 1 ELSE 0 END) DESC, MAX(usuario_nombre)
    `)
    return r.recordset.map((f) => ({
      usuarioCodigo: f.usuario_codigo,
      usuarioNombre: (f.usuario_nombre || "").toString().trim(),
      tipo: f.tipo_usuario || "",
      puntos: Number(f.puntos) || 0,
      simuladas: Number(f.simuladas) || 0,
      enCliente: Number(f.en_cliente) || 0,
      primera: f.primera,
      ultima: f.ultima,
    }))
  }

  function registrarRutas(app, { requireAuth, requireSoporte }) {
    app.post("/api/ubicaciones", requireAuth, async (req, res) => {
      try {
        const b = req.body || {}
        const usuario = usuarioDeSesion(req.user, b.idServicio)
        if (!usuario.codigo) return res.status(401).json({ success: false, message: "Sesión sin usuario identificable" })
        const crudos = Array.isArray(b.puntos) ? b.puntos : b.latitud != null || b.lat != null ? [b] : []
        const data = await registrarPuntos(usuario, crudos)
        if (data.simuladas > 0) {
          logger.error(`Ubicacion simulada reportada por ${usuario.codigo} (${usuario.nombre || "-"}): ${data.simuladas} punto(s)`)
        }
        res.json({ success: true, data })
      } catch (error) {
        logger.error("Error registrando ubicaciones:", error.message)
        res.status(500).json({ success: false, message: "No se pudieron registrar las ubicaciones" })
      }
    })

    app.get("/api/ubicaciones/en-cliente", requireAuth, async (req, res) => {
      try {
        const cliente = texto(req.query.cliente, 50)
        const lat = numero(req.query.lat)
        const lng = numero(req.query.lng)
        if (!cliente) return res.status(400).json({ success: false, message: "Cliente requerido" })
        if (!coordenadaValida(lat, lng)) return res.status(400).json({ success: false, message: "Coordenadas inválidas" })
        const data = await evaluar({ lat, lng, clienteCodigo: cliente })
        if (!data) return res.status(503).json({ success: false, message: "No se pudo evaluar la ubicación del cliente" })
        res.json({ success: true, data })
      } catch (error) {
        logger.error("Error evaluando ubicacion en cliente:", error.message)
        res.status(500).json({ success: false, message: "No se pudo evaluar la ubicación del cliente" })
      }
    })

    app.get("/api/ubicaciones/recorrido", requireAuth, async (req, res) => {
      try {
        const propio = codigoDeSesion(req.user)
        const solicitado = texto(req.query.usuario, 50)
        const esSoporte = !!(req.user && req.user.rol === "soporte")
        if (solicitado && solicitado !== propio && !esSoporte) {
          return res.status(403).json({ success: false, message: "Solo puedes consultar tu propio recorrido" })
        }
        const usuario = solicitado || propio
        if (!usuario) return res.json({ success: true, data: [], resumen: resumenRecorrido([]), radioM })
        const fecha = fechaValida(req.query.fecha)
        const { nombre, puntos } = await recorrido(usuario, fecha)
        res.json({
          success: true,
          usuario: { codigo: usuario, nombre: nombre || (usuario === propio && req.user ? req.user.nombre || "" : "") },
          fecha,
          radioM,
          data: puntos,
          resumen: resumenRecorrido(puntos),
        })
      } catch (error) {
        logger.error("Error consultando recorrido:", error.message)
        res.status(500).json({ success: false, message: "No se pudo cargar el recorrido", data: [] })
      }
    })

    app.get("/api/ubicaciones/usuarios", requireSoporte, async (req, res) => {
      try {
        const fecha = fechaValida(req.query.fecha)
        const data = await usuariosDelDia(fecha)
        res.json({
          success: true,
          fecha,
          data,
          total: data.length,
          conSimuladas: data.filter((u) => u.simuladas > 0).length,
        })
      } catch (error) {
        logger.error("Error listando usuarios con recorrido:", error.message)
        res.status(500).json({ success: false, message: "No se pudieron cargar los usuarios", data: [] })
      }
    })
  }

  return { registrarRutas, registrarPuntos, evaluar, asegurarTabla, radioM }
}

module.exports = {
  crear,
  usuarioDeSesion,
  normalizarPunto,
  distanciaMetros,
  coordenadaValida,
  resumenRecorrido,
}
