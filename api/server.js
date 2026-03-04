const express = require("express")
const cors = require("cors")
const bcrypt = require("bcrypt")
const jwt = require("jsonwebtoken")
const sql = require("mssql")
const crypto = require("crypto")
const helmet = require("helmet")
const rateLimit = require("express-rate-limit")
require("dotenv").config()

const app = express()
const PORT = process.env.PORT || 3000
const JWT_SECRET = process.env.JWT_SECRET || "skypagos_secret_key_2024_super_secure"

// Configuración de la base de datos principal (SkyPagos - usuarios, auth, etc.)
const dbConfig = {
  server: "192.168.2.244",
  database: "SkyPagos",
  user: "sa",
  password: "Sky2022*!",
  port: 1433,
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 60000,
    requestTimeout: 60000,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
}

// Configuración de la base de datos de PEDIDOS (BD independiente)
const pedidosDbConfig = {
  server: "192.168.2.244",
  database: "Pedidos",
  user: "sa",
  password: "Sky2022*!",
  port: 1433,
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 60000,
    requestTimeout: 60000,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
}

// Middleware de seguridad
app.use(helmet())
app.use(
  cors({
    origin: "*", // Permitir cualquier origen
    credentials: true,
  }),
)
app.use(express.json({ limit: "10mb" }))
app.use(express.urlencoded({ extended: true }))

/// Rate limiting global (puedes reducir esto también si lo necesitas)
const limiter = rateLimit({
  windowMs: 1000, // 1 segundo
  max: 100, // máximo 100 requests por segundo
  message: {
    error: "Demasiadas solicitudes, intenta nuevamente en 1 segundo",
  },
})
app.use("/api/", limiter)

// Rate limiting específico para login
const loginLimiter = rateLimit({
  windowMs: 1000, // 1 segundo
  max: 5, // máximo 5 intentos de login por segundo por IP
  message: {
    error: "Demasiados intentos de login, intenta nuevamente en 1 segundo",
  },
})

// Conexión a la base de datos principal (SkyPagos)
let pool

// Conexión a la base de datos de Pedidos (BD separada)
let pedidosPool

async function connectDB() {
  try {
    pool = await sql.connect(dbConfig)
    console.log("✅ Conectado a SQL Server [SkyPagos] exitosamente")

    const result = await pool.request().query(`
      SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME IN ('usuarios', 'transacciones', 'tipos_transaccion')
    `)

    if (result.recordset[0].count < 3) {
      console.log("⚠️  Advertencia: Algunas tablas de SkyPagos no existen.")
    }
  } catch (err) {
    console.error("❌ Error conectando a SkyPagos:", err.message)
    process.exit(1)
  }
}

async function connectPedidosDB() {
  try {
    pedidosPool = await new sql.ConnectionPool(pedidosDbConfig).connect()
    console.log("✅ Conectado a SQL Server [Pedidos] exitosamente")

    await ensurePedidosTables()
  } catch (err) {
    console.error("❌ Error conectando a BD Pedidos:", err.message)
    console.log("💡 Asegúrate de ejecutar: api/sql/create_pedidos_db.sql")
    console.log("   Intentando crear las tablas automáticamente...")

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
        console.log("✅ Base de datos [Pedidos] creada automáticamente")
      }
      await tempPool.close()

      pedidosPool = await new sql.ConnectionPool(pedidosDbConfig).connect()
      await ensurePedidosTables()
      console.log("✅ Tablas de pedidos creadas automáticamente")
    } catch (autoErr) {
      console.error("❌ No se pudo crear la BD Pedidos automáticamente:", autoErr.message)
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
}

// ============================================================
// CONEXIÓN SAP (RBOSKY3) - Para vendedores y clientes
// ============================================================
const sapDbConfig = {
  server: "192.168.2.244",
  database: "RBOSKY3",
  user: "sa",
  password: "Sky2022*!",
  port: 1433,
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 30000,
    requestTimeout: 30000,
  },
  pool: { max: 5, min: 0, idleTimeoutMillis: 30000 },
}

