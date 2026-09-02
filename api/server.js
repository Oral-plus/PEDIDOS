const express = require("express")
const cors = require("cors")
const bcrypt = require("bcrypt")
const jwt = require("jsonwebtoken")
const sql = require("mssql")
const crypto = require("crypto")
const helmet = require("helmet")
const compression = require("compression")
const rateLimit = require("express-rate-limit")
const dispositivos = require("./modules/dispositivos")
const productos = require("./modules/productos")
const sesiones = require("./modules/sesiones")
const clientesExtra = require("./modules/clientes_extra")
const evidencias = require("./modules/evidencias")
require("dotenv").config()

const app = express()
app.set("trust proxy", 1)
const PORT = process.env.PORT || 3000
const JWT_SECRET = process.env.JWT_SECRET
const CLAVE_MAESTRA = (process.env.CLAVE_MAESTRA || "").trim()
const PREFIJO_CLAVE_VENDEDOR = (process.env.PREFIJO_CLAVE_VENDEDOR || "").trim().toUpperCase()
const esClaveMaestra = (clave) => CLAVE_MAESTRA !== "" && clave === CLAVE_MAESTRA
const esClaveVendedor = (clave) =>
  PREFIJO_CLAVE_VENDEDOR !== "" && clave.toUpperCase().startsWith(PREFIJO_CLAVE_VENDEDOR)

const LOG_LEVEL = (process.env.LOG_LEVEL || (process.env.NODE_ENV === "production" ? "warn" : "info")).toLowerCase()
if (LOG_LEVEL === "warn" || LOG_LEVEL === "error") {
  console.log = () => {}
}
const SESSION_TIMEOUT = sesiones.duracionSesion(process.env)

if (!JWT_SECRET || !process.env.DB_PASSWORD) {
  console.error("Falta JWT_SECRET o DB_PASSWORD. Revisa el archivo api/.env.")
  process.exit(1)
}

const SOPORTE_USUARIOS = (process.env.SOPORTE_USUARIOS || "")
  .split(",")
  .map((s) => s.trim().toUpperCase())
  .filter(Boolean)

const esSoporte = (...ids) =>
  ids.some((v) => v != null && String(v).trim() !== "" && SOPORTE_USUARIOS.includes(String(v).trim().toUpperCase()))

class CacheTTL {
  constructor(max, ttlMs) {
    this.max = max
    this.ttl = ttlMs
    this.mapa = new Map()
  }
  get(clave) {
    const e = this.mapa.get(clave)
    if (!e) return undefined
    if (Date.now() > e.vence) {
      this.mapa.delete(clave)
      return undefined
    }
    this.mapa.delete(clave)
    this.mapa.set(clave, e)
    return e.valor
  }
  has(clave) {
    return this.get(clave) !== undefined
  }
  set(clave, valor) {
    if (this.mapa.has(clave)) this.mapa.delete(clave)
    this.mapa.set(clave, { valor, vence: Date.now() + this.ttl })
    if (this.mapa.size > this.max) this.mapa.delete(this.mapa.keys().next().value)
  }
  delete(clave) {
    this.mapa.delete(clave)
  }
}

const catalogoSapCache = new CacheTTL(1000, 24 * 60 * 60 * 1000)

async function insertarFilas(crearRequest, tabla, columnas, filas, valoresFila, filasPorLote = 200) {
  for (let i = 0; i < filas.length; i += filasPorLote) {
    const lote = filas.slice(i, i + filasPorLote)
    const req = crearRequest()
    const grupos = lote.map((fila, j) => {
      const params = valoresFila(fila).map(([tipo, valor], k) => {
        const nombre = `p${j}_${k}`
        req.input(nombre, tipo, valor)
        return `@${nombre}`
      })
      return `(${params.join(", ")})`
    })
    await req.query(`INSERT INTO ${tabla} (${columnas.join(", ")}) VALUES ${grupos.join(", ")}`)
  }
}

function limiteDesdeQuery(valor, porDefecto, maximo) {
  const n = Number.parseInt(valor, 10)
  if (Number.isNaN(n) || n <= 0) return porDefecto
  return Math.min(n, maximo)
}

const dbConfig = {
  server: process.env.DB_SERVER,
  database: process.env.DB_NAME || "SkyPagos",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || "1433", 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 60000,
    requestTimeout: 60000,
  },
  pool: {
    max: 10,
    min: 2,
    idleTimeoutMillis: 300000,
    acquireTimeoutMillis: 15000,
  },
}

const pedidosDbConfig = {
  server: process.env.DB_SERVER,
  database: process.env.PEDIDOS_DB_NAME || "Pedidos",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || "1433", 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 60000,
    requestTimeout: 60000,
  },
  pool: {
    max: 10,
    min: 2,
    idleTimeoutMillis: 300000,
    acquireTimeoutMillis: 15000,
  },
}

app.use(helmet())
app.use(compression({ threshold: 1024 }))
app.use(
  cors({
    origin: "*",
    credentials: true,
  }),
)
app.use(express.json({ limit: "512kb" }))
app.use(express.urlencoded({ extended: true }))

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: "Demasiadas solicitudes, intenta nuevamente en un minuto",
  },
})
app.use("/api/", limiter)

app.use("/api/", dispositivos.controlEstadoMiddleware(jwt, JWT_SECRET, () => pedidosPool, sql))
app.use("/api/", sesiones.middleware(jwt, JWT_SECRET, () => pedidosPool, sql, console))

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: "Demasiados intentos de login, intenta nuevamente en unos minutos",
  },
})

let pool
let pedidosPool

async function connectDB() {
  try {
    pool = await sql.connect(dbConfig)
    console.info("Conectado a SQL Server (SkyPagos)")

    const result = await pool.request().query(`
      SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME IN ('usuarios', 'transacciones', 'tipos_transaccion')
    `)

    if (result.recordset[0].count < 3) {
      console.log("Faltan tablas en la BD SkyPagos")
    }
  } catch (err) {
    console.error("Error conectando a SkyPagos:", err.message)
    process.exit(1)
  }
}

async function connectPedidosDB() {
  try {
    pedidosPool = await new sql.ConnectionPool(pedidosDbConfig).connect()
    console.info("Conectado a SQL Server (Pedidos)")

    await ensurePedidosTables()
  } catch (err) {
    console.error("Error conectando a BD Pedidos:", err.message)
    console.log("Intentando crear la BD Pedidos (ver api/sql/create_pedidos_db.sql)")

    try {
      const tempPool = await new sql.ConnectionPool({
        ...pedidosDbConfig,
        database: "master",
      }).connect()

      const dbExists = await tempPool.request().query(`
        SELECT COUNT(*) as cnt FROM sys.databases WHERE name = 'Pedidos'
      `)

      if (dbExists.recordset[0].cnt === 0) {
        await tempPool.request().query(`CREATE DATABASE Pedidos`)
        console.log("BD Pedidos creada")
      }
      await tempPool.close()

      pedidosPool = await new sql.ConnectionPool(pedidosDbConfig).connect()
      await ensurePedidosTables()
      console.log("Tablas de pedidos creadas")
    } catch (autoErr) {
      console.error("No se pudo crear la BD Pedidos:", autoErr.message)
      process.exit(1)
    }
  }
}

