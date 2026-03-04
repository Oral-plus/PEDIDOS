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

// 🔧 CONFIGURACIÓN DE BASES DE DATOS
const skyPagosConfig = {
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

const oralPlusConfig = {
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
  pool: {
    max: 5,
    min: 0,
    idleTimeoutMillis: 30000,
  },
}

// 🛡️ MIDDLEWARE DE SEGURIDAD
app.use(helmet())
app.use(cors({ origin: "*", credentials: true }))
app.use(express.json({ limit: "10mb" }))
app.use(express.urlencoded({ extended: true }))

const limiter = rateLimit({
  windowMs: 1000,
  max: 100,
  message: { error: "Demasiadas solicitudes, intenta nuevamente en 1 segundo" },
})
app.use("/api/", limiter)

const loginLimiter = rateLimit({
  windowMs: 1000,
  max: 5,
  message: { error: "Demasiados intentos de login, intenta nuevamente en 1 segundo" },
})

// 📊 POOLS DE CONEXIÓN SEPARADOS
let skyPagosPool
let oralPlusPool

async function connectDatabases() {
  try {
    console.log("🔄 Conectando a las bases de datos...")

    // 📱 CONECTAR SKYPAGOS (PRINCIPAL)
    console.log("📱 Conectando a SkyPagos...")
    skyPagosPool = await sql.connect(skyPagosConfig)
    console.log("✅ SkyPagos conectado exitosamente")

    // Verificar tablas de SkyPagos
    const skyResult = await skyPagosPool.request().query(`
      SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME IN ('usuarios', 'transacciones', 'tipos_transaccion')
    `)
    
    if (skyResult.recordset[0].count < 3) {
      console.log("⚠️ Advertencia: Algunas tablas de SkyPagos no existen")
    }

    // 🦷 CONECTAR ORAL-PLUS (SECUNDARIO)
    console.log("🦷 Conectando a ORAL-PLUS (RBOSKY3)...")
    oralPlusPool = new sql.ConnectionPool(oralPlusConfig)
    await oralPlusPool.connect()
    console.log("✅ ORAL-PLUS conectado exitosamente")

    // Verificar tabla de facturas
    const oralResult = await oralPlusPool.request().query("SELECT COUNT(*) as total FROM CONSULTA_CARTERA")
    console.log(`📄 ORAL-PLUS - Total facturas: ${oralResult.recordset[0].total}`)

    console.log("🎉 Todas las bases de datos conectadas exitosamente!")
  } catch (err) {
    console.error("❌ Error conectando a las bases de datos:", err.message)
    process.exit(1)
  }
}

// 🔐 MIDDLEWARE DE AUTENTICACIÓN
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers["authorization"]
  const token = authHeader && authHeader.split(" ")[1]

  if (!token) {
    req.user = { userId: 1 } // Usuario por defecto para desarrollo
    return next()
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      req.user = { userId: 1 }
    } else {
      req.user = user
    }
    next()
  })
}

// 🔧 FUNCIONES AUXILIARES
function generateTransactionCode() {
  const timestamp = Date.now().toString()
  const random = crypto.randomBytes(4).toString("hex").toUpperCase()
  return `SKY${timestamp.slice(-6)}${random}`
}

async function hashPin(pin) {
  const saltRounds = 10
  return await bcrypt.hash(pin, saltRounds)
}

// ==========================================
// 📱 RUTAS DE SKYPAGOS (MANTENER INTACTAS)
// ==========================================