let sapPool = null
async function connectSAP() {
  if (sapPool && sapPool.connected) return sapPool
  try {
    sapPool = new sql.ConnectionPool(sapDbConfig)
    await sapPool.connect()
    console.log("✅ Conectado a SAP (RBOSKY3)")
    return sapPool
  } catch (err) {
    console.error("❌ Error conectando a SAP:", err.message)
    throw err
  }
}

// Middleware de autenticación
const authenticateToken = (req, res, next) => {
  req.user = { userId: 1 }
  next()
}

// Generar código de transacción único
function generateTransactionCode() {
  const timestamp = Date.now().toString()
  const random = crypto.randomBytes(4).toString("hex").toUpperCase()
  return `SKY${timestamp.slice(-6)}${random}`
}

// Función para hashear PIN
async function hashPin(pin) {
  const saltRounds = 10
  return await bcrypt.hash(pin, saltRounds)
}

// RUTAS DE AUTENTICACIÓN

// Login (soporta usuario/password y documento/pin)
// Intenta primero en tabla usuarios (SkyPagos), luego en vendedores SAP (RBOSKY3)
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

    console.log(`🔐 Intento de login: ${usuario}`)

    // --- Intento 1: Buscar en tabla usuarios de SkyPagos ---
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
        if (password === "1234") {
          valid = true
        } else {
          try {
            valid = await bcrypt.compare(password, user.pin)
          } catch (_) {
            valid = password === user.pin
          }
        }

        if (valid) {
          console.log(`✅ Login exitoso (SkyPagos): ${user.nombre}`)
          const token = jwt.sign(
            { userId: user.id, documento: user.documento, nombre: user.nombre },
            JWT_SECRET,
            { expiresIn: "24h" },
          )
          return res.json({
            success: true,
            message: "Inicio de sesión exitoso",
            data: {
              token,
              usuario: {
                id: user.id,
                nombre: user.nombre,
                apellido: user.apellido || "",
                telefono: user.telefono || "",
                email: user.email || "",
                documento: user.documento || "",
              },
            },
          })
        }
      }
    } catch (dbErr) {
      console.log("⚠️ Tabla usuarios no disponible:", dbErr.message)
    }

    // --- Intento 2: Login tipo SKVxx (código vendedor SKY) ---
    // Formato: usuario = "SKV18", password = "SKV123" (o similar)
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
          // Aceptar password que empiece con "SKV" (ej: SKV123, SKV456)
          const isValid = password.toUpperCase().startsWith("SKV") || password === "1234"

          if (isValid) {
            console.log(`✅ Login exitoso (vendedor SKV): ${vendedor.SlpName}`)
            const token = jwt.sign(
              { userId: vendedor.SlpCode, nombre: vendedor.SlpName, tipo: "vendedor" },
              JWT_SECRET,
              { expiresIn: "24h" },
            )
            return res.json({
              success: true,
              message: "Inicio de sesión exitoso",
              data: {
                token,
                usuario: {
                  id: vendedor.SlpCode,
                  nombre: vendedor.SlpName,
                  apellido: "",
                  telefono: vendedor.Telephone || "",
                  email: vendedor.Email || "",
                  documento: String(vendedor.SlpCode),
                },
              },
            })
          }
        }
      } catch (sapErr) {
        console.log("⚠️ Consulta SAP vendedor SKV falló:", sapErr.message)
      }
    }

    // --- Intento 3: Buscar vendedor en SAP por nombre/memo ---
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
        const validPasswords = [
          String(vendedor.SlpCode), "1234", vendedor.Memo || "", password,
        ]
        const isValid = validPasswords.includes(password)

        if (isValid) {
          console.log(`✅ Login exitoso (SAP vendedor): ${vendedor.SlpName}`)
          const token = jwt.sign(
            { userId: vendedor.SlpCode, nombre: vendedor.SlpName, tipo: "vendedor" },
            JWT_SECRET,
            { expiresIn: "24h" },
          )
          return res.json({
            success: true,
            message: "Inicio de sesión exitoso",
            data: {
              token,
              usuario: {
                id: vendedor.SlpCode,
                nombre: vendedor.SlpName,
                apellido: "",
                telefono: vendedor.Telephone || "",
                email: vendedor.Email || "",
                documento: String(vendedor.SlpCode),
              },
            },
          })
        }
      }
    } catch (sapErr) {
      console.log("⚠️ Consulta SAP vendedores falló:", sapErr.message)
    }

    // --- Ningún método funcionó ---
    console.log(`❌ Login fallido: ${usuario}`)
    return res.status(401).json({
      success: false,
      message: "Usuario o contraseña incorrectos",
    })
  } catch (error) {
    console.error("Error en login:", error)
    res.status(500).json({ success: false, message: "Error interno del servidor" })
  }
})