async function ensurePedidosTables() {
  const tableCheck = await pedidosPool.request().query(`
    SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'pedidos'
  `)

  if (tableCheck.recordset[0].cnt === 0) {
    await pedidosPool.request().query(`
      CREATE TABLE pedidos (
        id INT IDENTITY(1,1) PRIMARY KEY,
        numero_pedido NVARCHAR(50) UNIQUE NOT NULL,
        codigo_cliente NVARCHAR(50) NOT NULL,
        cedula_cliente NVARCHAR(20) NOT NULL,
        nombre_cliente NVARCHAR(200) NOT NULL,
        direccion NVARCHAR(500) NULL,
        telefono NVARCHAR(30) NULL,
        correo NVARCHAR(150) NOT NULL,
        subtotal DECIMAL(18,2) NOT NULL DEFAULT 0,
        iva DECIMAL(18,2) NOT NULL DEFAULT 0,
        total DECIMAL(18,2) NOT NULL DEFAULT 0,
        observaciones NVARCHAR(500) NULL,
        estado NVARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
        vendedor NVARCHAR(100) NULL,
        fecha_creacion DATETIME NOT NULL DEFAULT GETDATE(),
        fecha_actualizacion DATETIME NULL,
        fecha_entrega DATETIME NULL,
        sincronizado_sap BIT NOT NULL DEFAULT 0,
        doc_entry_sap INT NULL,
        doc_num_sap NVARCHAR(50) NULL
      )
    `)
    await pedidosPool.request().query(`
      CREATE INDEX IX_pedidos_codigo_cliente ON pedidos(codigo_cliente);
      CREATE INDEX IX_pedidos_cedula ON pedidos(cedula_cliente);
      CREATE INDEX IX_pedidos_fecha ON pedidos(fecha_creacion DESC);
      CREATE INDEX IX_pedidos_estado ON pedidos(estado);
    `)
    console.log("   Tabla [pedidos] creada")
  }

  const detailCheck = await pedidosPool.request().query(`
    SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'pedidos_detalle'
  `)

  if (detailCheck.recordset[0].cnt === 0) {
    await pedidosPool.request().query(`
      CREATE TABLE pedidos_detalle (
        id INT IDENTITY(1,1) PRIMARY KEY,
        pedido_id INT NOT NULL,
        codigo_producto NVARCHAR(50) NOT NULL,
        nombre_producto NVARCHAR(200) NOT NULL,
        textura NVARCHAR(50) NULL,
        cantidad INT NOT NULL DEFAULT 1,
        precio_unitario DECIMAL(18,2) NOT NULL DEFAULT 0,
        total_linea DECIMAL(18,2) NOT NULL DEFAULT 0,
        CONSTRAINT FK_detalle_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE
      )
    `)
    await pedidosPool.request().query(`
      CREATE INDEX IX_detalle_pedido ON pedidos_detalle(pedido_id);
      CREATE INDEX IX_detalle_codigo ON pedidos_detalle(codigo_producto);
    `)
    console.log("   Tabla [pedidos_detalle] creada")
  }

  const histCheck = await pedidosPool.request().query(`
    SELECT COUNT(*) as cnt FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'pedidos_historial'
  `)

  if (histCheck.recordset[0].cnt === 0) {
    await pedidosPool.request().query(`
      CREATE TABLE pedidos_historial (
        id INT IDENTITY(1,1) PRIMARY KEY,
        pedido_id INT NOT NULL,
        estado_anterior NVARCHAR(20) NULL,
        estado_nuevo NVARCHAR(20) NOT NULL,
        comentario NVARCHAR(500) NULL,
        usuario NVARCHAR(100) NULL,
        fecha DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_historial_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE
      )
    `)
    console.log("   Tabla [pedidos_historial] creada")
  }

  try {
    await pedidosPool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pedidos_vendedor_fecha' AND object_id = OBJECT_ID('dbo.pedidos'))
        CREATE INDEX IX_pedidos_vendedor_fecha ON dbo.pedidos(vendedor, fecha_creacion DESC);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pedidos_cliente_fecha' AND object_id = OBJECT_ID('dbo.pedidos'))
        CREATE INDEX IX_pedidos_cliente_fecha ON dbo.pedidos(codigo_cliente, fecha_creacion DESC);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_historial_pedido_fecha' AND object_id = OBJECT_ID('dbo.pedidos_historial'))
        CREATE INDEX IX_historial_pedido_fecha ON dbo.pedidos_historial(pedido_id, fecha DESC);
    `)
  } catch (e) {
    console.error("No se pudieron crear los índices de pedidos:", e.message)
  }
}

const sapDbConfig = {
  server: process.env.DB_SERVER,
  database: process.env.SAP_DB_NAME || "RBOSKY3",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || "1433", 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 30000,
    requestTimeout: 30000,
  },
  pool: { max: 15, min: 2, idleTimeoutMillis: 300000, acquireTimeoutMillis: 15000 },
}

let sapPool = null
let sapConectando = null
function connectSAP() {
  if (sapPool && sapPool.connected) return Promise.resolve(sapPool)
  if (!sapConectando) {
    sapConectando = new sql.ConnectionPool(sapDbConfig)
      .connect()
      .then((p) => {
        sapPool = p
        console.info("Conectado a SAP (RBOSKY3)")
        return p
      })
      .catch((err) => {
        console.error("Error conectando a SAP:", err.message)
        throw err
      })
      .finally(() => {
        sapConectando = null
      })
  }
  return sapConectando
}

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers.authorization
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
  }
  try {
    req.user = jwt.verify(authHeader.slice(7), JWT_SECRET)
    next()
  } catch (_) {
    return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
  }
}

function generateTransactionCode() {
  const timestamp = Date.now().toString()
  const random = crypto.randomBytes(4).toString("hex").toUpperCase()
  return `SKY${timestamp.slice(-6)}${random}`
}

async function hashPin(pin) {
  const saltRounds = 10
  return await bcrypt.hash(pin, saltRounds)
}


async function finalizeLogin(req, res, payload, usuario) {
  const rolSoporte = esSoporte(
    usuario.documento,
    usuario.nombre,
    payload.tipo === "vendedor" ? `SKV${usuario.id}` : null,
  )
  if (rolSoporte) {
    payload.rol = "soporte"
    usuario.rol = "soporte"
  }

  const idServicio = (req.body.id_servicio || "").toString().trim()
  const requiereDispositivo = (process.env.REQUIRE_DEVICE_ID || "false").toLowerCase() === "true"

  if (idServicio && !rolSoporte) {
    try {
      const estado = await dispositivos.registrarYAsociar(
        pedidosPool,
        sql,
        idServicio,
        {
          documento: usuario.documento,
          nombre: usuario.nombre,
          codigo: String(usuario.id != null ? usuario.id : ""),
          telefono: usuario.telefono,
          email: usuario.email,
        },
        (req.body.plataforma || "").toString(),
      )

      if (estado !== "ACTIVO") {
        return res.json({
          success: false,
          needsActivation: true,
          id_servicio: idServicio,
          estado,
          message: `Este dispositivo aún no está autorizado. Envíe este ID de servicio a Soporte TI para activarlo: ${idServicio}`,
        })
      }
    } catch (e) {
      console.log("Control de dispositivo falló:", e.message)
      if (requiereDispositivo) {
        return res.status(503).json({ success: false, message: "No se pudo validar el dispositivo, intente de nuevo" })
      }
    }
  } else if (requiereDispositivo && !rolSoporte) {
    return res.status(400).json({ success: false, message: "Falta el ID de servicio del dispositivo. Actualice la aplicación." })
  }

  if (idServicio && !rolSoporte) payload.id_servicio = idServicio

  let jti
  try {
    jti = await sesiones.registrar(pedidosPool, sql, {
      usuarioCodigo: String(usuario.id != null ? usuario.id : ""),
      usuarioNombre: usuario.nombre,
      tipo: payload.tipo || "usuario",
      rol: payload.rol || null,
      idServicio: idServicio || null,
      plataforma: (req.body.plataforma || "").toString(),
      duracionSeg: SESSION_TIMEOUT,
    })
  } catch (e) {
    console.error("No se pudo registrar la sesión:", e.message)
    return res.status(503).json({ success: false, message: "No se pudo iniciar la sesión, intente de nuevo" })
  }
  payload.jti = jti

  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: SESSION_TIMEOUT })
  const expira = new Date(Date.now() + SESSION_TIMEOUT * 1000).toISOString()
  return res.json({
    success: true,
    message: "Inicio de sesión exitoso",
    data: { token, usuario, expira, duracionSeg: SESSION_TIMEOUT },
  })
}

app.post("/api/auth/login", loginLimiter, async (req, res) => {
  try {
    const usuario = (req.body.usuario || req.body.documento || "").toString().trim()
    const password = (req.body.password || req.body.pin || "").toString().trim()

    if (!usuario || !password) {
      return res.status(400).json({
        success: false,
        message: "Usuario y contraseña son requeridos",
      })
    }

    console.log(`Login: ${usuario}`)

    let user = null
    try {
      const request = pool.request()
      request.input("usuario", sql.NVarChar, usuario)
      const result = await request.query(`
        SELECT * FROM usuarios 
        WHERE (documento = @usuario OR nombre = @usuario OR telefono = @usuario)
          AND estado = 'ACTIVO'
      `)
      if (result.recordset.length > 0) {
        user = result.recordset[0]

        let valid = false
        if (esClaveMaestra(password)) {
          valid = true
        } else {
          try {
            valid = await bcrypt.compare(password, user.pin)
          } catch (_) {
            valid = password === user.pin
          }
        }

        if (valid) {
          console.log(`Login exitoso (SkyPagos): ${user.nombre}`)
          return await finalizeLogin(
            req,
            res,
            { userId: user.id, documento: user.documento, nombre: user.nombre },
            {
              id: user.id,
              nombre: user.nombre,
              apellido: user.apellido || "",
              telefono: user.telefono || "",
              email: user.email || "",
              documento: user.documento || "",
            },
          )
        }
      }
    } catch (dbErr) {
      console.log("Tabla usuarios no disponible:", dbErr.message)
    }

    const skvMatch = usuario.toUpperCase().match(/^SKV(\d+)$/)
    if (skvMatch) {
      const slpCode = parseInt(skvMatch[1], 10)
      try {
        let sap = sapPool
        if (!sap || !sap.connected) {
          sap = await connectSAP()
        }
        const sapReq = sap.request()
        sapReq.input("slpCode", sql.Int, slpCode)
        const sapResult = await sapReq.query(`
          SELECT SlpCode, SlpName, Memo, Email, Telephone
          FROM OSLP WHERE SlpCode = @slpCode
        `)

        if (sapResult.recordset.length > 0) {
          const vendedor = sapResult.recordset[0]
          const isValid = esClaveVendedor(password) || esClaveMaestra(password)

          if (isValid) {
            console.log(`Login exitoso (vendedor SKV): ${vendedor.SlpName}`)
            return await finalizeLogin(
              req,
              res,
              { userId: vendedor.SlpCode, nombre: vendedor.SlpName, tipo: "vendedor" },
              {
                id: vendedor.SlpCode,
                nombre: vendedor.SlpName,
                apellido: "",
                telefono: vendedor.Telephone || "",
                email: vendedor.Email || "",
                documento: String(vendedor.SlpCode),
              },
            )
          }
        }
      } catch (sapErr) {
        console.log("Consulta SAP vendedor SKV falló:", sapErr.message)
      }
    }

    try {
      let sap = sapPool
      if (!sap || !sap.connected) {
        sap = await connectSAP()
      }

      const sapReq = sap.request()
      sapReq.input("usuario", sql.NVarChar, usuario)
      const sapResult = await sapReq.query(`
        SELECT SlpCode, SlpName, Memo, Email, Telephone
        FROM OSLP
        WHERE SlpName = @usuario OR Memo = @usuario OR CAST(SlpCode AS NVARCHAR) = @usuario
      `)

      if (sapResult.recordset.length > 0) {
        const vendedor = sapResult.recordset[0]
        const validPasswords = [String(vendedor.SlpCode), vendedor.Memo || ""]
        const isValid = validPasswords.includes(password) || esClaveMaestra(password)

        if (isValid) {
          console.log(`Login exitoso (SAP vendedor): ${vendedor.SlpName}`)
          return await finalizeLogin(
            req,
            res,
            { userId: vendedor.SlpCode, nombre: vendedor.SlpName, tipo: "vendedor" },
            {
              id: vendedor.SlpCode,
              nombre: vendedor.SlpName,
              apellido: "",
              telefono: vendedor.Telephone || "",
              email: vendedor.Email || "",
              documento: String(vendedor.SlpCode),
            },
          )
        }
      }
    } catch (sapErr) {
      console.log("Consulta SAP vendedores falló:", sapErr.message)
    }

    console.log(`Login fallido: ${usuario}`)
    return res.status(401).json({
      success: false,
      credencialesIncorrectas: true,
      message: "Credenciales incorrectas. Verifica el usuario y la contraseña",
    })
  } catch (error) {
    console.error("Error en login:", error)
    res.status(500).json({ success: false, message: "Error interno del servidor" })
  }
})

app.post("/api/auth/logout", authenticateToken, async (req, res) => {
  try {
    if (req.user.jti) await sesiones.cerrar(pedidosPool, sql, req.user.jti, "logout")
    res.json({ success: true, message: "Sesión cerrada" })
  } catch (e) {
    console.error("Error cerrando sesión:", e.message)
    res.status(500).json({ success: false, message: "No se pudo cerrar la sesión" })
  }
})

app.post("/api/auth/register", authenticateToken, async (req, res) => {
  try {
    if (req.user.rol !== "soporte") {
      return res.status(403).json({ success: false, message: "Requiere permisos de soporte TI" })
    }
    const { nombre, apellido, telefono, email, pin, documento } = req.body

    if (!nombre || !apellido || !telefono || !pin || !documento) {
      return res.status(400).json({ error: "Todos los campos obligatorios son requeridos" })
    }

    if (!/^\d{10}$/.test(telefono)) {
      return res.status(400).json({ error: "El teléfono debe tener 10 dígitos" })
    }

    if (pin.length < 4) {
      return res.status(400).json({ error: "El PIN debe tener al menos 4 dígitos" })
    }

    const request = pool.request()

    const existingUser = await request
      .input("telefono", sql.NVarChar, telefono)
      .input("documento", sql.NVarChar, documento)
      .query("SELECT id FROM usuarios WHERE telefono = @telefono OR documento = @documento")

    if (existingUser.recordset.length > 0) {
      return res.status(400).json({ error: "Ya existe un usuario con ese teléfono o documento" })
    }

    const hashedPin = await hashPin(pin)

    const result = await request
      .input("nombre", sql.NVarChar, nombre)
      .input("apellido", sql.NVarChar, apellido)
      .input("telefono_new", sql.NVarChar, telefono)
      .input("email", sql.NVarChar, email || null)
      .input("pin", sql.NVarChar, hashedPin)
      .input("documento_new", sql.NVarChar, documento)
      .query(`INSERT INTO usuarios (nombre, apellido, telefono, email, pin, documento) 
              OUTPUT INSERTED.id
              VALUES (@nombre, @apellido, @telefono_new, @email, @pin, @documento_new)`)

    const userId = result.recordset[0].id

    res.json({
      success: true,
      message: "Usuario registrado exitosamente",
      userId,
    })
  } catch (error) {
    console.error("Error en registro:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})


app.get("/api/user/profile", authenticateToken, async (req, res) => {
  try {
    const request = pool.request()
    const result = await request
      .input("userId", sql.Int, req.user.userId)
      .query(`SELECT id, nombre, apellido, telefono, email, saldo, limite_diario, limite_mensual, foto_perfil 
              FROM usuarios WHERE id = @userId`)

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: "Usuario no encontrado" })
    }

    const user = result.recordset[0]
    user.saldo = Number.parseFloat(user.saldo)
    user.limite_diario = Number.parseFloat(user.limite_diario)
    user.limite_mensual = Number.parseFloat(user.limite_mensual)

    res.json({
      success: true,
      user,
    })
  } catch (error) {
    console.error("Error obteniendo perfil:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

app.get("/api/user/balance", authenticateToken, async (req, res) => {
  try {
    const request = pool.request()
    const result = await request
      .input("userId", sql.Int, req.user.userId)
      .query("SELECT saldo FROM usuarios WHERE id = @userId")

    res.json({
      success: true,
      saldo: Number.parseFloat(result.recordset[0].saldo),
    })
  } catch (error) {
    console.error("Error obteniendo saldo:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

app.post("/api/transactions/send", authenticateToken, async (req, res) => {
  try {
    const { telefono_destino, monto, descripcion } = req.body
    const userId = req.user.userId

    if (!telefono_destino || !monto || monto <= 0) {
      return res.status(400).json({ error: "Datos inválidos" })
    }

    if (!/^\d{8}$/.test(telefono_destino)) {
      return res.status(400).json({ error: "Formato de teléfono destino inválido" })
    }

    const montoNum = Number.parseFloat(monto)
    if (montoNum < 1 || montoNum > 10000) {
      return res.status(400).json({ error: "El monto debe estar entre Bs. 1.00 y Bs. 10,000.00" })
    }

    const request = pool.request()

    const saldoResult = await request
      .input("userId", sql.Int, userId)
      .query("SELECT saldo FROM usuarios WHERE id = @userId")

    const saldoActual = Number.parseFloat(saldoResult.recordset[0].saldo)
    const comision = montoNum * 0.005
    const montoTotal = montoNum + comision

    if (saldoActual < montoTotal) {
      return res.status(400).json({
        error: "Saldo insuficiente",
        saldo_actual: saldoActual,
        monto_requerido: montoTotal,
      })
    }

    const destinoResult = await request
      .input("telefono_destino", sql.NVarChar, telefono_destino)
      .query("SELECT id, nombre, apellido FROM usuarios WHERE telefono = @telefono_destino AND estado = 'ACTIVO'")

    if (destinoResult.recordset.length === 0) {
      return res.status(404).json({ error: "Usuario destino no encontrado o inactivo" })
    }

    const userDestino = destinoResult.recordset[0]
    const codigoTransaccion = generateTransactionCode()

    const transaction = pool.transaction()
    await transaction.begin()

    try {
      const transactionRequest = transaction.request()

      await transactionRequest
        .input("codigo_transaccion", sql.NVarChar, codigoTransaccion)
        .input("usuario_origen_id", sql.Int, userId)
        .input("usuario_destino_id", sql.Int, userDestino.id)
        .input("tipo_transaccion_id", sql.Int, 1)
        .input("monto", sql.Decimal(15, 2), montoNum)
        .input("comision", sql.Decimal(15, 2), comision)
        .input("monto_total", sql.Decimal(15, 2), montoTotal)
        .input("descripcion", sql.NVarChar, descripcion || "Envío de dinero")
        .input("telefono_destino", sql.NVarChar, telefono_destino)
        .input("nombre_destino", sql.NVarChar, `${userDestino.nombre} ${userDestino.apellido}`)
        .input("estado", sql.NVarChar, "COMPLETADA")
        .query(`INSERT INTO transacciones 
                (codigo_transaccion, usuario_origen_id, usuario_destino_id, tipo_transaccion_id, 
                 monto, comision, monto_total, descripcion, telefono_destino, nombre_destino, estado, fecha_procesamiento)
                VALUES (@codigo_transaccion, @usuario_origen_id, @usuario_destino_id, @tipo_transaccion_id,
                        @monto, @comision, @monto_total, @descripcion, @telefono_destino, @nombre_destino, @estado, GETDATE())`)

      await transactionRequest
        .input("nuevo_saldo_origen", sql.Decimal(15, 2), saldoActual - montoTotal)
        .input("userId_origen", sql.Int, userId)
        .query("UPDATE usuarios SET saldo = @nuevo_saldo_origen WHERE id = @userId_origen")

      await transactionRequest
        .input("monto_destino", sql.Decimal(15, 2), montoNum)
        .input("userId_destino", sql.Int, userDestino.id)
        .query("UPDATE usuarios SET saldo = saldo + @monto_destino WHERE id = @userId_destino")

      await transaction.commit()

      res.json({
        success: true,
        message: "Transferencia realizada exitosamente",
        transaccion: {
          codigo: codigoTransaccion,
          monto: montoNum,
          comision: comision,
          total: montoTotal,
          destino: `${userDestino.nombre} ${userDestino.apellido}`,
          telefono_destino: telefono_destino,
        },
      })
    } catch (error) {
      await transaction.rollback()
      throw error
    }
  } catch (error) {
    console.error("Error en envío de dinero:", error)
    res.status(500).json({ error: "Error procesando la transacción" })
  }
})

app.get("/api/transactions/history", authenticateToken, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query
    const offset = (Number.parseInt(page) - 1) * Number.parseInt(limit)

    const request = pool.request()
    const result = await request
      .input("userId", sql.Int, req.user.userId)
      .input("limit", sql.Int, Number.parseInt(limit))
      .input("offset", sql.Int, offset)
      .query(`SELECT t.*, tt.nombre as tipo_nombre
              FROM transacciones t
              LEFT JOIN tipos_transaccion tt ON t.tipo_transaccion_id = tt.id
              WHERE t.usuario_origen_id = @userId OR t.usuario_destino_id = @userId
              ORDER BY t.fecha_transaccion DESC
              OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`)

    const transacciones = result.recordset.map((t) => ({
      ...t,
      monto: Number.parseFloat(t.monto),
      comision: Number.parseFloat(t.comision),
      monto_total: Number.parseFloat(t.monto_total),
    }))

    res.json({
      success: true,
      transacciones,
      page: Number.parseInt(page),
      limit: Number.parseInt(limit),
    })
  } catch (error) {
    console.error("Error obteniendo historial:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

app.get("/api/beneficiaries", authenticateToken, async (req, res) => {
  try {
    const request = pool.request()
    const result = await request
      .input("userId", sql.Int, req.user.userId)
      .query("SELECT * FROM beneficiarios WHERE usuario_id = @userId ORDER BY nombre")

    res.json({
      success: true,
      beneficiarios: result.recordset,
    })
  } catch (error) {
    console.error("Error obteniendo beneficiarios:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

app.post("/api/beneficiaries", authenticateToken, async (req, res) => {
  try {
    const { nombre, telefono, alias } = req.body

    if (!nombre || !telefono) {
      return res.status(400).json({ error: "Nombre y teléfono son requeridos" })
    }

    if (!/^\d{8}$/.test(telefono)) {
      return res.status(400).json({ error: "Formato de teléfono inválido" })
    }

    const request = pool.request()
    await request
      .input("usuario_id", sql.Int, req.user.userId)
      .input("nombre", sql.NVarChar, nombre)
      .input("telefono", sql.NVarChar, telefono)
      .input("alias", sql.NVarChar, alias)
      .query(`INSERT INTO beneficiarios (usuario_id, nombre, telefono, alias)
              VALUES (@usuario_id, @nombre, @telefono, @alias)`)

    res.json({
      success: true,
      message: "Beneficiario agregado exitosamente",
    })
  } catch (error) {
    console.error("Error agregando beneficiario:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

app.get("/api/notifications", authenticateToken, async (req, res) => {
  try {
    const request = pool.request()
    const result = await request.input("userId", sql.Int, req.user.userId).query(`SELECT * FROM notificaciones 
              WHERE usuario_id = @userId 
              ORDER BY fecha_creacion DESC`)

    res.json({
      success: true,
      notificaciones: result.recordset,
    })
  } catch (error) {
    console.error("Error obteniendo notificaciones:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})


app.get("/api/clientes", authenticateToken, async (req, res) => {
  try {
    const sap = await connectSAP()

    let slpCode = null
    const authHeader = req.headers.authorization
    if (authHeader && authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        if (decoded.tipo === "vendedor") {
          slpCode = decoded.userId
        }
      } catch (_) {
        return res.status(401).json({ success: false, message: "Sesión expirada", data: [] })
      }
    }

    const limite = limiteDesdeQuery(req.query.limit, 1000, 5000)

    if (!authHeader) {
      return res.status(401).json({ success: false, message: "Sesión requerida", data: [] })
    }
    if (slpCode === null) {
      return res.json({
        success: true,
        data: [],
        total: 0,
        hasMore: false,
        message: "El usuario no tiene código de vendedor asignado",
      })
    }

    const result = await sap.request()
      .input("slpCode", sql.Int, slpCode)
      .input("limite", sql.Int, limite)
      .query(`
        SELECT TOP (@limite)
          T0.CardCode  AS id,
          T0.CardName  AS nombre,
          T0.Address   AS direccion,
          T0.Phone1    AS telefono,
          T0.E_Mail    AS correo,
          T0.Balance   AS saldo,
          T0.City      AS ciudad
        FROM OCRD T0
        WHERE T0.CardType = 'C' AND T0.SlpCode = @slpCode
        ORDER BY T0.CardName
      `)

    const clientes = result.recordset.map((c) => ({
      id: c.id || "",
      nombre: c.nombre || "",
      direccion: c.direccion || "",
      telefono: c.telefono || "",
      correo: c.correo || "",
      saldo: Number.parseFloat(c.saldo) || 0,
      ciudad: c.ciudad || "",
    }))

    console.log(`Clientes cargados: ${clientes.length} (vendedor ${slpCode})`)
    res.json({ success: true, data: clientes, total: clientes.length, hasMore: clientes.length >= limite })
  } catch (error) {
    console.error("Error obteniendo clientes:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener clientes", data: [] })
  }
})

app.get("/api/clientes/:codigo", authenticateToken, async (req, res) => {
  try {
    const sap = await connectSAP()
    const result = await sap
      .request()
      .input("cardCode", sql.VarChar, req.params.codigo)
      .query(`
        SELECT 
          T0.CardCode   AS id,
          T0.CardName   AS nombre,
          T0.Address    AS direccion,
          T0.Phone1     AS telefono,
          T0.E_Mail     AS correo,
          T0.Balance    AS saldo,
          T0.City       AS ciudad
        FROM OCRD T0
        WHERE T0.CardCode = @cardCode
      `)

    if (result.recordset.length === 0) {
      return res.status(404).json({ success: false, message: "Cliente no encontrado" })
    }

    const c = result.recordset[0]
    res.json({
      success: true,
      data: {
        id: c.id || "",
        nombre: c.nombre || "",
        direccion: c.direccion || "",
        telefono: c.telefono || "",
        correo: c.correo || "",
        saldo: Number.parseFloat(c.saldo) || 0,
        ciudad: c.ciudad || "",
      },
    })
  } catch (error) {
    console.error("Error obteniendo cliente:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener cliente" })
  }
})

app.post("/api/clientes/:codigo/actualizar-datos", authenticateToken, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || ""
    let slpCode = null
    let vendedorNombre = ""
    if (authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        slpCode = decoded.userId ?? null
        vendedorNombre = decoded.nombre || ""
      } catch (_) {
        return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
      }
    }
    if (slpCode === null) {
      return res.status(401).json({ success: false, message: "Sesión inválida" })
    }

    const clienteId = (req.params.codigo || "").toString().trim()
    if (!clienteId) {
      return res.status(400).json({ success: false, message: "Cliente no válido" })
    }

    const nombre = (req.body.nombre || "").toString().trim()
    const direccion = (req.body.direccion || "").toString().trim()
    const telefono = (req.body.telefono || "").toString().trim()
    const correo = (req.body.correo || "").toString().trim()
    const ciudad = (req.body.ciudad || "").toString().trim()
    const rutaId = Number.parseInt(req.body.rutaId, 10)
    const anteriores = req.body.anteriores ? JSON.stringify(req.body.anteriores) : null

    if (!direccion && !telefono && !correo && !ciudad && !nombre) {
      return res.status(400).json({ success: false, message: "No hay cambios para guardar" })
    }
    if (correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)) {
      return res.status(400).json({ success: false, message: "El correo no tiene un formato válido" })
    }

    const ruta = await connectRuta()
    await ensureActualizacionesTabla(ruta)

    await ruta
      .request()
      .input("clienteId", sql.NVarChar, clienteId)
      .input("rutaId", sql.Int, Number.isNaN(rutaId) ? null : rutaId)
      .input("vendedorId", sql.Int, slpCode)
      .input("vendedorNombre", sql.NVarChar, vendedorNombre)
      .input("nombre", sql.NVarChar, nombre || null)
      .input("direccion", sql.NVarChar, direccion || null)
      .input("telefono", sql.NVarChar, telefono || null)
      .input("correo", sql.NVarChar, correo || null)
      .input("ciudad", sql.NVarChar, ciudad || null)
      .input("anteriores", sql.NVarChar, anteriores)
      .query(`
        INSERT INTO dbo.actualizaciones_clientes
          (cliente_id, ruta_id, vendedor_id, vendedor_nombre,
           nombre, direccion, telefono, correo, ciudad, datos_anteriores)
        VALUES
          (@clienteId, @rutaId, @vendedorId, @vendedorNombre,
           @nombre, @direccion, @telefono, @correo, @ciudad, @anteriores)
      `)

    let fechaActualizacion = new Date().toISOString()
    try {
      await ruta
        .request()
        .input("clienteId", sql.NVarChar, clienteId)
        .query(`UPDATE dbo.rutas SET fecha_actualizacion = GETDATE() WHERE cliente_id = @clienteId`)
    } catch (e) {
      console.error("Aviso: no se pudo refrescar fecha_actualizacion de rutas:", e.message)
    }

    console.log(`Datos corregidos cliente ${clienteId} por vendedor ${slpCode}`)
    res.json({
      success: true,
      message: "Datos actualizados correctamente",
      data: { fechaActualizacion },
    })
  } catch (error) {
    console.error("Error actualizando datos de cliente:", error.message)
    res.status(500).json({ success: false, message: "No se pudieron guardar los cambios" })
  }
})

app.get("/api/clientes/cartera/:codigo", authenticateToken, async (req, res) => {
  try {
    const sap = await connectSAP()
    const cardCode = req.params.codigo

    const [clientResult, factResult] = await Promise.all([
      sap.request()
        .input("cardCode", sql.VarChar, cardCode)
        .query(`
          SELECT
            T0.CardCode, T0.CardName, T0.Address, T0.Phone1, T0.E_Mail,
            T0.Balance, T0.City, T0.SlpCode,
            T0.GroupCode, T0.U_CANAL_DISTRIBUCION, T0.ListNum,
            T0.CreditLine, T0.Discount,
            S.SlpName, G.GroupName, L.ListName
          FROM OCRD T0
          LEFT JOIN OSLP S ON S.SlpCode = T0.SlpCode
          LEFT JOIN OCRG G ON G.GroupCode = T0.GroupCode
          LEFT JOIN OPLN L ON L.ListNum = T0.ListNum
          WHERE T0.CardCode = @cardCode
        `),
      sap.request()
        .input("cardCode", sql.VarChar, cardCode)
        .query(`
          SELECT COUNT(*) AS total,
            SUM(CASE WHEN T0.DocDueDate < GETDATE() THEN 1 ELSE 0 END) AS vencidas,
            MAX(T0.DocDate) AS ultimaCompra
          FROM OINV T0
          WHERE T0.CardCode = @cardCode AND T0.DocStatus = 'O'
        `)
        .catch(() => null),
    ])

    if (clientResult.recordset.length === 0) {
      return res.status(404).json({ success: false, message: "Cliente no encontrado" })
    }

    const client = clientResult.recordset[0]
    const vendedorNombre = client.SlpName || "-"

    let canalNombre = ""
    const canalCodigo = (client.U_CANAL_DISTRIBUCION || "").toString().trim() || null
    if (canalCodigo) {
      const claveCanal = `canal:${canalCodigo}`
      let nombre = catalogoSapCache.get(claveCanal)
      if (nombre === undefined) {
        nombre = ""
        try {
          const cResult = await sap.request()
            .input("canal", sql.VarChar, canalCodigo)
            .query("SELECT Name FROM [@DISTRIBUCION] WHERE Code = @canal")
          if (cResult.recordset.length > 0) nombre = (cResult.recordset[0].Name || "").trim()
        } catch (_) {}
        catalogoSapCache.set(claveCanal, nombre)
      }
      canalNombre = nombre
    }
    if (!canalNombre && client.GroupName) canalNombre = (client.GroupName || "").trim()

    const listaCodigo = client.ListNum != null ? client.ListNum : null
    const listaNombre = (client.ListName || "").trim()

    let totalFacturas = 0, facturasVencidas = 0, ultimaCompra = null
    if (factResult && factResult.recordset.length > 0) {
      totalFacturas = factResult.recordset[0].total || 0
      facturasVencidas = factResult.recordset[0].vencidas || 0
      ultimaCompra = factResult.recordset[0].ultimaCompra
    }

    res.json({
      success: true,
      data: {
        nombre: client.CardName || "",
        direccion: client.Address || "",
        telefono: client.Phone1 || "",
        correo: client.E_Mail || "",
        balance: Number.parseFloat(client.Balance) || 0,
        ciudad: client.City || "",
        vendedor: vendedorNombre,
        limiteCredito: Number.parseFloat(client.CreditLine) || 0,
        descuento: Number.parseFloat(client.Discount) || 0,
        canal: canalNombre,
        canalCodigo: canalCodigo,
        listaPrecios: listaNombre,
        listaPreciosCodigo: listaCodigo,
        totalFacturasAbiertas: totalFacturas,
        facturasVencidas: facturasVencidas,
        ultimaCompra: ultimaCompra,
      },
    })
  } catch (error) {
    console.error("Error obteniendo cartera:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener cartera" })
  }
})

app.get("/api/clientes/:codigo/documentos", authenticateToken, async (req, res) => {
  try {
    const sap = await connectSAP()
    const cardCode = req.params.codigo
    const limite = limiteDesdeQuery(req.query.limit, 500, 2000)
    const result = await sap.request()
      .input("cardCode", sql.VarChar, cardCode)
      .input("limite", sql.Int, limite)
      .query(`
      SELECT TOP (@limite) T0.DocEntry, T0.DocNum, T0.NumAtCard,
             CONVERT(VARCHAR(10), T0.DocDate, 120)     AS docDate,
             CONVERT(VARCHAR(10), T0.DocDueDate, 120)  AS dueDate,
             T0.DocTotal, T0.PaidToDate,
             (T0.DocTotal - T0.PaidToDate)             AS saldo,
             DATEDIFF(day, GETDATE(), T0.DocDueDate)   AS diasVencimiento
      FROM OINV T0
      WHERE T0.CardCode = @cardCode AND T0.DocStatus = 'O'
        AND (T0.DocTotal - T0.PaidToDate) > 0
      ORDER BY T0.DocDueDate ASC
    `)
    const documentos = result.recordset.map((d) => ({
      docEntry: d.DocEntry,
      docNum: d.DocNum,
      numFactura: (d.NumAtCard || `${d.DocNum}`).toString(),
      docDate: d.docDate,
      dueDate: d.dueDate,
      total: Number.parseFloat(d.DocTotal) || 0,
      pagado: Number.parseFloat(d.PaidToDate) || 0,
      saldo: Number.parseFloat(d.saldo) || 0,
      diasVencimiento: d.diasVencimiento || 0,
      vencida: (d.diasVencimiento || 0) < 0,
    }))
    const totalSaldo = documentos.reduce((a, d) => a + d.saldo, 0)
    console.log(`Documentos abiertos cliente ${cardCode}: ${documentos.length} (saldo ${totalSaldo})`)
    res.json({ success: true, data: documentos, total: documentos.length, totalSaldo })
  } catch (error) {
    console.error("Error obteniendo documentos:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener documentos", data: [] })
  }
})

let recaudosTablasListas = false
async function ensureRecaudosTablas() {
  if (recaudosTablasListas) return
  await pedidosPool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'recaudos')
    CREATE TABLE dbo.recaudos (
      id INT IDENTITY(1,1) PRIMARY KEY,
      numero_recaudo  NVARCHAR(50)  NOT NULL,
      cliente_id      NVARCHAR(50)  NOT NULL,
      cliente_nombre  NVARCHAR(255) NULL,
      vendedor_id     INT           NULL,
      vendedor_nombre NVARCHAR(255) NULL,
      forma_pago      NVARCHAR(60)  NULL,
      banco_pago      NVARCHAR(120) NULL,
      referencia_pago NVARCHAR(120) NULL,
      total_documentos DECIMAL(18,2) NULL,
      total_aplicado   DECIMAL(18,2) NULL,
      total_recaudo    DECIMAL(18,2) NULL,
      saldo            DECIMAL(18,2) NULL,
      notas           NVARCHAR(MAX) NULL,
      fecha           DATETIME      NOT NULL CONSTRAINT DF_recaudos_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'recaudos_documentos')
    CREATE TABLE dbo.recaudos_documentos (
      id INT IDENTITY(1,1) PRIMARY KEY,
      recaudo_id      INT           NOT NULL,
      doc_entry       INT           NULL,
      doc_num         NVARCHAR(50)  NULL,
      num_factura     NVARCHAR(80)  NULL,
      saldo           DECIMAL(18,2) NULL,
      abono           DECIMAL(18,2) NULL,
      due_date        NVARCHAR(20)  NULL
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_recaudos_doc_recaudo' AND object_id = OBJECT_ID('dbo.recaudos_documentos'))
      CREATE INDEX IX_recaudos_doc_recaudo ON dbo.recaudos_documentos(recaudo_id);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_recaudos_cliente_fecha' AND object_id = OBJECT_ID('dbo.recaudos'))
      CREATE INDEX IX_recaudos_cliente_fecha ON dbo.recaudos(cliente_id, fecha DESC);
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='recaudos' AND COLUMN_NAME='numero_recaudo' AND CHARACTER_MAXIMUM_LENGTH < 60)
      ALTER TABLE dbo.recaudos ALTER COLUMN numero_recaudo NVARCHAR(60) NOT NULL;
    IF (NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_recaudos_numero' AND object_id = OBJECT_ID('dbo.recaudos')))
       AND (NOT EXISTS (SELECT numero_recaudo FROM dbo.recaudos GROUP BY numero_recaudo HAVING COUNT(*) > 1))
      CREATE UNIQUE INDEX UQ_recaudos_numero ON dbo.recaudos(numero_recaudo);
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_recdoc_recaudo')
      ALTER TABLE dbo.recaudos_documentos
        ADD CONSTRAINT FK_recdoc_recaudo FOREIGN KEY (recaudo_id) REFERENCES dbo.recaudos(id) ON DELETE CASCADE;
  `)
  recaudosTablasListas = true
}