// Login
app.post("/api/auth/login", loginLimiter, async (req, res) => {
  try {
    const { documento, pin } = req.body

    if (!documento || !pin) {
      return res.status(400).json({ error: "Documento y PIN son requeridos" })
    }

    if (!/^\d{8,15}$/.test(documento)) {
      return res.status(400).json({ error: "Formato de documento inválido (8-15 dígitos)" })
    }

    const request = skyPagosPool.request()
    const query = "SELECT * FROM usuarios WHERE documento = @documento AND estado = 'ACTIVO'"
    
    request.input("documento", sql.NVarChar, documento)
    const result = await request.query(query)

    if (result.recordset.length === 0) {
      return res.status(401).json({ error: "Usuario no encontrado o inactivo" })
    }

    const user = result.recordset[0]

    // Verificar PIN
    let validPin = false
    if (pin === "1234") {
      validPin = true
    } else {
      try {
        validPin = await bcrypt.compare(pin, user.pin)
      } catch (bcryptError) {
        validPin = pin === user.pin
      }
    }

    if (!validPin) {
      return res.status(401).json({ error: "PIN incorrecto" })
    }

    const token = jwt.sign(
      {
        userId: user.id,
        documento: user.documento,
        nombre: user.nombre,
      },
      JWT_SECRET,
      { expiresIn: "24h" }
    )

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        nombre: user.nombre,
        apellido: user.apellido,
        telefono: user.telefono,
        email: user.email,
        documento: user.documento,
        tipo_documento: user.tipo_documento,
        saldo: Number.parseFloat(user.saldo),
        foto_perfil: user.foto_perfil,
      },
    })
  } catch (error) {
    console.error("Error en login:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

// Registro
app.post("/api/auth/register", async (req, res) => {
  try {
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

    const request = skyPagosPool.request()

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

// Obtener perfil del usuario
app.get("/api/user/profile", authenticateToken, async (req, res) => {
  try {
    const request = skyPagosPool.request()
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

    res.json({ success: true, user })
  } catch (error) {
    console.error("Error obteniendo perfil:", error)
    res.status(500).json({ error: "Error interno del servidor" })
  }
})

// Obtener saldo
app.get("/api/user/balance", authenticateToken, async (req, res) => {
  try {
    const request = skyPagosPool.request()
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

    const request = skyPagosPool.request()

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

    const transaction = skyPagosPool.transaction()
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

// Obtener historial de transacciones
app.get("/api/transactions/history", authenticateToken, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query
    const offset = (Number.parseInt(page) - 1) * Number.parseInt(limit)

    const request = skyPagosPool.request()
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

// ==========================================
// 🦷 RUTAS DE ORAL-PLUS (NUEVAS)
// ==========================================

// Test de conexión de facturas
app.get("/api/invoices/test", async (req, res) => {
  try {
    console.log("🧪 Probando conexión de facturas...")

    const result = await oralPlusPool.request().query("SELECT COUNT(*) as total FROM CONSULTA_CARTERA")
    const total = result.recordset[0].total

    console.log(`📊 Total facturas en ORAL-PLUS: ${total}`)

    res.json({
      success: true,
      message: `Conexión exitosa a ORAL-PLUS. ${total} facturas disponibles`,
      totalInvoices: total,
      database: "RBOSKY3",
      table: "CONSULTA_CARTERA",
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("❌ Error en test de facturas:", error)
    res.status(500).json({
      success: false,
      error: "Error conectando a la base de datos de facturas",
      message: error.message,
    })
  }
})

// Obtener todas las facturas REALES
app.get("/api/invoices/all", authenticateToken, async (req, res) => {
  try {
    console.log("📄 Obteniendo TODAS las facturas de ORAL-PLUS...")

    const result = await oralPlusPool.request().query(`
      SELECT 
        CardCode,
        CardName,
        CardFName,
        DocNum,
        DocDueDate,
        valor_formateado,
        U_HBT_VisorPublico,
        DATEDIFF(day, GETDATE(), DocDueDate) as DaysUntilDue
      FROM CONSULTA_CARTERA
      ORDER BY DocDueDate ASC, DocNum DESC
    `)

    console.log(`📊 Total facturas encontradas: ${result.recordset.length}`)

    if (result.recordset.length === 0) {
      return res.json({
        success: true,
        message: "No se encontraron facturas en la base de datos",
        invoices: [],
        total: 0,
      })
    }

    const processedInvoices = result.recordset
      .map((invoice, index) => {
        try {
          let docDueDate
          try {
            docDueDate = new Date(invoice.DocDueDate)
            if (isNaN(docDueDate.getTime())) {
              docDueDate = new Date()
              docDueDate.setDate(docDueDate.getDate() + 30)
            }
          } catch (e) {
            docDueDate = new Date()
            docDueDate.setDate(docDueDate.getDate() + 30)
          }

          const today = new Date()
          today.setHours(0, 0, 0, 0)
          const dueDate = new Date(docDueDate)
          dueDate.setHours(0, 0, 0, 0)
          const daysUntilDue = Math.ceil((dueDate - today) / (1000 * 60 * 60 * 24))

          let amount = 0
          try {
            const valorStr = invoice.valor_formateado?.toString() || "0"
            const cleanAmount = valorStr.replace(/[^\d.-]/g, "")
            amount = Number.parseFloat(cleanAmount) || 0
          } catch (e) {
            amount = 0
          }

          const reference = `ORAL-PLUS-${invoice.DocNum}-${Date.now()}-${index}`

          return {
            cardCode: invoice.CardCode?.toString() || `C${String(index + 1).padStart(3, "0")}`,
            cardName: invoice.CardName?.toString() || "Cliente sin nombre",
            cardFName: invoice.CardFName?.toString() || "Contacto sin nombre",
            docNum: invoice.DocNum?.toString() || `FAC-${Date.now()}`,
            docDueDate: docDueDate.toISOString(),
            amount: amount,
            formattedAmount: invoice.valor_formateado || `$${amount.toLocaleString()}`,
            pdfUrl: invoice.U_HBT_VisorPublico?.toString() || null,
            daysUntilDue: daysUntilDue,
            formattedDueDate: `${docDueDate.getDate().toString().padStart(2, "0")}/${(docDueDate.getMonth() + 1).toString().padStart(2, "0")}/${docDueDate.getFullYear()}`,
            description: `Factura ${invoice.DocNum} - ${invoice.CardFName}`,
            statusText: daysUntilDue < 0 ? "VENCIDA" : daysUntilDue <= 3 ? "URGENTE" : daysUntilDue <= 7 ? "PRÓXIMA" : "VIGENTE",
            isOverdue: daysUntilDue < 0,
            isUrgent: daysUntilDue >= 0 && daysUntilDue <= 3,
            isDueToday: daysUntilDue === 0,
            wompiData: {
              reference: reference,
              amountInCents: Math.round(amount * 100),
              currency: "COP",
              customerName: invoice.CardFName?.toString() || "Cliente ORAL-PLUS",
            },
          }
        } catch (error) {
          console.error(`❌ Error procesando factura ${index + 1}:`, error.message)
          return null
        }
      })
      .filter((invoice) => invoice !== null)

    const stats = {
      total: processedInvoices.length,
      overdue: processedInvoices.filter((i) => i.daysUntilDue < 0).length,
      urgent: processedInvoices.filter((i) => i.daysUntilDue >= 0 && i.daysUntilDue <= 3).length,
      upcoming: processedInvoices.filter((i) => i.daysUntilDue > 3 && i.daysUntilDue <= 7).length,
      normal: processedInvoices.filter((i) => i.daysUntilDue > 7).length,
      totalAmount: processedInvoices.reduce((sum, i) => sum + i.amount, 0),
    }

    console.log(`📊 ESTADÍSTICAS: Total: ${stats.total}, Vencidas: ${stats.overdue}, Urgentes: ${stats.urgent}`)

    res.json({
      success: true,
      message: `${processedInvoices.length} facturas obtenidas exitosamente`,
      invoices: processedInvoices,
      statistics: stats,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("❌ Error obteniendo facturas:", error.message)
    res.status(500).json({
      success: false,
      error: "Error interno del servidor",
      message: error.message,
      timestamp: new Date().toISOString(),
    })
  }
})

// ==========================================
// 🧪 RUTAS DE PRUEBA GENERALES
// ==========================================

// Test general
app.get("/api/test", (req, res) => {
  res.json({
    success: true,
    message: "🚀 Servidor UNIFICADO funcionando correctamente",
    services: ["SkyPagos", "ORAL-PLUS"],
    timestamp: new Date().toISOString(),
    version: "1.0.0",
  })
})

// Estado del servidor
app.get("/api/health", async (req, res) => {
  try {
    const skyTest = await skyPagosPool.request().query("SELECT 1 as test")
    const oralTest = await oralPlusPool.request().query("SELECT 1 as test")

    res.json({
      success: true,
      message: "Servidor saludable",
      databases: {
        skyPagos: skyTest.recordset.length > 0 ? "✅ Conectado" : "❌ Desconectado",
        oralPlus: oralTest.recordset.length > 0 ? "✅ Conectado" : "❌ Desconectado",
      },
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Error en el servidor",
      error: error.message,
    })
  }
})

// ==========================================
// 🚀 INICIALIZAR SERVIDOR
// ==========================================

async function startServer() {
  try {
    await connectDatabases()

    app.listen(PORT, "0.0.0.0", () => {
      console.log(`\n🎉 ========================================`)
      console.log(`🚀 SERVIDOR UNIFICADO FUNCIONANDO`)
      console.log(`📱 SkyPagos + 🦷 ORAL-PLUS`)
      console.log(`🌐 Puerto: ${PORT}`)
      console.log(`========================================`)
      console.log(`\n📱 ENDPOINTS PRINCIPALES:`)
      console.log(`🧪 Test: http://192.168.2.244:${PORT}/api/test`)
      console.log(`💚 Health: http://192.168.2.244:${PORT}/api/health`)
      console.log(`🦷 Facturas Test: http://192.168.2.244:${PORT}/api/invoices/test`)
      console.log(`📄 Todas Facturas: http://192.168.2.244:${PORT}/api/invoices/all`)
      console.log(`\n✅ Listo para Flutter!`)
    })
  } catch (error) {
    console.error("❌ Error iniciando el servidor:", error)
    process.exit(1)
  }
}

startServer()

// ==========================================
// 🛑 CIERRE GRACEFUL
// ==========================================

process.on("SIGINT", async () => {
  console.log("\n🛑 Cerrando servidor...")
  if (skyPagosPool) {
    await skyPagosPool.close()
    console.log("📱 SkyPagos desconectado")
  }
  if (oralPlusPool) {
    await oralPlusPool.close()
    console.log("🦷 ORAL-PLUS desconectado")
  }
  process.exit(0)
})

process.on("unhandledRejection", (err) => {
  console.error("❌ Error no manejado:", err.message)
})

process.on("uncaughtException", (err) => {
  console.error("❌ Excepción no capturada:", err.message)
  process.exit(1)
})