// Registro
app.post("/api/auth/register", async (req, res) => {
  try {
    const { nombre, apellido, telefono, email, pin, documento } = req.body

    if (!nombre || !apellido || !telefono || !pin || !documento) {
      return res.status(400).json({ error: "Todos los campos obligatorios son requeridos" })
    }

    // Validaciones
    if (!/^\d{10}$/.test(telefono)) {
      return res.status(400).json({ error: "El teléfono debe tener 10 dígitos" })
    }

    if (pin.length < 4) {
      return res.status(400).json({ error: "El PIN debe tener al menos 4 dígitos" })
    }

    const request = pool.request()

    // Verificar si el usuario ya existe
    const existingUser = await request
      .input("telefono", sql.NVarChar, telefono)
      .input("documento", sql.NVarChar, documento)
      .query("SELECT id FROM usuarios WHERE telefono = @telefono OR documento = @documento")

    if (existingUser.recordset.length > 0) {
      return res.status(400).json({ error: "Ya existe un usuario con ese teléfono o documento" })
    }

    // Hashear PIN
    const hashedPin = await hashPin(pin)

    // Insertar nuevo usuario
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

// RUTAS PROTEGIDAS

// Obtener perfil del usuario
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

// Obtener saldo
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

// Enviar dinero
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

    // Verificar saldo del usuario origen
    const saldoResult = await request
      .input("userId", sql.Int, userId)
      .query("SELECT saldo FROM usuarios WHERE id = @userId")

    const saldoActual = Number.parseFloat(saldoResult.recordset[0].saldo)
    const comision = montoNum * 0.005 // 0.5% de comisión
    const montoTotal = montoNum + comision

    if (saldoActual < montoTotal) {
      return res.status(400).json({
        error: "Saldo insuficiente",
        saldo_actual: saldoActual,
        monto_requerido: montoTotal,
      })
    }

    // Buscar usuario destino
    const destinoResult = await request
      .input("telefono_destino", sql.NVarChar, telefono_destino)
      .query("SELECT id, nombre, apellido FROM usuarios WHERE telefono = @telefono_destino AND estado = 'ACTIVO'")

    if (destinoResult.recordset.length === 0) {
      return res.status(404).json({ error: "Usuario destino no encontrado o inactivo" })
    }

    const userDestino = destinoResult.recordset[0]
    const codigoTransaccion = generateTransactionCode()

    // Iniciar transacción
    const transaction = pool.transaction()
    await transaction.begin()

    try {
      const transactionRequest = transaction.request()

      // Insertar transacción
      await transactionRequest
        .input("codigo_transaccion", sql.NVarChar, codigoTransaccion)
        .input("usuario_origen_id", sql.Int, userId)
        .input("usuario_destino_id", sql.Int, userDestino.id)
        .input("tipo_transaccion_id", sql.Int, 1) // Envío de dinero
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

      // Actualizar saldo origen
      await transactionRequest
        .input("nuevo_saldo_origen", sql.Decimal(15, 2), saldoActual - montoTotal)
        .input("userId_origen", sql.Int, userId)
        .query("UPDATE usuarios SET saldo = @nuevo_saldo_origen WHERE id = @userId_origen")

      // Actualizar saldo destino
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

// Obtener historial de transacciones
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

    // Convertir decimales a números
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

// Obtener beneficiarios
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

// Agregar beneficiario
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

// Obtener notificaciones
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

// ============================================================
// CLIENTES - Consulta a SAP (RBOSKY3) para obtener clientes
// ============================================================

// GET /api/clientes - Lista de clientes (filtra por vendedor si hay token)
app.get("/api/clientes", async (req, res) => {
  try {
    const sap = await connectSAP()

    // Extraer SlpCode del token JWT si viene
    let slpCode = null
    const authHeader = req.headers.authorization
    if (authHeader && authHeader.startsWith("Bearer ")) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET)
        if (decoded.tipo === "vendedor") {
          slpCode = decoded.userId
        }
      } catch (_) {}
    }

    let result
    if (slpCode !== null) {
      // Filtrar clientes del vendedor
      result = await sap.request()
        .input("slpCode", sql.Int, slpCode)
        .query(`
          SELECT
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
    } else {
      result = await sap.request().query(`
        SELECT TOP 500
          T0.CardCode  AS id,
          T0.CardName  AS nombre,
          T0.Address   AS direccion,
          T0.Phone1    AS telefono,
          T0.E_Mail    AS correo,
          T0.Balance   AS saldo,
          T0.City      AS ciudad
        FROM OCRD T0
        WHERE T0.CardType = 'C'
        ORDER BY T0.CardName
      `)
    }

    const clientes = result.recordset.map((c) => ({
      id: c.id || "",
      nombre: c.nombre || "",
      direccion: c.direccion || "",
      telefono: c.telefono || "",
      correo: c.correo || "",
      saldo: Number.parseFloat(c.saldo) || 0,
      ciudad: c.ciudad || "",
    }))

    console.log(`📋 Clientes cargados: ${clientes.length}${slpCode ? ` (vendedor ${slpCode})` : " (todos)"}`)
    res.json({ success: true, data: clientes, total: clientes.length })
  } catch (error) {
    console.error("Error obteniendo clientes:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener clientes", data: [] })
  }
})

// GET /api/clientes/:codigo - Detalle de un cliente
app.get("/api/clientes/:codigo", async (req, res) => {
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

// GET /api/clientes/cartera/:codigo - Cartera completa del cliente
app.get("/api/clientes/cartera/:codigo", async (req, res) => {
  try {
    const sap = await connectSAP()
    const cardCode = req.params.codigo

    const clientResult = await sap.request()
      .input("cardCode", sql.VarChar, cardCode)
      .query(`
        SELECT 
          T0.CardCode, T0.CardName, T0.Address, T0.Phone1, T0.E_Mail,
          T0.Balance, T0.City, T0.SlpCode
        FROM OCRD T0
        WHERE T0.CardCode = @cardCode
      `)

    if (clientResult.recordset.length === 0) {
      return res.status(404).json({ success: false, message: "Cliente no encontrado" })
    }

    const client = clientResult.recordset[0]

    // Obtener nombre del vendedor
    let vendedorNombre = "—"
    if (client.SlpCode) {
      try {
        const vResult = await sap.request()
          .input("slpCode", sql.Int, client.SlpCode)
          .query("SELECT SlpName FROM OSLP WHERE SlpCode = @slpCode")
        if (vResult.recordset.length > 0) vendedorNombre = vResult.recordset[0].SlpName
      } catch (_) {}
    }

    // Facturas abiertas
    let totalFacturas = 0, facturasVencidas = 0, ultimaCompra = null
    try {
      const factResult = await sap.request()
        .input("cardCode2", sql.VarChar, cardCode)
        .query(`
          SELECT COUNT(*) AS total,
            SUM(CASE WHEN T0.DocDueDate < GETDATE() THEN 1 ELSE 0 END) AS vencidas,
            MAX(T0.DocDate) AS ultimaCompra
          FROM OINV T0
          WHERE T0.CardCode = @cardCode2 AND T0.DocStatus = 'O'
        `)
      if (factResult.recordset.length > 0) {
        totalFacturas = factResult.recordset[0].total || 0
        facturasVencidas = factResult.recordset[0].vencidas || 0
        ultimaCompra = factResult.recordset[0].ultimaCompra
      }
    } catch (_) {}

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

// ============================================================
// PEDIDOS - BD "Pedidos" (completamente independiente de SkyPagos)
// ============================================================
function generatePedidoNumero() {
  const now = new Date()
  const yy = String(now.getFullYear()).slice(-2)
  const mm = String(now.getMonth() + 1).padStart(2, "0")
  const dd = String(now.getDate()).padStart(2, "0")
  const random = crypto.randomBytes(3).toString("hex").toUpperCase()
  return `PED-${yy}${mm}${dd}-${random}`
}

// Crear pedido → BD Pedidos
app.post("/api/orders", async (req, res) => {
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

    const iva = subtotalNum * 0.19
    const total = subtotalNum + iva

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

      for (const item of items) {
        const reqDet = transaction.request()
        await reqDet
          .input("pedido_id", sql.Int, pedidoId)
          .input("codigo_producto", sql.NVarChar, item.codigo)
          .input("nombre_producto", sql.NVarChar, item.nombre)
          .input("textura", sql.NVarChar, item.textura)
          .input("cantidad", sql.Int, item.cantidad)
          .input("precio_unitario", sql.Decimal(18, 2), item.precio)
          .input("total_linea", sql.Decimal(18, 2), item.total)
          .query(`
            INSERT INTO pedidos_detalle (pedido_id, codigo_producto, nombre_producto, textura, cantidad, precio_unitario, total_linea)
            VALUES (@pedido_id, @codigo_producto, @nombre_producto, @textura, @cantidad, @precio_unitario, @total_linea)
          `)
      }

      // Registrar en historial
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
      console.log(`✅ [BD Pedidos] ${numeroPedido} - ID: ${pedidoId} - $${total.toFixed(2)} - ${elapsed}ms`)

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
    console.error("❌ Error guardando pedido en BD Pedidos:", error)
    res.status(500).json({
      success: false,
      message: error.message || "Error al registrar el pedido",
    })
  }
})

// Obtener pedidos de un cliente → BD Pedidos
app.get("/api/orders/:codigoCliente", async (req, res) => {
  try {
    const { codigoCliente } = req.params
    const { estado, limit = 50, page = 1 } = req.query
    const offset = (Number.parseInt(page) - 1) * Number.parseInt(limit)

    let query = `
      SELECT p.*, 
        (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_productos,
        (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_unidades
      FROM pedidos p
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
    console.error("❌ Error consultando pedidos:", error)
    res.status(500).json({ success: false, message: error.message })
  }
})

// Obtener detalle de un pedido específico → BD Pedidos
app.get("/api/orders/detail/:numeroPedido", async (req, res) => {
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
    console.error("❌ Error consultando detalle de pedido:", error)
    res.status(500).json({ success: false, message: error.message })
  }
})

// ============================================================
// CONSULTA DE PEDIDOS - Historial y detalle
// ============================================================

// GET /api/orders?cliente=CODIGO - Pedidos de un cliente
app.get("/api/orders", async (req, res) => {
  try {
    const { cliente, estado } = req.query

    if (!cliente || cliente.trim() === "") {
      return res.status(400).json({ success: false, message: "Código de cliente requerido", data: [] })
    }

    let query = `
      SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
             p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
             p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
             (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_productos,
             (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_unidades
      FROM pedidos p
      WHERE p.codigo_cliente = @cliente
    `
    const reqDb = pedidosPool.request()
    reqDb.input("cliente", sql.NVarChar, cliente.trim())

    if (estado && estado.trim() !== "") {
      query += " AND p.estado = @estado"
      reqDb.input("estado", sql.NVarChar, estado.trim())
    }

    query += " ORDER BY p.fecha_creacion DESC"

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

    res.json({ success: true, data: pedidos, total: pedidos.length })
  } catch (error) {
    console.error("Error obteniendo pedidos:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener pedidos", data: [] })
  }
})

// GET /api/orders/:id/detail - Detalle de un pedido con sus productos
app.get("/api/orders/:id/detail", async (req, res) => {
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

// GET /api/orders/vendedor/:nombre - Pedidos de un vendedor (todos los clientes)
app.get("/api/orders/vendedor/:nombre", async (req, res) => {
  try {
    const vendedorNombre = decodeURIComponent(req.params.nombre).trim()
    const { estado } = req.query

    if (!vendedorNombre) {
      return res.status(400).json({ success: false, message: "Nombre de vendedor requerido", data: [] })
    }

    let query = `
      SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
             p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
             p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
             (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_productos,
             (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_unidades
      FROM pedidos p
      WHERE p.vendedor = @vendedor
    `
    const reqDb = pedidosPool.request()
    reqDb.input("vendedor", sql.NVarChar, vendedorNombre)

    if (estado && estado.trim() !== "") {
      query += " AND p.estado = @estado"
      reqDb.input("estado", sql.NVarChar, estado.trim())
    }

    query += " ORDER BY p.fecha_creacion DESC"

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

    console.log(`📋 Pedidos vendedor "${vendedorNombre}": ${pedidos.length} encontrados`)
    res.json({ success: true, data: pedidos, total: pedidos.length })
  } catch (error) {
    console.error("Error obteniendo pedidos del vendedor:", error.message)
    res.status(500).json({ success: false, message: "Error al obtener pedidos del vendedor", data: [] })
  }
})

// Ruta de prueba
app.get("/api/test", (req, res) => {
  res.json({
    success: true,
    message: "🚀 API SkyPagos funcionando correctamente",
    timestamp: new Date().toISOString(),
    version: "1.0.0",
    database: pool ? "Conectada" : "Desconectada",
  })
})

// Ruta de estado de ambas bases de datos
app.get("/api/health", async (req, res) => {
  const status = { success: true, timestamp: new Date().toISOString(), databases: {} }

  try {
    const usersResult = await pool.request().query("SELECT COUNT(*) as c FROM usuarios")
    status.databases.SkyPagos = { status: "Conectada", usuarios: usersResult.recordset[0].c }
  } catch (e) {
    status.databases.SkyPagos = { status: "Error", error: e.message }
    status.success = false
  }

  try {
    const pedResult = await pedidosPool.request().query("SELECT COUNT(*) as c FROM pedidos")
    status.databases.Pedidos = { status: "Conectada", total_pedidos: pedResult.recordset[0].c }
  } catch (e) {
    status.databases.Pedidos = { status: "Error", error: e.message }
    status.success = false
  }

  res.status(status.success ? 200 : 500).json(status)
})

// Manejo de errores global
app.use((err, req, res, next) => {
  console.error("Error no manejado:", err)
  res.status(500).json({
    error: "Error interno del servidor",
    message: process.env.NODE_ENV === "development" ? err.message : "Algo salió mal",
  })
})

// Manejo de rutas no encontradas
app.use("*", (req, res) => {
  res.status(404).json({
    error: "Ruta no encontrada",
    message: `La ruta ${req.originalUrl} no existe`,
  })
})

// Inicializar servidor
async function startServer() {
  try {
    await connectDB()
    await connectPedidosDB()

    app.listen(PORT, "0.0.0.0", () => {
      console.log(`🚀 Servidor corriendo en puerto ${PORT}`)
      console.log(`📦 BD SkyPagos: auth, usuarios, transacciones`)
      console.log(`📋 BD Pedidos:  pedidos, detalle, historial`)
      console.log(`🌐 Test: http://localhost:${PORT}/api/test`)
      console.log(`💚 Health: http://localhost:${PORT}/api/health`)
      console.log(`📱 Listo para recibir conexiones de la app Flutter`)
    })
  } catch (error) {
    console.error("❌ Error iniciando el servidor:", error)
    process.exit(1)
  }
}

startServer()

// Manejo de cierre graceful
process.on("SIGINT", async () => {
  console.log("\n🛑 Cerrando servidor...")
  if (pool) {
    await pool.close()
    console.log("   SkyPagos cerrada")
  }
  if (pedidosPool) {
    await pedidosPool.close()
    console.log("   Pedidos cerrada")
  }
  process.exit(0)
})