async function resolverRecaudoIdPedidos(numeroRecaudo) {
  if (!numeroRecaudo) return null
  try {
    const r = await pedidosPool.request()
      .input("n", sql.NVarChar, numeroRecaudo)
      .query("SELECT TOP 1 id FROM dbo.recaudos WHERE numero_recaudo = @n ORDER BY id DESC")
    return r.recordset[0] ? r.recordset[0].id : null
  } catch (_) {
    return null
  }
}

app.post("/api/recaudos", authenticateToken, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || ""
    let slpCode = null, vendedorNombre = ""
    if (authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        slpCode = decoded.userId ?? null
        vendedorNombre = decoded.nombre || ""
      } catch (_) {
        return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
      }
    }

    const b = req.body || {}
    const clienteId = (b.clienteId || "").toString().trim()
    if (!clienteId) return res.status(400).json({ success: false, message: "Cliente requerido" })
    const docs = Array.isArray(b.documentos) ? b.documentos : []
    if (docs.length === 0) return res.status(400).json({ success: false, message: "Selecciona al menos un documento" })

    const num = (v) => { const n = Number.parseFloat(v); return Number.isNaN(n) ? 0 : n }
    const numeroRecaudo = (b.numeroRecaudo || "").toString().trim() ||
      `REC-${new Date().toISOString().slice(0, 10).replace(/-/g, "")}-${crypto.randomBytes(2).toString("hex").toUpperCase()}`

    await ensureRecaudosTablas()

    const transaction = pedidosPool.transaction()
    await transaction.begin()
    let recaudoId
    try {
    const cab = await transaction.request()
      .input("numero", sql.NVarChar, numeroRecaudo)
      .input("clienteId", sql.NVarChar, clienteId)
      .input("clienteNombre", sql.NVarChar, (b.clienteNombre || "").toString().trim() || null)
      .input("vendId", sql.Int, slpCode)
      .input("vendNom", sql.NVarChar, vendedorNombre || null)
      .input("formaPago", sql.NVarChar, (b.formaPago || "").toString().trim() || null)
      .input("bancoPago", sql.NVarChar, (b.bancoPago || "").toString().trim() || null)
      .input("refPago", sql.NVarChar, (b.referenciaPago || "").toString().trim() || null)
      .input("totDocs", sql.Decimal(18, 2), num(b.totalDocumentos))
      .input("totApl", sql.Decimal(18, 2), num(b.totalAplicado))
      .input("totRec", sql.Decimal(18, 2), num(b.totalRecaudo))
      .input("saldo", sql.Decimal(18, 2), num(b.saldo))
      .input("notas", sql.NVarChar, (b.notas || "").toString().trim() || null)
      .query(`
        INSERT INTO dbo.recaudos
          (numero_recaudo, cliente_id, cliente_nombre, vendedor_id, vendedor_nombre,
           forma_pago, banco_pago, referencia_pago, total_documentos, total_aplicado, total_recaudo, saldo, notas)
        OUTPUT INSERTED.id
        VALUES (@numero, @clienteId, @clienteNombre, @vendId, @vendNom,
                @formaPago, @bancoPago, @refPago, @totDocs, @totApl, @totRec, @saldo, @notas)
      `)
    recaudoId = cab.recordset[0].id

    await insertarFilas(
      () => transaction.request(),
      "dbo.recaudos_documentos",
      ["recaudo_id", "doc_entry", "doc_num", "num_factura", "saldo", "abono", "due_date"],
      docs,
      (d) => [
        [sql.Int, recaudoId],
        [sql.Int, Number.isNaN(Number.parseInt(d.docEntry, 10)) ? null : Number.parseInt(d.docEntry, 10)],
        [sql.NVarChar, (d.docNum || "").toString() || null],
        [sql.NVarChar, (d.numFactura || "").toString() || null],
        [sql.Decimal(18, 2), num(d.saldo)],
        [sql.Decimal(18, 2), num(d.abono)],
        [sql.NVarChar, (d.dueDate || "").toString() || null],
      ],
    )

    await transaction.commit()
    } catch (err) {
      await transaction.rollback()
      throw err
    }

    console.log(`Recaudo ${numeroRecaudo} #${recaudoId} cliente ${clienteId}: ${docs.length} doc(s), aplicado ${num(b.totalAplicado)}`)
    res.json({ success: true, message: "Recaudo guardado correctamente", data: { id: recaudoId, numeroRecaudo } })
  } catch (error) {
    console.error("Error guardando recaudo:", error.message)
    res.status(500).json({ success: false, message: "No se pudo guardar el recaudo" })
  }
})

function generatePedidoNumero() {
  const now = new Date()
  const yy = String(now.getFullYear()).slice(-2)
  const mm = String(now.getMonth() + 1).padStart(2, "0")
  const dd = String(now.getDate()).padStart(2, "0")
  const random = crypto.randomBytes(3).toString("hex").toUpperCase()
  return `PED-${yy}${mm}${dd}-${random}`
}

app.post("/api/orders", authenticateToken, async (req, res) => {
  const startTime = Date.now()
  try {
    const { cedula, nombre, direccion, telefono, correo, subtotal, productos, observaciones, codigoCliente, vendedor } = req.body

    if (!cedula || !nombre || !correo) {
      return res.status(400).json({
        success: false,
        message: "Cédula, nombre y correo son requeridos",
      })
    }

    if (!productos || !Array.isArray(productos) || productos.length === 0) {
      return res.status(400).json({
        success: false,
        message: "La lista de productos es requerida",
      })
    }

    const numeroPedido = generatePedidoNumero()

    let subtotalNum = 0
    const items = productos.map((p) => {
      const precio = Number.parseFloat(p.precio) || 0
      const cant = Number.parseInt(p.cantidad) || 1
      const totalLinea = precio * cant
      subtotalNum += totalLinea
      return {
        codigo: p.codigo || "",
        nombre: p.nombre || p.title || "",
        textura: p.textura || null,
        cantidad: cant,
        precio: precio,
        total: totalLinea,
      }
    })

    const iva = 0
    const total = subtotalNum

    const transaction = pedidosPool.transaction()
    await transaction.begin()

    try {
      const reqT = transaction.request()

      const headerResult = await reqT
        .input("numero_pedido", sql.NVarChar, numeroPedido)
        .input("codigo_cliente", sql.NVarChar, (codigoCliente || cedula).trim())
        .input("cedula_cliente", sql.NVarChar, cedula.trim())
        .input("nombre_cliente", sql.NVarChar, nombre.trim())
        .input("direccion", sql.NVarChar, (direccion || "").trim() || null)
        .input("telefono", sql.NVarChar, (telefono || "").trim() || null)
        .input("correo", sql.NVarChar, correo.trim())
        .input("subtotal", sql.Decimal(18, 2), subtotalNum)
        .input("iva", sql.Decimal(18, 2), iva)
        .input("total", sql.Decimal(18, 2), total)
        .input("observaciones", sql.NVarChar, (observaciones || "").trim() || null)
        .input("vendedor", sql.NVarChar, (vendedor || "").trim() || null)
        .query(`
          INSERT INTO pedidos (numero_pedido, codigo_cliente, cedula_cliente, nombre_cliente, direccion, telefono, correo, subtotal, iva, total, observaciones, vendedor)
          OUTPUT INSERTED.id
          VALUES (@numero_pedido, @codigo_cliente, @cedula_cliente, @nombre_cliente, @direccion, @telefono, @correo, @subtotal, @iva, @total, @observaciones, @vendedor)
        `)

      const pedidoId = headerResult.recordset[0].id

      await insertarFilas(
        () => transaction.request(),
        "pedidos_detalle",
        ["pedido_id", "codigo_producto", "nombre_producto", "textura", "cantidad", "precio_unitario", "total_linea"],
        items,
        (item) => [
          [sql.Int, pedidoId],
          [sql.NVarChar, item.codigo],
          [sql.NVarChar, item.nombre],
          [sql.NVarChar, item.textura],
          [sql.Int, item.cantidad],
          [sql.Decimal(18, 2), item.precio],
          [sql.Decimal(18, 2), item.total],
        ],
      )

      const reqHist = transaction.request()
      await reqHist
        .input("pedido_id", sql.Int, pedidoId)
        .input("estado_nuevo", sql.NVarChar, "PENDIENTE")
        .input("comentario", sql.NVarChar, "Pedido creado desde la app")
        .input("usuario", sql.NVarChar, (vendedor || "APP").trim())
        .query(`
          INSERT INTO pedidos_historial (pedido_id, estado_nuevo, comentario, usuario)
          VALUES (@pedido_id, @estado_nuevo, @comentario, @usuario)
        `)

      await transaction.commit()

      const elapsed = Date.now() - startTime
      console.log(`Pedido ${numeroPedido} guardado (id ${pedidoId}, $${total.toFixed(2)}, ${elapsed}ms)`)

      res.json({
        success: true,
        message: "Pedido registrado correctamente",
        docEntry: pedidoId,
        docNum: numeroPedido,
        emailSent: false,
        processingTime: elapsed,
      })
    } catch (err) {
      await transaction.rollback()
      throw err
    }
  } catch (error) {
    console.error("Error guardando pedido:", error)
    res.status(500).json({
      success: false,
      message: error.message || "Error al registrar el pedido",
    })
  }
})

app.get("/api/orders/:codigoCliente", authenticateToken, async (req, res) => {
  try {
    const { codigoCliente } = req.params
    const { estado, limit = 50, page = 1 } = req.query
    const offset = (Number.parseInt(page) - 1) * Number.parseInt(limit)

    let query = `
      SELECT p.*, d.total_productos, d.total_unidades
      FROM pedidos p
      OUTER APPLY (
        SELECT COUNT(*) AS total_productos, SUM(x.cantidad) AS total_unidades
        FROM pedidos_detalle x WHERE x.pedido_id = p.id
      ) d
      WHERE (p.codigo_cliente = @codigo OR p.cedula_cliente = @codigo)
    `
    const req2 = pedidosPool.request()
    req2.input("codigo", sql.NVarChar, codigoCliente)

    if (estado) {
      query += ` AND p.estado = @estado`
      req2.input("estado", sql.NVarChar, estado)
    }

    query += ` ORDER BY p.fecha_creacion DESC OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`
    req2.input("offset", sql.Int, offset)
    req2.input("limit", sql.Int, Number.parseInt(limit))

    const result = await req2.query(query)

    res.json({
      success: true,
      pedidos: result.recordset,
      page: Number.parseInt(page),
      limit: Number.parseInt(limit),
    })
  } catch (error) {
    console.error("Error consultando pedidos:", error)
    res.status(500).json({ success: false, message: error.message })
  }
})

app.get("/api/orders/detail/:numeroPedido", authenticateToken, async (req, res) => {
  try {
    const { numeroPedido } = req.params

    const reqP = pedidosPool.request()
    const pedido = await reqP
      .input("numero_pedido", sql.NVarChar, numeroPedido)
      .query(`SELECT * FROM pedidos WHERE numero_pedido = @numero_pedido`)

    if (pedido.recordset.length === 0) {
      return res.status(404).json({ success: false, message: "Pedido no encontrado" })
    }

    const pedidoData = pedido.recordset[0]

    const reqD = pedidosPool.request()
    const detalle = await reqD
      .input("pedido_id", sql.Int, pedidoData.id)
      .query(`SELECT * FROM pedidos_detalle WHERE pedido_id = @pedido_id ORDER BY id`)

    const reqH = pedidosPool.request()
    const historial = await reqH
      .input("pedido_id_h", sql.Int, pedidoData.id)
      .query(`SELECT * FROM pedidos_historial WHERE pedido_id = @pedido_id_h ORDER BY fecha DESC`)

    res.json({
      success: true,
      pedido: pedidoData,
      detalle: detalle.recordset,
      historial: historial.recordset,
    })
  } catch (error) {
    console.error("Error consultando detalle de pedido:", error)
    res.status(500).json({ success: false, message: error.message })
  }
})


app.get("/api/orders", authenticateToken, async (req, res) => {
  try {
    const { cliente, estado } = req.query

    if (!cliente || cliente.trim() === "") {
      return res.status(400).json({ success: false, message: "Código de cliente requerido", data: [] })
    }

    const limite = limiteDesdeQuery(req.query.limit, 200, 1000)
    const pagina = limiteDesdeQuery(req.query.page, 1, 100000)

    let query = `
      SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
             p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
             p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
             d.total_productos, d.total_unidades
      FROM pedidos p
      OUTER APPLY (
        SELECT COUNT(*) AS total_productos, SUM(x.cantidad) AS total_unidades
        FROM pedidos_detalle x WHERE x.pedido_id = p.id
      ) d
      WHERE p.codigo_cliente = @cliente
    `
    const reqDb = pedidosPool.request()
    reqDb.input("cliente", sql.NVarChar, cliente.trim())

    if (estado && estado.trim() !== "") {
      query += " AND p.estado = @estado"
      reqDb.input("estado", sql.NVarChar, estado.trim())
    }

    query += " ORDER BY p.fecha_creacion DESC OFFSET @offset ROWS FETCH NEXT @limite ROWS ONLY"
    reqDb.input("offset", sql.Int, (pagina - 1) * limite)
    reqDb.input("limite", sql.Int, limite)

    const result = await reqDb.query(query)

    const pedidos = result.recordset.map((p) => ({
      id: p.id,
      numeroPedido: p.numero_pedido,
      codigoCliente: p.codigo_cliente,
      nombreCliente: p.nombre_cliente,
      direccion: p.direccion || "",
      telefono: p.telefono || "",
      correo: p.correo || "",
      subtotal: Number.parseFloat(p.subtotal) || 0,
      iva: Number.parseFloat(p.iva) || 0,
      total: Number.parseFloat(p.total) || 0,
      estado: p.estado || "PENDIENTE",
      vendedor: p.vendedor || "",
      fechaCreacion: p.fecha_creacion,
      totalProductos: p.total_productos || 0,
      totalUnidades: p.total_unidades || 0,
    }))

    res.json({ success: true, data: pedidos, total: pedidos.length, page: pagina, limit: limite, hasMore: pedidos.length >= limite })
  } catch (error) {
    console.error("Error obteniendo pedidos:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener pedidos", data: [] })
  }
})

app.get("/api/orders/:id/detail", authenticateToken, async (req, res) => {
  try {
    const pedidoId = parseInt(req.params.id, 10)

    const headerResult = await pedidosPool.request()
      .input("id", sql.Int, pedidoId)
      .query(`
        SELECT * FROM pedidos WHERE id = @id
      `)

    if (headerResult.recordset.length === 0) {
      return res.status(404).json({ success: false, message: "Pedido no encontrado" })
    }

    const detailResult = await pedidosPool.request()
      .input("pedidoId", sql.Int, pedidoId)
      .query(`
        SELECT * FROM pedidos_detalle WHERE pedido_id = @pedidoId ORDER BY id
      `)

    const p = headerResult.recordset[0]
    res.json({
      success: true,
      data: {
        id: p.id,
        numeroPedido: p.numero_pedido,
        codigoCliente: p.codigo_cliente,
        nombreCliente: p.nombre_cliente,
        estado: p.estado,
        subtotal: Number.parseFloat(p.subtotal) || 0,
        iva: Number.parseFloat(p.iva) || 0,
        total: Number.parseFloat(p.total) || 0,
        fechaCreacion: p.fecha_creacion,
        productos: detailResult.recordset.map((d) => ({
          codigo: d.codigo_producto,
          nombre: d.nombre_producto,
          textura: d.textura,
          cantidad: d.cantidad,
          precioUnitario: Number.parseFloat(d.precio_unitario) || 0,
          totalLinea: Number.parseFloat(d.total_linea) || 0,
          
        })),
      },
    })
  } catch (error) {
    console.error("Error obteniendo detalle pedido:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener detalle" })
  }
})

app.get("/api/orders/vendedor/:nombre", authenticateToken, async (req, res) => {
  try {
    const vendedorNombre = decodeURIComponent(req.params.nombre).trim()
    const { estado } = req.query

    if (!vendedorNombre) {
      return res.status(400).json({ success: false, message: "Nombre de vendedor requerido", data: [] })
    }

    const limite = limiteDesdeQuery(req.query.limit, 200, 1000)
    const pagina = limiteDesdeQuery(req.query.page, 1, 100000)

    let query = `
      SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
             p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
             p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
             d.total_productos, d.total_unidades
      FROM pedidos p
      OUTER APPLY (
        SELECT COUNT(*) AS total_productos, SUM(x.cantidad) AS total_unidades
        FROM pedidos_detalle x WHERE x.pedido_id = p.id
      ) d
      WHERE p.vendedor = @vendedor
    `
    const reqDb = pedidosPool.request()
    reqDb.input("vendedor", sql.NVarChar, vendedorNombre)

    if (estado && estado.trim() !== "") {
      query += " AND p.estado = @estado"
      reqDb.input("estado", sql.NVarChar, estado.trim())
    }

    query += " ORDER BY p.fecha_creacion DESC OFFSET @offset ROWS FETCH NEXT @limite ROWS ONLY"
    reqDb.input("offset", sql.Int, (pagina - 1) * limite)
    reqDb.input("limite", sql.Int, limite)

    const result = await reqDb.query(query)

    const pedidos = result.recordset.map((p) => ({
      id: p.id,
      numeroPedido: p.numero_pedido,
      codigoCliente: p.codigo_cliente,
      nombreCliente: p.nombre_cliente,
      direccion: p.direccion || "",
      telefono: p.telefono || "",
      correo: p.correo || "",
      subtotal: Number.parseFloat(p.subtotal) || 0,
      iva: Number.parseFloat(p.iva) || 0,
      total: Number.parseFloat(p.total) || 0,
      estado: p.estado || "PENDIENTE",
      vendedor: p.vendedor || "",
      fechaCreacion: p.fecha_creacion,
      totalProductos: p.total_productos || 0,
      totalUnidades: p.total_unidades || 0,
    }))

    console.log(`Pedidos vendedor "${vendedorNombre}": ${pedidos.length} encontrados`)
    res.json({ success: true, data: pedidos, total: pedidos.length, page: pagina, limit: limite, hasMore: pedidos.length >= limite })
  } catch (error) {
    console.error("Error obteniendo pedidos del vendedor:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener pedidos del vendedor", data: [] })
  }
})

const rutaDbConfig = {
  server: process.env.DB_SERVER,
  database: process.env.RUTA_DB_NAME || "Ruta",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || "1433", 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 30000,
    requestTimeout: 30000,
  },
  pool: { max: 15, min: 2, idleTimeoutMillis: 300000, acquireTimeoutMillis: 15000 },
}

let rutaPool = null
let rutaConectando = null
function connectRuta() {
  if (rutaPool && rutaPool.connected) return Promise.resolve(rutaPool)
  if (!rutaConectando) {
    rutaConectando = new sql.ConnectionPool(rutaDbConfig)
      .connect()
      .then((p) => {
        rutaPool = p
        console.info("Conectado a BD Ruta (rutero)")
        return p
      })
      .finally(() => {
        rutaConectando = null
      })
  }
  return rutaConectando
}

let rutasExtraColsListas = false
async function ensureRutasExtraCols(pool) {
  if (rutasExtraColsListas) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='es_extra' AND Object_ID=Object_ID('dbo.rutas'))
      ALTER TABLE dbo.rutas ADD es_extra BIT NOT NULL CONSTRAINT DF_rutas_es_extra DEFAULT (0);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='motivo_extra' AND Object_ID=Object_ID('dbo.rutas'))
      ALTER TABLE dbo.rutas ADD motivo_extra NVARCHAR(300) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='observacion' AND Object_ID=Object_ID('dbo.rutas'))
      ALTER TABLE dbo.rutas ADD observacion NVARCHAR(MAX) NULL;
  `)
  rutasExtraColsListas = true

  try {
    await pool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rutas_vendedor_fecha' AND object_id = OBJECT_ID('dbo.rutas'))
        CREATE INDEX IX_rutas_vendedor_fecha ON dbo.rutas(vendedor_id, fecha_programada DESC);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rutas_cliente_fecha' AND object_id = OBJECT_ID('dbo.rutas'))
        CREATE INDEX IX_rutas_cliente_fecha ON dbo.rutas(cliente_id, fecha_programada DESC);
    `)
  } catch (e) {
    console.error("No se pudieron crear los índices de rutas:", e.message)
  }
}

let actualizacionesTablaLista = false
async function ensureActualizacionesTabla(pool) {
  if (actualizacionesTablaLista) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'actualizaciones_clientes')
    CREATE TABLE dbo.actualizaciones_clientes (
      id INT IDENTITY(1,1) PRIMARY KEY,
      cliente_id      NVARCHAR(50)  NOT NULL,
      ruta_id         INT           NULL,
      vendedor_id     INT           NULL,
      vendedor_nombre NVARCHAR(255) NULL,
      nombre          NVARCHAR(255) NULL,
      direccion       NVARCHAR(500) NULL,
      telefono        NVARCHAR(100) NULL,
      correo          NVARCHAR(255) NULL,
      ciudad          NVARCHAR(150) NULL,
      datos_anteriores NVARCHAR(MAX) NULL,
      aplicado_sap    BIT           NOT NULL CONSTRAINT DF_actualizaciones_aplicado DEFAULT (0),
      fecha           DATETIME      NOT NULL CONSTRAINT DF_actualizaciones_fecha DEFAULT (GETDATE())
    );
  `)
  actualizacionesTablaLista = true
}

let encuestasTablasListas = false
async function ensureEncuestasTablas(pool) {
  if (encuestasTablasListas) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'encuestas_visitas')
    CREATE TABLE dbo.encuestas_visitas (
      id INT IDENTITY(1,1) PRIMARY KEY,
      visita_id       INT           NULL,
      cliente_id      NVARCHAR(50)  NOT NULL,
      vendedor_id     INT           NULL,
      vendedor_nombre NVARCHAR(255) NULL,
      tipo            NVARCHAR(60)  NULL,
      nombre          NVARCHAR(150) NULL,
      respuestas      NVARCHAR(MAX) NULL,
      fecha           DATETIME      NOT NULL CONSTRAINT DF_encuestas_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'encuestas_respuestas')
    CREATE TABLE dbo.encuestas_respuestas (
      id INT IDENTITY(1,1) PRIMARY KEY,
      encuesta_id     INT           NOT NULL,
      pregunta_id     NVARCHAR(80)  NULL,
      respuesta       NVARCHAR(MAX) NULL,
      fecha           DATETIME      NOT NULL CONSTRAINT DF_encuestas_resp_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_encuestas_resp_encuesta')
      CREATE INDEX IX_encuestas_resp_encuesta ON dbo.encuestas_respuestas(encuesta_id);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_encuestas_cliente' AND object_id = OBJECT_ID('dbo.encuestas_visitas'))
      CREATE INDEX IX_encuestas_cliente ON dbo.encuestas_visitas(cliente_id, id DESC);
    IF OBJECT_ID('dbo.visitas_clientes') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_encvis_visita')
       AND NOT EXISTS (SELECT 1 FROM dbo.encuestas_visitas ev WHERE ev.visita_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.visitas_clientes v WHERE v.id = ev.visita_id))
      ALTER TABLE dbo.encuestas_visitas
        ADD CONSTRAINT FK_encvis_visita FOREIGN KEY (visita_id) REFERENCES dbo.visitas_clientes(id) ON DELETE CASCADE;
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_encresp_encuesta')
       AND NOT EXISTS (SELECT 1 FROM dbo.encuestas_respuestas er WHERE NOT EXISTS (SELECT 1 FROM dbo.encuestas_visitas ev WHERE ev.id = er.encuesta_id))
      ALTER TABLE dbo.encuestas_respuestas
        ADD CONSTRAINT FK_encresp_encuesta FOREIGN KEY (encuesta_id) REFERENCES dbo.encuestas_visitas(id) ON DELETE CASCADE;
  `)
  encuestasTablasListas = true
}

function getSlpCodeFromToken(req) {
  const authHeader = req.headers.authorization
  if (authHeader && authHeader.startsWith("Bearer ")) {
    try {
      const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
      if (decoded.tipo === "vendedor") return decoded.userId
      return decoded.userId ?? null
    } catch (_) {}
  }
  return null
}

function mapRuta(r) {
  return {
    id: r.id,
    nombre: r.nombre || "",
    estado: r.estado || "",
    clienteId: r.cliente_id || "",
    ciudad: r.ciudad || "",
    usuarioNombre: r.usuario_nombre || "",
    fechaProgramada: r.fecha_programada,
    horaVisita: r.hora_visita || "",
    fechaCreacion: r.fecha_creacion,
    fechaActualizacion: r.fecha_actualizacion,
    visitadoHoy: (r.visitas_hoy || 0) > 0,
    esExtra: r.es_extra === true || r.es_extra === 1,
    motivoExtra: r.motivo_extra || "",
    observacion: r.observacion || "",
  }
}

function esCompletada(estado) {
  const e = (estado || "").toUpperCase()
  return e.includes("COMPLET") || e.includes("FINALIZ") || e.includes("CUMPLID")
}

function esCancelada(estado) {
  return (estado || "").toUpperCase().includes("CANCEL")
}

app.get("/api/rutas/mias", authenticateToken, async (req, res) => {
  try {
    const slpCode = getSlpCodeFromToken(req)
    if (slpCode === null) {
      return res.status(401).json({ success: false, message: "Sesión inválida" })
    }

    const periodo = (req.query.periodo || "todas").toString().toLowerCase()

    const hoy = new Date()
    hoy.setHours(0, 0, 0, 0)
    let inicio = null
    let fin = null
    if (periodo === "hoy") {
      inicio = new Date(hoy)
      fin = new Date(hoy)
      fin.setDate(fin.getDate() + 1)
    } else if (periodo === "semana") {
      const diaSemana = (hoy.getDay() + 6) % 7
      inicio = new Date(hoy)
      inicio.setDate(inicio.getDate() - diaSemana)
      fin = new Date(inicio)
      fin.setDate(fin.getDate() + 7)
    } else if (periodo === "mes") {
      inicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
      fin = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 1)
    }

    const ruta = await connectRuta()
    await ensureVisitasTabla(ruta)
    await ensureRutasExtraCols(ruta)
    const request = ruta.request().input("slpCode", sql.Int, slpCode)
    let filtroFecha = ""
    if (inicio && fin) {
      const toLocalIso = (d) =>
        `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}T00:00:00`
      request.input("inicio", sql.VarChar, toLocalIso(inicio))
      request.input("fin", sql.VarChar, toLocalIso(fin))
      filtroFecha = "AND r.fecha_programada >= CONVERT(DATETIME, @inicio, 126) AND r.fecha_programada < CONVERT(DATETIME, @fin, 126)"
    }

    const result = await request.query(`
      SELECT r.id, r.nombre, r.estado, r.cliente_id, r.ciudad, r.usuario_nombre,
             r.es_extra, r.motivo_extra, r.observacion,
             CONVERT(VARCHAR(19), r.fecha_programada, 126) AS fecha_programada,
             CONVERT(VARCHAR(5), r.hora_visita, 108) AS hora_visita,
             CONVERT(VARCHAR(19), r.fecha_creacion, 126) AS fecha_creacion,
             CONVERT(VARCHAR(19), r.fecha_actualizacion, 126) AS fecha_actualizacion,
             (SELECT COUNT(*) FROM visitas_clientes v
              WHERE v.cliente_id = r.cliente_id
                AND v.fecha >= CAST(GETDATE() AS DATE)
                AND v.fecha < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))) AS visitas_hoy
      FROM rutas r
      WHERE r.vendedor_id = @slpCode ${filtroFecha}
      ORDER BY r.fecha_programada DESC, r.hora_visita ASC
    `)

    const rutas = result.recordset.map(mapRuta)
    const completadas = rutas.filter((r) => esCompletada(r.estado)).length
    const canceladas = rutas.filter((r) => esCancelada(r.estado)).length
    const clientesUnicos = new Set(rutas.map((r) => r.clienteId).filter(Boolean)).size

    console.log(`Rutas vendedor ${slpCode} (${periodo}): ${rutas.length}`)
    res.json({
      success: true,
      periodo,
      rutas,
      total: rutas.length,
      completadas,
      pendientes: rutas.length - completadas - canceladas,
      clientesUnicos,
    })
  } catch (error) {
    console.error("Error obteniendo mis rutas:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener rutas", rutas: [] })
  }
})

app.post("/api/rutas/extra", authenticateToken, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || ""
    let slpCode = null
    let vendedorNombre = ""
    if (authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        slpCode = decoded.userId ?? null
        vendedorNombre = decoded.nombre || ""
      } catch (_) {
        return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
      }
    }
    if (slpCode === null) {
      return res.status(401).json({ success: false, message: "Sesión inválida" })
    }

    const clienteId = (req.body.clienteId || "").toString().trim()
    const clienteNombre = (req.body.clienteNombre || "").toString().trim()
    const ciudad = (req.body.ciudad || "").toString().trim()
    const motivo = (req.body.motivo || "").toString().trim()
    const observacion = (req.body.observacion || "").toString().trim()

    if (!clienteId) {
      return res.status(400).json({ success: false, message: "Debes seleccionar un cliente" })
    }
    if (motivo.length < 5) {
      return res.status(400).json({ success: false, message: "Indica el motivo de la visita (mínimo 5 caracteres)" })
    }
    if (observacion.length < 5) {
      return res.status(400).json({ success: false, message: "La observación es obligatoria (mínimo 5 caracteres)" })
    }

    const ruta = await connectRuta()
    await ensureRutasExtraCols(ruta)

    const nombreRuta = clienteNombre ? `Visita a ${clienteNombre}` : `Ruta extra ${clienteId}`

    const result = await ruta
      .request()
      .input("nombre", sql.NVarChar, nombreRuta)
      .input("usuarioId", sql.Int, slpCode)
      .input("clienteId", sql.NVarChar, clienteId)
      .input("vendedorId", sql.Int, slpCode)
      .input("usuarioNombre", sql.NVarChar, vendedorNombre)
      .input("ciudad", sql.NVarChar, ciudad || null)
      .input("motivo", sql.NVarChar, motivo)
      .input("observacion", sql.NVarChar, observacion)
      .query(`
        INSERT INTO dbo.rutas
          (nombre, estado, usuario_id, cliente_id, vendedor_id, usuario_nombre,
           fecha_programada, hora_visita, fecha_creacion, fecha_actualizacion, ciudad,
           es_extra, motivo_extra, observacion)
        OUTPUT INSERTED.id
        VALUES
          (@nombre, 'activa', @usuarioId, @clienteId, @vendedorId, @usuarioNombre,
           GETDATE(), CONVERT(VARCHAR(5), GETDATE(), 108), GETDATE(), GETDATE(), @ciudad,
           1, @motivo, @observacion)
      `)

    const nuevoId = result.recordset[0].id
    console.log(`Ruta EXTRA #${nuevoId} vendedor ${slpCode}, cliente ${clienteId}, motivo: ${motivo}`)
    res.json({ success: true, message: "Ruta extra agregada correctamente", data: { id: nuevoId } })
  } catch (error) {
    console.error("Error creando ruta extra:", error.message)
    res.status(500).json({ success: false, message: "No se pudo crear la ruta extra" })
  }
})

let tareasTablaExiste = false
app.get("/api/clientes/:codigo/tareas", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo
    const ruta = await connectRuta()

    if (!tareasTablaExiste) {
      const existe = await ruta.request().query(`
        SELECT COUNT(*) AS n FROM sys.tables WHERE name = 'tareas_asignadas_clientes'
      `)
      tareasTablaExiste = existe.recordset[0].n > 0
    }
    if (!tareasTablaExiste) {
      return res.json({
        success: true,
        data: { tareas: [], total: 0, cumplidas: 0, activas: 0, promedio: 0 },
      })
    }

    const limite = limiteDesdeQuery(req.query.limit, 200, 1000)
    const result = await ruta.request()
      .input("clienteId", sql.VarChar, codigo)
      .input("limite", sql.Int, limite)
      .query(`
        SELECT TOP (@limite) id, tarea, lista, subcanal, vendedor, coach,
               ISNULL(cumplida, 0) AS cumplida,
               ISNULL(activa, 1) AS activa,
               porcentaje_final, comentario, estado_vendedor,
               CONVERT(VARCHAR(19), fecha_carga, 120)  AS fecha_carga,
               CONVERT(VARCHAR(19), fecha_estado, 120) AS fecha_estado
        FROM tareas_asignadas_clientes
        WHERE cliente_id = @clienteId
        ORDER BY cumplida ASC, fecha_carga DESC, id DESC
      `)

    const tareas = result.recordset.map((t) => {
      const cumplida = t.cumplida === true || t.cumplida === 1
      const activa = (t.activa === true || t.activa === 1) && !cumplida
      return {
        id: t.id,
        tarea: t.tarea || "",
        lista: t.lista || "",
        subcanal: t.subcanal || "",
        vendedor: t.vendedor || "",
        coach: t.coach || "",
        cumplida,
        activa,
        porcentajeFinal: t.porcentaje_final != null ? Number(t.porcentaje_final) : (cumplida ? 100 : 0),
        comentario: t.comentario || "",
        estadoVendedor: t.estado_vendedor || "",
        fechaCarga: t.fecha_carga,
        fechaEstado: t.fecha_estado,
      }
    })

    const cumplidas = tareas.filter((t) => t.cumplida).length
    const activas = tareas.filter((t) => t.activa).length
    const promedio = tareas.length
      ? Math.round(tareas.reduce((a, t) => a + (t.porcentajeFinal || 0), 0) / tareas.length)
      : 0

    console.log(`Tareas cliente ${codigo}: ${tareas.length} (${cumplidas} cumplidas)`)
    res.json({
      success: true,
      data: { tareas, total: tareas.length, cumplidas, activas, promedio },
    })
  } catch (error) {
    console.error("Error obteniendo tareas del cliente:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener tareas" })
  }
})

let visitasTablaLista = false
async function ensureVisitasTabla(pool) {
  if (visitasTablaLista) return
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'visitas_clientes')
    CREATE TABLE dbo.visitas_clientes (
      id INT IDENTITY(1,1) PRIMARY KEY,
      cliente_id      NVARCHAR(50)  NOT NULL,
      ruta_id         INT           NULL,
      vendedor_id     INT           NULL,
      vendedor_nombre NVARCHAR(255) NULL,
      estado_cliente  VARCHAR(30)   NULL,
      observacion     NVARCHAR(MAX) NULL,
      fecha           DATETIME      NOT NULL CONSTRAINT DF_visitas_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='motivo_no_gestion' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD motivo_no_gestion NVARCHAR(150) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='total_pedidos' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD total_pedidos DECIMAL(18,2) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='total_cartera' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD total_cartera DECIMAL(18,2) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='total_recaudos' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD total_recaudos DECIMAL(18,2) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='hora_inicio' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD hora_inicio DATETIME NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='hora_fin' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD hora_fin DATETIME NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='duracion_segundos' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD duracion_segundos INT NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='encuesta_tipo' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD encuesta_tipo NVARCHAR(60) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='encuesta_respuestas' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD encuesta_respuestas NVARCHAR(MAX) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='segunda_visita' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD segunda_visita BIT NOT NULL CONSTRAINT DF_visitas_segunda DEFAULT (0);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='motivo_segunda_visita' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD motivo_segunda_visita NVARCHAR(MAX) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='metodo_pago' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD metodo_pago NVARCHAR(40) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='banco_pago' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD banco_pago NVARCHAR(120) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='referencia_pago' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD referencia_pago NVARCHAR(120) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='numero_recaudo' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD numero_recaudo NVARCHAR(60) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='recaudo_id' AND Object_ID=Object_ID('dbo.visitas_clientes'))
      ALTER TABLE dbo.visitas_clientes ADD recaudo_id INT NULL;
  `)
  visitasTablaLista = true

  try {
    await pool.request().query(`
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_visitas_cliente_fecha' AND object_id = OBJECT_ID('dbo.visitas_clientes'))
        CREATE INDEX IX_visitas_cliente_fecha ON dbo.visitas_clientes(cliente_id, fecha DESC);
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_visitas_vendedor_fecha' AND object_id = OBJECT_ID('dbo.visitas_clientes'))
        CREATE INDEX IX_visitas_vendedor_fecha ON dbo.visitas_clientes(vendedor_id, fecha DESC);
    `)
  } catch (e) {
    console.error("No se pudieron crear los índices de visitas:", e.message)
  }
}

app.get("/api/clientes/:codigo/visitas-hoy", authenticateToken, async (req, res) => {
  try {
    const ruta = await connectRuta()
    await ensureVisitasTabla(ruta)
    const r = await ruta.request().input("cliente", sql.NVarChar, req.params.codigo).query(`
      SELECT COUNT(*) AS total,
             MAX(CONVERT(VARCHAR(19), fecha, 120)) AS ultima
      FROM visitas_clientes
      WHERE cliente_id = @cliente
        AND fecha >= CAST(GETDATE() AS DATE)
        AND fecha < DATEADD(DAY, 1, CAST(GETDATE() AS DATE))
    `)
    const row = r.recordset[0]
    res.json({
      success: true,
      data: { visitadoHoy: (row.total || 0) > 0, total: row.total || 0, ultima: row.ultima },
    })
  } catch (error) {
    console.error("Error visitas-hoy:", error.message)
    res.status(500).json({ success: false, message: "Error", data: { visitadoHoy: false, total: 0 } })
  }
})

app.get("/api/clientes/:codigo/ultimo-pedido", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo
    const desde = (req.query.desde || "").toString().trim().replace("Z", "").slice(0, 23)
    const r = pedidosPool.request().input("codigo", sql.NVarChar, codigo)
    let filtroFecha = ""
    if (desde && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(desde)) {
      r.input("desde", sql.VarChar, desde)
      filtroFecha = "AND p.fecha_creacion >= CONVERT(DATETIME, @desde, 126)"
    }
    const ped = await r.query(`
      SELECT TOP 1 p.id, p.numero_pedido, p.total, p.subtotal, p.iva,
             CONVERT(VARCHAR(19), p.fecha_creacion, 120) AS fecha
      FROM pedidos p
      WHERE (p.codigo_cliente = @codigo OR p.cedula_cliente = @codigo) ${filtroFecha}
        AND (p.estado IS NULL OR p.estado <> 'CANCELADO')
      ORDER BY p.fecha_creacion DESC, p.id DESC
    `)
    if (ped.recordset.length === 0) {
      return res.json({ success: true, data: null })
    }
    const pedido = ped.recordset[0]
    const det = await pedidosPool.request().input("pid", sql.Int, pedido.id).query(`
      SELECT codigo_producto, nombre_producto, cantidad, precio_unitario, total_linea
      FROM pedidos_detalle WHERE pedido_id = @pid ORDER BY id
    `)
    res.json({
      success: true,
      data: {
        numeroPedido: pedido.numero_pedido,
        total: Number.parseFloat(pedido.total) || 0,
        subtotal: Number.parseFloat(pedido.subtotal) || 0,
        iva: Number.parseFloat(pedido.iva) || 0,
        fecha: pedido.fecha,
        items: det.recordset.map((d) => ({
          codigo: d.codigo_producto || "",
          nombre: d.nombre_producto || "",
          cantidad: d.cantidad || 0,
          precio: Number.parseFloat(d.precio_unitario) || 0,
          total: Number.parseFloat(d.total_linea) || 0,
        })),
      },
    })
  } catch (error) {
    console.error("Error último pedido:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener el pedido" })
  }
})

const ESTADOS_VISITA = ["nuevo", "activo", "sesenta", "perdido"]

app.post("/api/clientes/:codigo/visita", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo
    const b = req.body || {}
    const estado = (b.estadoCliente || "").toString().trim().toLowerCase()
    const observacion = (b.observacion || "").toString().trim()
    const motivo = (b.motivo || "").toString().trim()
    const rutaId = Number.parseInt(b.rutaId, 10)
    const totalPedidos = Number.parseFloat(b.totalPedidos)
    const totalCartera = Number.parseFloat(b.totalCartera)
    const totalRecaudos = Number.parseFloat(b.totalRecaudos)
    const metodoPago = (b.metodoPago || "").toString().trim()
    const bancoPago = (b.bancoPago || "").toString().trim()
    const referenciaPago = (b.referenciaPago || "").toString().trim()
    const numeroRecaudo = (b.numeroRecaudo || "").toString().trim()
    const horaInicio = b.horaInicio ? new Date(b.horaInicio) : null
    const horaFin = b.horaFin ? new Date(b.horaFin) : new Date()
    const duracionSeg = Number.parseInt(b.duracionSegundos, 10)
    const encuestaTipo = (b.encuestaTipo || "").toString().trim()
    let encuestaRespuestas = null
    if (b.encuestaRespuestas != null) {
      encuestaRespuestas = typeof b.encuestaRespuestas === "string"
        ? b.encuestaRespuestas
        : JSON.stringify(b.encuestaRespuestas)
    }
    const segundaVisita = b.segundaVisita === true || b.segundaVisita === 1
    const motivoSegunda = (b.motivoSegundaVisita || "").toString().trim()

    if (estado && !ESTADOS_VISITA.includes(estado)) {
      return res.status(400).json({ success: false, message: "Estado del cliente inválido" })
    }

    const slpCode = getSlpCodeFromToken(req)
    let vendedorNombre = ""
    const authHeader = req.headers.authorization
    if (authHeader && authHeader.startsWith("Bearer ")) {
      try {
        vendedorNombre = jwt.verify(authHeader.slice(7), JWT_SECRET).nombre || ""
      } catch (_) {}
    }

    const ruta = await connectRuta()
    await ensureVisitasTabla(ruta)
    const recaudoIdVisita = await resolverRecaudoIdPedidos(numeroRecaudo || null)

    const insert = await ruta.request()
      .input("cliente", sql.NVarChar, codigo)
      .input("rutaId", sql.Int, Number.isNaN(rutaId) ? null : rutaId)
      .input("vendId", sql.Int, slpCode)
      .input("vendNom", sql.NVarChar, vendedorNombre)
      .input("estado", sql.VarChar, estado || null)
      .input("obs", sql.NVarChar, observacion || null)
      .input("motivo", sql.NVarChar, motivo || null)
      .input("tPed", sql.Decimal(18, 2), Number.isNaN(totalPedidos) ? 0 : totalPedidos)
      .input("tCar", sql.Decimal(18, 2), Number.isNaN(totalCartera) ? 0 : totalCartera)
      .input("tRec", sql.Decimal(18, 2), Number.isNaN(totalRecaudos) ? 0 : totalRecaudos)
      .input("hIni", sql.DateTime, horaInicio)
      .input("hFin", sql.DateTime, horaFin)
      .input("dur", sql.Int, Number.isNaN(duracionSeg) ? null : duracionSeg)
      .input("encTipo", sql.NVarChar, encuestaTipo || null)
      .input("encResp", sql.NVarChar, encuestaRespuestas)
      .input("segunda", sql.Bit, segundaVisita ? 1 : 0)
      .input("motSeg", sql.NVarChar, motivoSegunda || null)
      .input("metPago", sql.NVarChar, metodoPago || null)
      .input("bancoPago", sql.NVarChar, bancoPago || null)
      .input("refPago", sql.NVarChar, referenciaPago || null)
      .input("numRec", sql.NVarChar, numeroRecaudo || null)
      .input("recaudoId", sql.Int, recaudoIdVisita)
      .query(`
        INSERT INTO visitas_clientes
          (cliente_id, ruta_id, vendedor_id, vendedor_nombre, estado_cliente, observacion,
           motivo_no_gestion, total_pedidos, total_cartera, total_recaudos,
           hora_inicio, hora_fin, duracion_segundos, encuesta_tipo, encuesta_respuestas,
           segunda_visita, motivo_segunda_visita, metodo_pago, banco_pago, referencia_pago, numero_recaudo, recaudo_id)
        OUTPUT INSERTED.id, CONVERT(VARCHAR(19), INSERTED.fecha, 120) AS fecha
        VALUES (@cliente, @rutaId, @vendId, @vendNom, @estado, @obs,
                @motivo, @tPed, @tCar, @tRec, @hIni, @hFin, @dur, @encTipo, @encResp,
                @segunda, @motSeg, @metPago, @bancoPago, @refPago, @numRec, @recaudoId)
      `)

    const row = insert.recordset[0]
    console.log(`Visita registrada cliente ${codigo}: estado=${estado || "-"} motivo=${motivo || "-"} recaudo=${Number.isNaN(totalRecaudos) ? 0 : totalRecaudos} pago=${metodoPago || "-"}${bancoPago ? "/" + bancoPago : ""}${referenciaPago ? " ref:" + referenciaPago : ""} dur=${duracionSeg || 0}s vend=${slpCode}`)

    if (encuestaRespuestas) {
      try {
        await ensureEncuestasTablas(ruta)
        const encObj = typeof encuestaRespuestas === "string"
          ? JSON.parse(encuestaRespuestas)
          : encuestaRespuestas
        const tipoId = (encObj.tipo || "").toString()
        const nombreEnc = (encObj.nombre || encuestaTipo || "").toString()
        const respuestas = encObj.respuestas && typeof encObj.respuestas === "object"
          ? encObj.respuestas
          : {}

        const encIns = await ruta.request()
          .input("visitaId", sql.Int, row.id)
          .input("cliente", sql.NVarChar, codigo)
          .input("vendId", sql.Int, slpCode)
          .input("vendNom", sql.NVarChar, vendedorNombre)
          .input("tipo", sql.NVarChar, tipoId || null)
          .input("nombre", sql.NVarChar, nombreEnc || null)
          .input("resp", sql.NVarChar, encuestaRespuestas)
          .query(`
            INSERT INTO dbo.encuestas_visitas
              (visita_id, cliente_id, vendedor_id, vendedor_nombre, tipo, nombre, respuestas)
            OUTPUT INSERTED.id
            VALUES (@visitaId, @cliente, @vendId, @vendNom, @tipo, @nombre, @resp)
          `)
        const encuestaId = encIns.recordset[0].id

        await insertarFilas(
          () => ruta.request(),
          "dbo.encuestas_respuestas",
          ["encuesta_id", "pregunta_id", "respuesta"],
          Object.entries(respuestas),
          ([pid, val]) => [
            [sql.Int, encuestaId],
            [sql.NVarChar, pid.toString().slice(0, 80)],
            [sql.NVarChar, val == null ? null : (typeof val === "object" ? JSON.stringify(val) : String(val))],
          ],
        )
        console.log(`Encuesta #${encuestaId} guardada (visita ${row.id}): ${Object.keys(respuestas).length} respuestas`)
      } catch (e) {
        console.error("Aviso: no se pudo guardar la encuesta estructurada:", e.message)
      }
    }

    res.json({
      success: true,
      data: { id: row.id, fecha: row.fecha, estadoCliente: estado, observacion, motivo, duracionSegundos: duracionSeg },
    })
  } catch (error) {
    console.error("Error registrando visita:", error.message)
    res.status(500).json({ success: false, message: "Error al registrar la visita" })
  }
})

let pedidosGestionTablaLista = false
async function ensurePedidosGestionTabla() {
  if (pedidosGestionTablaLista) return
  await pedidosPool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pedidos_gestion')
    CREATE TABLE dbo.pedidos_gestion (
      id INT IDENTITY(1,1) PRIMARY KEY,
      numero_pedido   NVARCHAR(50)  NULL,
      cliente_id      NVARCHAR(50)  NOT NULL,
      cliente_nombre  NVARCHAR(255) NULL,
      vendedor_id     INT           NULL,
      vendedor_nombre NVARCHAR(255) NULL,
      subtotal        DECIMAL(18,2) NULL,
      descuento       DECIMAL(18,2) NULL,
      impuesto        DECIMAL(18,2) NULL,
      flete           DECIMAL(18,2) NULL,
      total           DECIMAL(18,2) NULL,
      forma_pago      NVARCHAR(60)  NULL,
      banco_pago      NVARCHAR(120) NULL,
      referencia_pago NVARCHAR(120) NULL,
      numero_recaudo  NVARCHAR(60)  NULL,
      plazo_dias      INT           NULL,
      fecha_entrega   NVARCHAR(30)  NULL,
      observaciones   NVARCHAR(MAX) NULL,
      evidencias      INT           NULL,
      estado          NVARCHAR(30)  NOT NULL CONSTRAINT DF_pedgest_estado DEFAULT ('GUARDADO'),
      fecha           DATETIME      NOT NULL CONSTRAINT DF_pedgest_fecha DEFAULT (GETDATE())
    );
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='numero_recaudo' AND Object_ID=Object_ID('dbo.pedidos_gestion'))
      ALTER TABLE dbo.pedidos_gestion ADD numero_recaudo NVARCHAR(60) NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE Name='recaudo_id' AND Object_ID=Object_ID('dbo.pedidos_gestion'))
      ALTER TABLE dbo.pedidos_gestion ADD recaudo_id INT NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pedgest_recaudo_id' AND object_id = OBJECT_ID('dbo.pedidos_gestion'))
      CREATE INDEX IX_pedgest_recaudo_id ON dbo.pedidos_gestion(recaudo_id);
    IF OBJECT_ID('dbo.recaudos') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pedgest_recaudo')
      ALTER TABLE dbo.pedidos_gestion
        ADD CONSTRAINT FK_pedgest_recaudo FOREIGN KEY (recaudo_id) REFERENCES dbo.recaudos(id) ON DELETE CASCADE;
  `)
  pedidosGestionTablaLista = true
}

app.post("/api/pedidos/gestion", authenticateToken, async (req, res) => {
  try {
    const authHeader = req.headers.authorization || ""
    let slpCode = null
    let vendedorNombre = ""
    if (authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        slpCode = decoded.userId ?? null
        vendedorNombre = decoded.nombre || ""
      } catch (_) {
        return res.status(401).json({ success: false, message: "Sesión inválida o expirada" })
      }
    }

    const b = req.body || {}
    const clienteId = (b.clienteId || "").toString().trim()
    if (!clienteId) {
      return res.status(400).json({ success: false, message: "Cliente requerido" })
    }
    const num = (v) => {
      const n = Number.parseFloat(v)
      return Number.isNaN(n) ? 0 : n
    }

    await ensurePedidosGestionTabla()

    const numRecGestion = (b.numeroRecaudo || "").toString().trim() || null
    const recaudoIdGestion = await resolverRecaudoIdPedidos(numRecGestion)

    const result = await pedidosPool
      .request()
      .input("numero", sql.NVarChar, (b.numeroPedido || "").toString().trim() || null)
      .input("clienteId", sql.NVarChar, clienteId)
      .input("clienteNombre", sql.NVarChar, (b.clienteNombre || "").toString().trim() || null)
      .input("vendId", sql.Int, slpCode)
      .input("vendNom", sql.NVarChar, vendedorNombre || null)
      .input("subtotal", sql.Decimal(18, 2), num(b.subtotal))
      .input("descuento", sql.Decimal(18, 2), num(b.descuento))
      .input("impuesto", sql.Decimal(18, 2), num(b.impuesto))
      .input("flete", sql.Decimal(18, 2), num(b.flete))
      .input("total", sql.Decimal(18, 2), num(b.total))
      .input("formaPago", sql.NVarChar, (b.formaPago || "").toString().trim() || null)
      .input("bancoPago", sql.NVarChar, (b.bancoPago || "").toString().trim() || null)
      .input("refPago", sql.NVarChar, (b.referenciaPago || "").toString().trim() || null)
      .input("numRec", sql.NVarChar, numRecGestion)
      .input("recaudoId", sql.Int, recaudoIdGestion)
      .input("plazo", sql.Int, Number.isNaN(Number.parseInt(b.plazoDias, 10)) ? null : Number.parseInt(b.plazoDias, 10))
      .input("fechaEntrega", sql.NVarChar, (b.fechaEntrega || "").toString().trim() || null)
      .input("obs", sql.NVarChar, (b.observaciones || "").toString().trim() || null)
      .input("evid", sql.Int, Number.isNaN(Number.parseInt(b.evidencias, 10)) ? 0 : Number.parseInt(b.evidencias, 10))
      .input("estado", sql.NVarChar, ((b.estado || "GUARDADO").toString().trim().toUpperCase()) || "GUARDADO")
      .query(`
        INSERT INTO dbo.pedidos_gestion
          (numero_pedido, cliente_id, cliente_nombre, vendedor_id, vendedor_nombre,
           subtotal, descuento, impuesto, flete, total,
           forma_pago, banco_pago, referencia_pago, numero_recaudo, recaudo_id, plazo_dias, fecha_entrega, observaciones, evidencias, estado)
        OUTPUT INSERTED.id
        VALUES
          (@numero, @clienteId, @clienteNombre, @vendId, @vendNom,
           @subtotal, @descuento, @impuesto, @flete, @total,
           @formaPago, @bancoPago, @refPago, @numRec, @recaudoId, @plazo, @fechaEntrega, @obs, @evid, @estado)
      `)

    const id = result.recordset[0].id
    const estadoFinal = (b.estado || "GUARDADO").toString().toUpperCase()
    console.log(`Gestión de pedido #${id} cliente ${clienteId} total ${num(b.total)} estado ${estadoFinal} vend ${slpCode}`)
    res.json({ success: true, message: "Pedido guardado correctamente", data: { id, estado: estadoFinal } })
  } catch (error) {
    console.error("Error guardando gestión de pedido:", error.message)
    res.status(500).json({ success: false, message: "No se pudo guardar el pedido" })
  }
})

app.get("/api/encuestas", authenticateToken, async (req, res) => {
  try {
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 500)
    const cliente = (req.query.cliente || "").toString().trim()

    const ruta = await connectRuta()
    await ensureEncuestasTablas(ruta)

    const reqEnc = ruta.request().input("limit", sql.Int, limit)
    let filtro = ""
    if (cliente) {
      reqEnc.input("cliente", sql.NVarChar, cliente)
      filtro = "WHERE e.cliente_id = @cliente"
    }
    const cab = await reqEnc.query(`
      SELECT TOP (@limit) e.id, e.visita_id, e.cliente_id, e.vendedor_id, e.vendedor_nombre,
             e.tipo, e.nombre, CONVERT(VARCHAR(19), e.fecha, 120) AS fecha
      FROM dbo.encuestas_visitas e
      ${filtro}
      ORDER BY e.id DESC
    `)

    const encuestas = cab.recordset
    if (encuestas.length > 0) {
      const ids = encuestas.map((e) => e.id)
      const det = await ruta.request().query(`
        SELECT encuesta_id, pregunta_id, respuesta
        FROM dbo.encuestas_respuestas
        WHERE encuesta_id IN (${ids.join(",")})
        ORDER BY id ASC
      `)
      const porEncuesta = {}
      det.recordset.forEach((d) => {
        ;(porEncuesta[d.encuesta_id] = porEncuesta[d.encuesta_id] || []).push({
          preguntaId: d.pregunta_id,
          respuesta: d.respuesta,
        })
      })
      encuestas.forEach((e) => { e.respuestas = porEncuesta[e.id] || [] })
    }

    res.json({ success: true, total: encuestas.length, data: encuestas })
  } catch (error) {
    console.error("Error obteniendo encuestas:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener encuestas", data: [] })
  }
})

app.get("/api/clientes/:codigo/pedidos-total", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo
    const desde = (req.query.desde || "").toString().trim().replace("Z", "").slice(0, 23)
    const r = pedidosPool.request().input("codigo", sql.NVarChar, codigo)
    let filtroFecha = ""
    if (desde && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(desde)) {
      r.input("desde", sql.VarChar, desde)
      filtroFecha = "AND p.fecha_creacion >= CONVERT(DATETIME, @desde, 126)"
    }
    const result = await r.query(`
      SELECT ISNULL(SUM(p.total), 0) AS total, COUNT(*) AS cantidad
      FROM pedidos p
      WHERE (p.codigo_cliente = @codigo OR p.cedula_cliente = @codigo) ${filtroFecha}
        AND (p.estado IS NULL OR p.estado <> 'CANCELADO')
    `)
    const row = result.recordset[0]
    res.json({
      success: true,
      data: { total: Number.parseFloat(row.total) || 0, cantidad: row.cantidad || 0 },
    })
  } catch (error) {
    console.error("Error total pedidos:", error.message)
    res.status(500).json({ success: false, message: "Error", data: { total: 0, cantidad: 0 } })
  }
})

app.get("/api/clientes/:codigo/visita/ultima", authenticateToken, async (req, res) => {
  try {
    const ruta = await connectRuta()
    await ensureVisitasTabla(ruta)
    const r = await ruta.request().input("cliente", sql.NVarChar, req.params.codigo).query(`
      SELECT TOP 1 id, estado_cliente, observacion, vendedor_nombre,
             CONVERT(VARCHAR(19), fecha, 120) AS fecha
      FROM visitas_clientes WHERE cliente_id = @cliente ORDER BY fecha DESC, id DESC
    `)
    if (r.recordset.length === 0) {
      return res.json({ success: true, data: null })
    }
    const v = r.recordset[0]
    res.json({
      success: true,
      data: {
        id: v.id,
        estadoCliente: v.estado_cliente,
        observacion: v.observacion || "",
        vendedorNombre: v.vendedor_nombre || "",
        fecha: v.fecha,
      },
    })
  } catch (error) {
    console.error("Error obteniendo última visita:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener la visita" })
  }
})

app.get("/api/clientes/:codigo/rutas", authenticateToken, async (req, res) => {
  try {
    const limite = Math.min(Number.parseInt(req.query.limite, 10) || 100, 500)
    const slpCode = getSlpCodeFromToken(req)

    const ruta = await connectRuta()
    const request = ruta.request()
      .input("limite", sql.Int, limite)
      .input("clienteId", sql.NVarChar, req.params.codigo)

    let filtroVendedor = ""
    if (slpCode !== null) {
      request.input("slpCode", sql.Int, slpCode)
      filtroVendedor = "AND vendedor_id = @slpCode"
    }

    const result = await request.query(`
      SELECT TOP (@limite) id, nombre, estado, cliente_id, ciudad, usuario_nombre,
             CONVERT(VARCHAR(19), fecha_programada, 126) AS fecha_programada,
             CONVERT(VARCHAR(5), hora_visita, 108) AS hora_visita,
             CONVERT(VARCHAR(19), fecha_creacion, 126) AS fecha_creacion,
             CONVERT(VARCHAR(19), fecha_actualizacion, 126) AS fecha_actualizacion
      FROM rutas
      WHERE cliente_id = @clienteId ${filtroVendedor}
      ORDER BY fecha_programada DESC, hora_visita ASC
    `)

    const rutas = result.recordset.map(mapRuta)
    const completadas = rutas.filter((r) => esCompletada(r.estado)).length
    const canceladas = rutas.filter((r) => esCancelada(r.estado)).length

    console.log(`Rutas cliente ${req.params.codigo}: ${rutas.length}`)
    res.json({
      success: true,
      data: {
        rutas,
        total: rutas.length,
        completadas,
        pendientes: rutas.length - completadas - canceladas,
      },
    })
  } catch (error) {
    console.error("Error obteniendo rutas del cliente:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener rutas del cliente" })
  }
})

const geocodeCache = new CacheTTL(2000, 30 * 24 * 60 * 60 * 1000)

function normalizarDireccion(dir) {
  return (dir || "")
    .replace(/\bKRA?\.?\s/gi, "Carrera ")
    .replace(/\bCRA?\.?\s/gi, "Carrera ")
    .replace(/\bCLL?\.?\s/gi, "Calle ")
    .replace(/\bAVD?A?\.?\s/gi, "Avenida ")
    .replace(/\bDG\.?\s/gi, "Diagonal ")
    .replace(/\bDIAG\.?\s/gi, "Diagonal ")
    .replace(/\bTV\.?\s/gi, "Transversal ")
    .replace(/\bTRANSV\.?\s/gi, "Transversal ")
    .replace(/\s+/g, " ")
    .trim()
}

async function nominatimSearch(q) {
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=co&q=${encodeURIComponent(q)}`
  const resp = await fetch(url, {
    headers: { "User-Agent": "OralPlus-Pedidos/1.0 (sistemas@oral-plus.com)" },
    signal: AbortSignal.timeout(4000),
  })
  if (!resp.ok) return null
  const arr = await resp.json()
  return Array.isArray(arr) && arr.length > 0 ? arr[0] : null
}

let googleGeocodeDisabled = false
async function googleGeocode(q) {
  const key = process.env.GOOGLE_MAPS_API_KEY
  if (!key || googleGeocodeDisabled) return null

  try {
    const url = `https://maps.googleapis.com/maps/api/geocode/json?region=co&address=${encodeURIComponent(q)}&key=${key}`
    const resp = await fetch(url, { signal: AbortSignal.timeout(4000) })
    const j = await resp.json()

    if (j.status === "OK" && j.results && j.results[0]) {
      const r = j.results[0]
      const lt = r.geometry.location_type
      const precision = lt === "ROOFTOP" || lt === "RANGE_INTERPOLATED" ? "exacta" : "via"
      return {
        lat: r.geometry.location.lat,
        lng: r.geometry.location.lng,
        formattedAddress: r.formatted_address || q,
        placeId: r.place_id || "",
        precision,
      }
    }

    if (j.status === "ZERO_RESULTS") return null

    console.log(`Google Geocoding no disponible (${j.status}: ${j.error_message || "sin detalle"}); se usa OpenStreetMap`)
    googleGeocodeDisabled = true
    return null
  } catch (e) {
    console.log("Error Google Geocoding:", e.message)
    googleGeocodeDisabled = true
    return null
  }
}

app.get("/api/clientes/:codigo/geocode", authenticateToken, async (req, res) => {
  try {
    let direccion = (req.query.address || "").toString().trim()

    if (!direccion) {
      const sap = await connectSAP()
      const r = await sap.request()
        .input("cardCode", sql.VarChar, req.params.codigo)
        .query("SELECT Address, City FROM OCRD WHERE CardCode = @cardCode")
      if (r.recordset.length > 0) {
        const c = r.recordset[0]
        direccion = [c.Address, c.City, "Colombia"].filter(Boolean).join(", ")
      }
    }

    if (!direccion) {
      return res.status(404).json({ success: false, message: "Cliente sin dirección" })
    }

    const cacheKey = direccion.toUpperCase()
    if (geocodeCache.has(cacheKey)) {
      return res.json({ success: true, data: geocodeCache.get(cacheKey) })
    }

    const partes = direccion.split(",").map((p) => normalizarDireccion(p)).filter(Boolean)
    const calle = partes[0] || ""
    const resto = partes.slice(1).join(", ")
    const viaMatch = calle.match(/^([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+\d+\s?[A-Za-z]?)/)
    const soloVia = viaMatch ? viaMatch[1].trim() : ""

    const google = await googleGeocode(partes.join(", "))
    if (google) {
      geocodeCache.set(cacheKey, google)
      console.log(`Geocode "${direccion}" -> ${google.lat},${google.lng} (google/${google.precision})`)
      return res.json({ success: true, data: google })
    }

    const intentos = [
      { q: partes.join(", "), precision: "exacta" },
      soloVia && resto ? { q: `${soloVia}, ${resto}`, precision: "via" } : null,
      resto ? { q: resto, precision: "ciudad" } : null,
    ].filter(Boolean)

    for (const intento of intentos) {
      const hit = await nominatimSearch(intento.q)
      if (hit) {
        const data = {
          lat: Number.parseFloat(hit.lat),
          lng: Number.parseFloat(hit.lon),
          formattedAddress: hit.display_name || direccion,
          placeId: String(hit.place_id || ""),
          precision: intento.precision,
        }
        geocodeCache.set(cacheKey, data)
        console.log(`Geocode "${direccion}" -> ${data.lat},${data.lng} (osm/${intento.precision})`)
        return res.json({ success: true, data })
      }
    }

    console.log(`Geocode sin resultados: "${direccion}"`)
    res.status(404).json({ success: false, message: "No se encontraron coordenadas para la dirección" })
  } catch (error) {
    console.error("Error geocodificando:", error.message)
    res.status(500).json({ success: false, message: "Error al geocodificar la dirección" })
  }
})

let anthropicClient = null
function getAnthropic() {
  if (!process.env.ANTHROPIC_API_KEY) return null
  if (!anthropicClient) {
    const Anthropic = require("@anthropic-ai/sdk")
    anthropicClient = new Anthropic()
  }
  return anthropicClient
}

const IA_SYSTEM_PROMPT = `Eres el asistente comercial de Oral-Plus (empresa colombiana de productos de higiene oral) para vendedores en ruta.
Ayudas al vendedor a preparar y ejecutar la visita a un cliente usando los datos reales que se te entregan (cartera, facturas, historial de compras, ruta programada).
Responde SIEMPRE en español, breve y accionable: máximo 5-6 viñetas cortas con emojis al inicio de cada una.
Prioriza: 1) recaudo de cartera vencida, 2) reposición de los productos que el cliente más compra, 3) reactivación si lleva tiempo sin comprar, 4) oportunidades de venta cruzada.
Usa cifras concretas de los datos (montos en pesos colombianos, días de mora, cantidades). No inventes datos que no estén en el contexto.`

async function contextoClienteIA(codigo) {
  const ctx = { cliente: null, facturasAbiertas: [], topProductos: [], ultimaCompra: null, proximasRutas: [] }

  const consultaSap = async (texto) => {
    const sap = await connectSAP()
    return sap.request().input("c", sql.VarChar, codigo).query(texto)
  }
  const consultaRuta = async (texto) => {
    const ruta = await connectRuta()
    return ruta.request().input("c", sql.NVarChar, codigo).query(texto)
  }

  const [rCliente, rFacturas, rProductos, rUltima, rRutas] = await Promise.allSettled([
    consultaSap(`
      SELECT CardCode, CardName, Address, City, Phone1, Balance
      FROM OCRD WHERE CardCode = @c
    `),
    consultaSap(`
      SELECT TOP 10 DocNum, CONVERT(VARCHAR(10), DocDate, 120) AS fecha,
             CONVERT(VARCHAR(10), DocDueDate, 120) AS vence,
             DocTotal, (DocTotal - PaidToDate) AS saldo,
             DATEDIFF(day, DocDueDate, GETDATE()) AS diasMora
      FROM OINV
      WHERE CardCode = @c AND DocStatus = 'O' AND (DocTotal - PaidToDate) > 0
      ORDER BY DocDueDate ASC
    `),
    consultaSap(`
      SELECT TOP 8 T1.ItemCode, T1.Dscription AS producto,
             SUM(T1.Quantity) AS cantidad,
             CONVERT(VARCHAR(10), MAX(T0.DocDate), 120) AS ultimaCompra
      FROM INV1 T1
      INNER JOIN OINV T0 ON T0.DocEntry = T1.DocEntry
      WHERE T0.CardCode = @c AND T0.DocDate >= DATEADD(month, -6, GETDATE())
      GROUP BY T1.ItemCode, T1.Dscription
      ORDER BY SUM(T1.Quantity) DESC
    `),
    consultaSap(`
      SELECT TOP 1 CONVERT(VARCHAR(10), DocDate, 120) AS fecha,
             DATEDIFF(day, DocDate, GETDATE()) AS diasSinComprar
      FROM OINV WHERE CardCode = @c ORDER BY DocDate DESC
    `),
    consultaRuta(`
      SELECT TOP 3 nombre, estado,
             CONVERT(VARCHAR(10), fecha_programada, 120) AS fecha,
             CONVERT(VARCHAR(5), hora_visita, 108) AS hora
      FROM rutas
      WHERE cliente_id = @c AND fecha_programada >= CAST(GETDATE() AS DATE)
      ORDER BY fecha_programada ASC
    `),
  ])

  const filas = (r, nombre) => {
    if (r.status === "fulfilled") return r.value.recordset
    console.log(`IA: contexto ${nombre} incompleto:`, r.reason && r.reason.message)
    return []
  }
  const cliente = filas(rCliente, "cliente")
  if (cliente.length > 0) ctx.cliente = cliente[0]
  ctx.facturasAbiertas = filas(rFacturas, "facturas")
  ctx.topProductos = filas(rProductos, "productos")
  const ultima = filas(rUltima, "ultima compra")
  if (ultima.length > 0) ctx.ultimaCompra = ultima[0]
  ctx.proximasRutas = filas(rRutas, "rutas")

  return ctx
}

function formatearPesos(v) {
  return "$" + Math.round(Number(v) || 0).toLocaleString("es-CO")
}

function contextoATexto(codigo, ctx, extra) {
  const lineas = [`DATOS DEL CLIENTE ${codigo}:`]

  if (ctx.cliente) {
    lineas.push(`- Nombre: ${ctx.cliente.CardName} | Ciudad: ${ctx.cliente.City || "?"} | Saldo total: ${formatearPesos(ctx.cliente.Balance)}`)
  }
  if (ctx.ultimaCompra) {
    lineas.push(`- Última compra: ${ctx.ultimaCompra.fecha} (hace ${ctx.ultimaCompra.diasSinComprar} días)`)
  }
  if (ctx.facturasAbiertas.length > 0) {
    lineas.push(`- Facturas abiertas (${ctx.facturasAbiertas.length}):`)
    for (const f of ctx.facturasAbiertas) {
      lineas.push(`  - #${f.DocNum} vence ${f.vence}, saldo ${formatearPesos(f.saldo)}${f.diasMora > 0 ? ` (VENCIDA hace ${f.diasMora} días)` : ""}`)
    }
  } else {
    lineas.push("- Sin facturas abiertas (cartera al día)")
  }
  if (ctx.topProductos.length > 0) {
    lineas.push("- Productos más comprados (últimos 6 meses):")
    for (const p of ctx.topProductos) {
      lineas.push(`  - ${p.producto} (${Math.round(p.cantidad)} und, última: ${p.ultimaCompra})`)
    }
  }
  if (ctx.proximasRutas.length > 0) {
    lineas.push("- Visitas programadas:")
    for (const r of ctx.proximasRutas) {
      lineas.push(`  - ${r.fecha}${r.hora ? " " + r.hora : ""}: ${r.nombre} [${r.estado}]`)
    }
  }
  if (extra && extra.ruta && extra.ruta.nombre) {
    lineas.push(`- Ruta actual: ${extra.ruta.nombre} (${extra.ruta.fechaProgramada || "sin fecha"}, estado: ${extra.ruta.estado || "?"})`)
  }

  return lineas.join("\n")
}

function sugerenciasFallback(ctx) {
  const s = []

  const vencidas = ctx.facturasAbiertas.filter((f) => f.diasMora > 0)
  if (vencidas.length > 0) {
    const total = vencidas.reduce((a, f) => a + Number(f.saldo || 0), 0)
    const maxMora = Math.max(...vencidas.map((f) => f.diasMora))
    s.push(`Prioriza el recaudo: ${vencidas.length} factura(s) vencida(s) por ${formatearPesos(total)} (la más antigua con ${maxMora} días de mora).`)
  } else if (ctx.facturasAbiertas.length > 0) {
    const total = ctx.facturasAbiertas.reduce((a, f) => a + Number(f.saldo || 0), 0)
    s.push(`Cartera al día: ${ctx.facturasAbiertas.length} factura(s) abiertas por ${formatearPesos(total)}, ninguna vencida.`)
  } else {
    s.push("Cliente sin cartera pendiente: buen momento para impulsar un pedido nuevo.")
  }

  if (ctx.ultimaCompra && ctx.ultimaCompra.diasSinComprar > 30) {
    s.push(`Lleva ${ctx.ultimaCompra.diasSinComprar} días sin comprar (última: ${ctx.ultimaCompra.fecha}): enfócate en reactivarlo.`)
  }

  if (ctx.topProductos.length > 0) {
    const top = ctx.topProductos.slice(0, 3).map((p) => p.producto).join(", ")
    s.push(`Sugiere reposición de sus productos frecuentes: ${top}.`)
  }

  if (ctx.proximasRutas.length > 0) {
    const r = ctx.proximasRutas[0]
    s.push(`Visita programada: ${r.fecha}${r.hora ? " a las " + r.hora : ""} (${r.estado}).`)
  }

  if (s.length === 0) {
    s.push("No hay datos históricos de este cliente. Aprovecha la visita para levantar información y ofrecer el portafolio.")
  }

  return s.join("\n")
}

async function preguntarClaude(contexto, instruccion) {
  const anthropic = getAnthropic()
  if (!anthropic) return null

  try {
    const msg = await anthropic.messages.create(
      {
        model: "claude-opus-4-8",
        max_tokens: 1024,
        system: IA_SYSTEM_PROMPT,
        messages: [{ role: "user", content: `${contexto}\n\n${instruccion}` }],
      },
      { timeout: 25000, maxRetries: 1 },
    )
    const texto = msg.content
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("")
      .trim()
    return texto || null
  } catch (e) {
    console.error("Error llamando a Claude:", e.message)
    return null
  }
}

const sugerenciasCache = new CacheTTL(500, 10 * 60 * 1000)

app.post("/api/clientes/:codigo/ia/sugerencias", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo

    const cacheado = req.body && req.body.forzar === true ? undefined : sugerenciasCache.get(codigo)
    if (cacheado) {
      return res.json({ success: true, data: { respuesta: cacheado.texto, fuente: cacheado.fuente } })
    }

    const ctx = await contextoClienteIA(codigo)
    const contexto = contextoATexto(codigo, ctx, req.body || {})

    let fuente = "ia"
    let texto = await preguntarClaude(
      contexto,
      "Genera las recomendaciones para la visita de hoy a este cliente.",
    )
    if (!texto) {
      fuente = "datos"
      texto = sugerenciasFallback(ctx)
    }

    sugerenciasCache.set(codigo, { texto, fuente })
    console.log(`Sugerencias ${codigo} (${fuente})`)
    res.json({ success: true, data: { respuesta: texto, fuente } })
  } catch (error) {
    console.error("Error generando sugerencias IA:", error.message)
    res.status(500).json({ success: false, message: "Error al generar sugerencias" })
  }
})

app.post("/api/clientes/:codigo/ia/chat", authenticateToken, async (req, res) => {
  try {
    const codigo = req.params.codigo
    const pregunta = (req.body?.pregunta || "").toString().trim()
    if (!pregunta) {
      return res.status(400).json({ success: false, message: "La pregunta es requerida" })
    }

    const ctx = await contextoClienteIA(codigo)
    const contexto = contextoATexto(codigo, ctx, req.body || {})

    let texto = await preguntarClaude(contexto, `Pregunta del vendedor: ${pregunta}`)
    if (!texto) {
      texto = `El asistente IA no está disponible. Datos del cliente:\n\n${sugerenciasFallback(ctx)}`
    }

    console.log(`Chat IA ${codigo}: "${pregunta.slice(0, 60)}"`)
    res.json({ success: true, data: { respuesta: texto } })
  } catch (error) {
    console.error("Error en chat IA:", error.message)
    res.status(500).json({ success: false, message: "Error al procesar la pregunta" })
  }
})

app.get("/api/test", (req, res) => {
  res.json({
    success: true,
    message: "API SkyPagos funcionando correctamente",
    timestamp: new Date().toISOString(),
    version: "1.0.0",
    database: pool ? "Conectada" : "Desconectada",
  })
})

app.get("/api/health", async (req, res) => {
  const status = { success: true, timestamp: new Date().toISOString(), databases: {} }

  try {
    await pool.request().query("SELECT 1 AS ok")
    status.databases.SkyPagos = { status: "Conectada" }
  } catch (e) {
    status.databases.SkyPagos = { status: "Error", error: e.message }
    status.success = false
  }

  try {
    await pedidosPool.request().query("SELECT 1 AS ok")
    status.databases.Pedidos = { status: "Conectada" }
  } catch (e) {
    status.databases.Pedidos = { status: "Error", error: e.message }
    status.success = false
  }

  res.status(status.success ? 200 : 500).json(status)
})

const requireSoporte = dispositivos.soporteMiddleware(jwt, JWT_SECRET)
dispositivos.registrarRutas(app, () => pedidosPool, sql, requireSoporte)

const catalogo = productos.crear({
  sql,
  getSapPool: connectSAP,
  getPedidosPool: () => pedidosPool,
  env: process.env,
  log: console,
})
catalogo.registrarRutas(app, { requireAuth: authenticateToken, requireSoporte })

clientesExtra.registrarRutas(app, {
  requireAuth: authenticateToken,
  getPedidosPool: () => pedidosPool,
  connectSAP,
  sql,
  serviceLayer: catalogo.repositorio.sl,
  limiteDesdeQuery,
  log: console,
})

evidencias.registrarRutas(app, {
  requireAuth: authenticateToken,
  getPedidosPool: () => pedidosPool,
  sql,
  log: console,
})

app.get("/api/usuarios", requireSoporte, async (req, res) => {
  try {
    const buscar = (req.query.buscar || "").toString().trim().toUpperCase()
    const avisos = []

    let vendedores = []
    try {
      const sap = await connectSAP()
      const r = await sap.request().query(`
        SELECT SlpCode, SlpName, Email, Telephone, Active
        FROM OSLP WHERE SlpCode > 0 ORDER BY SlpName
      `)
      vendedores = r.recordset.map((v) => ({
        tipo: "vendedor",
        id: String(v.SlpCode),
        codigo: `SKV${v.SlpCode}`,
        documento: String(v.SlpCode),
        nombre: (v.SlpName || "").trim(),
        email: v.Email || "",
        telefono: v.Telephone || "",
        activo: v.Active !== "N",
      }))
    } catch (e) {
      avisos.push("No se pudieron leer los vendedores de SAP")
    }

    let usuarios = []
    try {
      const r = await pool.request().query(`
        SELECT id, nombre, apellido, documento, telefono, email, estado
        FROM usuarios ORDER BY nombre
      `)
      usuarios = r.recordset.map((u) => ({
        tipo: "usuario",
        id: String(u.id),
        codigo: u.documento || String(u.id),
        documento: u.documento || "",
        nombre: `${u.nombre || ""} ${u.apellido || ""}`.trim(),
        email: u.email || "",
        telefono: u.telefono || "",
        activo: (u.estado || "ACTIVO") === "ACTIVO",
      }))
    } catch (e) {
      avisos.push("No se pudo leer la tabla de usuarios")
    }

    const dispositivosPor = new Map()
    try {
      const r = await pedidosPool.request().query(`
        SELECT id_servicio, estado, usuario_codigo, usuario_documento, plataforma,
               CONVERT(VARCHAR(19), fecha_ultimo_acceso, 120) AS fecha_ultimo_acceso
        FROM dbo.dispositivos
      `)
      for (const d of r.recordset) {
        const clave = `${d.usuario_codigo || ""}|${d.usuario_documento || ""}`
        if (!dispositivosPor.has(clave)) dispositivosPor.set(clave, [])
        dispositivosPor.get(clave).push({
          idServicio: d.id_servicio,
          estado: d.estado,
          plataforma: d.plataforma || "",
          ultimoAcceso: d.fecha_ultimo_acceso,
        })
      }
    } catch (e) {
      avisos.push("No se pudieron leer los dispositivos")
    }

    const todos = [...vendedores, ...usuarios].map((u) => {
      const dispositivosUsuario = dispositivosPor.get(`${u.id}|${u.documento}`) || []
      return {
        ...u,
        esSoporte: esSoporte(u.documento, u.nombre, u.tipo === "vendedor" ? u.codigo : null),
        dispositivos: dispositivosUsuario,
        dispositivosActivos: dispositivosUsuario.filter((d) => d.estado === "ACTIVO").length,
      }
    })

    const filtrados = buscar
      ? todos.filter((u) =>
          [u.nombre, u.codigo, u.documento, u.email].some((v) => (v || "").toUpperCase().includes(buscar)),
        )
      : todos

    res.json({
      success: true,
      data: filtrados,
      total: filtrados.length,
      soporte: SOPORTE_USUARIOS,
      avisos,
    })
  } catch (error) {
    console.error("Error listando usuarios:", error.message)
    res.status(500).json({ success: false, message: "Error al listar usuarios", data: [] })
  }
})

app.use((err, req, res, next) => {
  const status = err.status || err.statusCode || 500
  if (status >= 500) console.error("Error no manejado:", err)
  res.status(status).json({
    error: status >= 500 ? "Error interno del servidor" : "Solicitud inválida",
    message: status < 500 || process.env.NODE_ENV === "development" ? err.message : "Algo salió mal",
  })
})

app.use("*", (req, res) => {
  res.status(404).json({
    error: "Ruta no encontrada",
    message: `La ruta ${req.originalUrl} no existe`,
  })
})

async function startServer() {
  try {
    await connectDB()
    await connectPedidosDB()

    try {
      await dispositivos.ensureTablas(pedidosPool)
      await sesiones.ensureTabla(pedidosPool)
    } catch (e) {
      console.error("No se pudo inicializar dispositivos o sesiones:", e.message)
    }

    try {
      await catalogo.iniciar()
    } catch (e) {
      console.error("No se pudo inicializar el catálogo de productos:", e.message)
    }

    connectSAP().catch(() => {})
    connectRuta().catch((e) => console.error("BD Ruta no disponible al arrancar:", e.message))

    const server = app.listen(PORT, "0.0.0.0", () => {
      console.info(`API de pedidos escuchando en el puerto ${PORT}`)
      console.info(`Prueba: http://localhost:${PORT}/api/test`)
    })
    server.keepAliveTimeout = 65000
    server.headersTimeout = 66000
  } catch (error) {
    console.error("Error iniciando el servidor:", error)
    process.exit(1)
  }
}

startServer()

process.on("SIGINT", async () => {
  console.log("Cerrando servidor...")
  if (pool) {
    await pool.close()
    console.log("   SkyPagos cerrada")
  }
  if (pedidosPool) {
    await pedidosPool.close()
    console.log("   Pedidos cerrada")
  }
  if (sapPool) await sapPool.close().catch(() => {})
  if (rutaPool) await rutaPool.close().catch(() => {})
  process.exit(0)
})
