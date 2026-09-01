const express = require("express")
const sql = require("mssql")
const cors = require("cors")
const os = require("os")
const { exec } = require("child_process")
require("dotenv").config()

const app = express()
const port = 3005

app.use(cors())
app.use(express.json())

const dbConfig = {
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  server: process.env.DB_SERVER,
  database: process.env.SAP_DB_NAME || "RBOSKY3",
  port: parseInt(process.env.DB_PORT || "1433", 10),
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true,
    connectTimeout: 30000,
    requestTimeout: 30000,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
}

let globalPool = null

async function connectToDatabase() {
  if (globalPool && globalPool.connected) {
    return globalPool
  }

  try {
    console.log("Conectando a la base de datos...")
    console.log(`Servidor: ${dbConfig.server}:${dbConfig.port}`)
    console.log(`Base de datos: ${dbConfig.database}`)
    console.log(`Usuario: ${dbConfig.user}`)

    globalPool = new sql.ConnectionPool(dbConfig)
    await globalPool.connect()

    console.log("Conectado a SQL Server exitosamente")

    const testResult = await globalPool.request().query(`
      SELECT COUNT(*) as total 
      FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME = 'CONSULTA_CARTERA'
    `)

    if (testResult.recordset[0].total === 0) {
      console.log("ADVERTENCIA: Tabla CONSULTA_CARTERA no encontrada")
    } else {
      const countResult = await globalPool.request().query("SELECT COUNT(*) as total FROM CONSULTA_CARTERA")
      console.log(`Total de registros en CONSULTA_CARTERA: ${countResult.recordset[0].total}`)
    }

    return globalPool
  } catch (err) {
    console.error("Error conectando a la base de datos:", err.message)
    console.log("Verifica:")
    console.log("   - Que SQL Server esté ejecutándose")
    console.log("   - Las credenciales sean correctas")
    console.log("   - El servidor sea accesible desde esta máquina")
    console.log("   - El puerto 1433 esté abierto")
    throw err
  }
}

function formatDate(date) {
  if (!date) return ""
  const d = new Date(date)
  return d.toLocaleDateString("es-CO")
}

function formatCurrency(amount) {
  if (!amount) return "$0"
  return new Intl.NumberFormat("es-CO", {
    style: "currency",
    currency: "COP",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount)
}

function calculateDaysUntilDue(dueDate) {
  if (!dueDate) return 0
  const today = new Date()
  const due = new Date(dueDate)
  const diffTime = due - today
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
  return diffDays
}

function getInvoiceStatus(daysUntilDue) {
  if (daysUntilDue < 0) return "Vencida"
  if (daysUntilDue <= 3) return "Urgente"
  if (daysUntilDue <= 7) return "Próxima"
  return "Vigente"
}

function getStatusIcon(status) {
  switch (status) {
    case "Vencida":
      return "warning"
    case "Urgente":
      return "schedule"
    case "Próxima":
      return "schedule"
    default:
      return "check_circle"
  }
}

function getPriority(status) {
  switch (status) {
    case "Vencida":
      return 1
    case "Urgente":
      return 2
    case "Próxima":
      return 3
    default:
      return 4
  }
}

function getNetworkIPs() {
  const interfaces = os.networkInterfaces()
  const ips = []

  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === "IPv4" && !iface.internal) {
        ips.push({
          interface: name,
          ip: iface.address,
          url: `http://${iface.address}:${port}/api`,
        })
      }
    }
  }

  return ips
}

app.get("/api/invoices/by-cardcode/:cardcode", async (req, res) => {
  const startTime = Date.now()

  try {
    const cardCode = req.params.cardcode.trim()

    console.log(`[${new Date().toISOString()}] Consultando facturas para CardCode: ${cardCode}`)
    console.log(`Equivalente SQL: SELECT * FROM CONSULTA_CARTERA WHERE CardCode = '${cardCode}'`)

    if (!cardCode) {
      return res.status(400).json({
        success: false,
        error: "CardCode es requerido",
        message: "Debe proporcionar un CardCode válido",
        timestamp: new Date().toISOString(),
      })
    }

    const pool = await connectToDatabase()

    const result = await pool
      .request()
      .input("cardCode", sql.VarChar, cardCode)
      .query("SELECT * FROM CONSULTA_CARTERA WHERE CardCode = @cardCode")

    const queryTime = Date.now() - startTime
    console.log(`Registros encontrados: ${result.recordset.length} (${queryTime}ms)`)

    if (result.recordset.length === 0) {
      console.log(`Usuario a paz y salvo: ${cardCode}`)
      return res.json({
        success: true,
        message: "Te encuentras a paz y salvo",
        cardCode: cardCode,
        count: 0,
        invoices: [],
        queryTime: queryTime,
        timestamp: new Date().toISOString(),
      })
    }

    const invoices = result.recordset.map((row) => {
      const daysUntilDue = calculateDaysUntilDue(row.DocDueDate)
      const status = getInvoiceStatus(daysUntilDue)
      const formattedAmount = formatCurrency(row.valor_formateado || 0)

      const amountInCents = Math.round((row.valor_formateado || 0) * 100)
      const reference = `ORAL-${row.DocNum}-${Date.now()}`

      return {
        cardCode: row.CardCode,
        cardName: row.CardName,
        cardFName: row.CardFName,
        docNum: row.DocNum,
        docDueDate: row.DocDueDate,
        formattedDueDate: formatDate(row.DocDueDate),
        amount: row.valor_formateado || 0,
        formattedAmount: formattedAmount,
        daysUntilDue: daysUntilDue,
        status: status,
        statusIcon: getStatusIcon(status),
        statusText: status,
        priority: getPriority(status),
        pdfUrl: row.U_HBT_VisorPublico,
        isOverdue: daysUntilDue < 0,
        isUrgent: daysUntilDue >= 0 && daysUntilDue <= 3,
        isUpcoming: daysUntilDue > 3 && daysUntilDue <= 7,
        dueInfo:
          daysUntilDue < 0
            ? `Vencida hace ${Math.abs(daysUntilDue)} días`
            : daysUntilDue === 0
              ? "Vence hoy"
              : `Vence en ${daysUntilDue} días`,
        description: `Pago factura ${row.DocNum} - ${row.CardName}`,
        wompiData: {
          reference: reference,
          amountInCents: amountInCents,
          currency: "COP",
          customerName: row.CardFName || row.CardName,
        },
      }
    })

    const overdue = invoices.filter((i) => i.isOverdue).length
    const urgent = invoices.filter((i) => i.isUrgent && !i.isOverdue).length
    const upcoming = invoices.filter((i) => i.isUpcoming).length
    const normal = invoices.length - overdue - urgent - upcoming
    const totalAmount = invoices.reduce((sum, invoice) => sum + invoice.amount, 0)
    const overdueAmount = invoices.filter((i) => i.isOverdue).reduce((sum, invoice) => sum + invoice.amount, 0)

    console.log(`Estadísticas para ${cardCode}:`)
    console.log(`   - Total: ${invoices.length}`)
    console.log(`   - Vencidas: ${overdue}`)
    console.log(`   - Urgentes: ${urgent}`)
    console.log(`   - Próximas: ${upcoming}`)
    console.log(`   - Vigentes: ${normal}`)
    console.log(`   - Monto total: $${totalAmount.toLocaleString()}`)

    invoices.sort((a, b) => a.priority - b.priority)

    res.json({
      success: true,
      message: `${invoices.length} facturas encontradas para ${cardCode}`,
      cardCode: cardCode,
      count: invoices.length,
      invoices: invoices,
      statistics: {
        total: invoices.length,
        overdue: overdue,
        urgent: urgent,
        upcoming: upcoming,
        normal: normal,
        totalAmount: totalAmount,
        overdueAmount: overdueAmount,
      },
      overdueCount: overdue,
      urgentCount: urgent,
      upcomingCount: upcoming,
      normalCount: normal,
      totalAmount: totalAmount,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("Error en consulta por CardCode:", error.message)
    console.error("Stack trace:", error.stack)

    res.status(500).json({
      success: false,
      error: "Error interno del servidor",
      message: error.message,
      cardCode: req.params.cardcode,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  }
})

app.get("/api/test", async (req, res) => {
  const startTime = Date.now()

  try {
    console.log("Ejecutando test de conexión...")

    const pool = await connectToDatabase()
    const result = await pool.request().query("SELECT 1 as test, GETDATE() as server_time")

    const queryTime = Date.now() - startTime
    const networkIPs = getNetworkIPs()

    console.log("Test de conexión exitoso")

    res.json({
      success: true,
      status: "API ORAL-PLUS funcionando correctamente",
      database: "Conectado a SQL Server",
      server: {
        port: port,
        host: os.hostname(),
        platform: os.platform(),
        nodeVersion: process.version,
        uptime: process.uptime(),
      },
      network: {
        interfaces: networkIPs,
        primaryUrl: networkIPs.length > 0 ? networkIPs[0].url : `http://localhost:${port}/api`,
      },
      database_info: {
        server: dbConfig.server,
        database: dbConfig.database,
        user: dbConfig.user,
        connected: pool.connected,
      },
      test_query: result.recordset[0],
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("Error en test de conexión:", error.message)

    res.status(500).json({
      success: false,
      status: "Error en la API",
      error: error.message,
      server: {
        port: port,
        host: os.hostname(),
        platform: os.platform(),
        nodeVersion: process.version,
      },
      database_config: {
        server: dbConfig.server,
        database: dbConfig.database,
        user: dbConfig.user,
      },
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  }
})

app.get("/api/diagnostic", async (req, res) => {
  const diagnostic = {
    timestamp: new Date().toISOString(),
    server: {
      status: "running",
      port: port,
      host: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
      nodeVersion: process.version,
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      cpus: os.cpus().length,
    },
    network: {
      interfaces: getNetworkIPs(),
    },
    database: {
      config: {
        server: dbConfig.server,
        database: dbConfig.database,
        user: dbConfig.user,
        port: dbConfig.port,
      },
      status: "unknown",
      connected: false,
      error: null,
    },
    tests: {},
  }

  try {
    const pool = await connectToDatabase()
    diagnostic.database.status = "connected"
    diagnostic.database.connected = pool.connected

    const testResult = await pool.request().query("SELECT COUNT(*) as total FROM CONSULTA_CARTERA")
    diagnostic.tests.table_access = {
      success: true,
      total_records: testResult.recordset[0].total,
    }
  } catch (error) {
    diagnostic.database.status = "error"
    diagnostic.database.error = error.message
    diagnostic.tests.table_access = {
      success: false,
      error: error.message,
    }
  }

  diagnostic.tests.endpoints = {
    test: "/api/test",
    invoices_by_cardcode: "/api/invoices/by-cardcode/{cardcode}",
    all_invoices: "/api/invoices/all",
    diagnostic: "/api/diagnostic",
  }

  res.json(diagnostic)
})

app.get("/api/invoices/all", async (req, res) => {
  const startTime = Date.now()

  try {
    console.log("Obteniendo todas las facturas...")

    const pool = await connectToDatabase()
    const result = await pool.request().query("SELECT TOP 100 * FROM CONSULTA_CARTERA ORDER BY DocDueDate DESC")

    const invoices = result.recordset.map((row) => {
      const daysUntilDue = calculateDaysUntilDue(row.DocDueDate)
      const status = getInvoiceStatus(daysUntilDue)

      return {
        cardCode: row.CardCode,
        cardName: row.CardName,
        cardFName: row.CardFName,
        docNum: row.DocNum,
        docDueDate: row.DocDueDate,
        formattedDueDate: formatDate(row.DocDueDate),
        amount: row.valor_formateado || 0,
        formattedAmount: formatCurrency(row.valor_formateado || 0),
        daysUntilDue: daysUntilDue,
        status: status,
        pdfUrl: row.U_HBT_VisorPublico,
      }
    })

    const queryTime = Date.now() - startTime
    console.log(`${invoices.length} facturas obtenidas (${queryTime}ms)`)

    res.json({
      success: true,
      message: `${invoices.length} facturas obtenidas`,
      count: invoices.length,
      invoices: invoices,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("Error obteniendo todas las facturas:", error.message)

    res.status(500).json({
      success: false,
      error: "Error interno del servidor",
      message: error.message,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  }
})

app.get("/api/invoices/search", async (req, res) => {
  try {
    const { cardCode, docNum, cardName, limit = 50 } = req.query

    let whereClause = "WHERE 1=1"
    const inputs = []

    if (cardCode) {
      whereClause += " AND CardCode LIKE @cardCode"
      inputs.push({ name: "cardCode", type: sql.VarChar, value: `%${cardCode}%` })
    }

    if (docNum) {
      whereClause += " AND DocNum LIKE @docNum"
      inputs.push({ name: "docNum", type: sql.VarChar, value: `%${docNum}%` })
    }

    if (cardName) {
      whereClause += " AND (CardName LIKE @cardName OR CardFName LIKE @cardName)"
      inputs.push({ name: "cardName", type: sql.VarChar, value: `%${cardName}%` })
    }

    const pool = await connectToDatabase()
    const request = pool.request()

    inputs.forEach((input) => {
      request.input(input.name, input.type, input.value)
    })

    const query = `SELECT TOP ${Number.parseInt(limit)} * FROM CONSULTA_CARTERA ${whereClause} ORDER BY DocDueDate DESC`
    const result = await request.query(query)

    res.json({
      success: true,
      count: result.recordset.length,
      invoices: result.recordset,
      query: query,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("Error en búsqueda:", error.message)
    res.status(500).json({
      success: false,
      error: error.message,
      timestamp: new Date().toISOString(),
    })
  }
})

app.use("*", (req, res) => {
  res.status(404).json({
    success: false,
    error: "Ruta no encontrada",
    path: req.originalUrl,
    availableEndpoints: [
      "GET /api/test - Prueba de conexión",
      "GET /api/diagnostic - Diagnóstico completo del sistema",
      "GET /api/invoices/by-cardcode/:cardcode - Facturas por CardCode específico",
      "GET /api/invoices/all - Todas las facturas (limitado a 100)",
      "GET /api/invoices/search - Búsqueda avanzada de facturas",
    ],
    timestamp: new Date().toISOString(),
  })
})

function checkDependencies() {
  const requiredModules = ["express", "mssql", "cors"]
  const missing = []

  requiredModules.forEach((module) => {
    try {
      require.resolve(module)
    } catch (e) {
      missing.push(module)
    }
  })

  if (missing.length > 0) {
    console.log("Módulos faltantes:", missing.join(", "))
    console.log("Ejecuta: npm install", missing.join(" "))
    return false
  }

  return true
}

async function startServer() {
  console.log("Iniciando servidor ORAL-PLUS...")
  console.log("=" * 50)

  if (!checkDependencies()) {
    process.exit(1)
  }

  console.log(`Sistema: ${os.platform()} ${os.arch()}`)
  console.log(`Host: ${os.hostname()}`)
  console.log(`Node.js: ${process.version}`)
  console.log(`Directorio: ${process.cwd()}`)

  console.log("\nConfiguración de Base de Datos:")
  console.log(`   Servidor: ${dbConfig.server}:${dbConfig.port}`)
  console.log(`   Base de datos: ${dbConfig.database}`)
  console.log(`   Usuario: ${dbConfig.user}`)

  try {
    await connectToDatabase()
  } catch (error) {
    console.log("\nNo se pudo conectar a la base de datos")
    console.log("El servidor iniciará pero las consultas fallarán")
    console.log("Verifica la configuración en dbConfig")
  }

  const server = app.listen(port, "0.0.0.0", () => {
    console.log("\n¡Servidor iniciado exitosamente!")
    console.log("=" * 50)
    console.log(`Puerto: ${port}`)
    console.log(`URL local: http://localhost:${port}/api`)

    const networkIPs = getNetworkIPs()
    if (networkIPs.length > 0) {
      console.log("\nURLs de red disponibles:")
      networkIPs.forEach(({ interface: iface, ip, url }) => {
        console.log(`   ${iface}: ${url}`)
      })
      console.log("\nUsa cualquiera de estas URLs en tu app Flutter")
    }

    console.log("\nEndpoints disponibles:")
    console.log(`   Test: http://localhost:${port}/api/test`)
    console.log(`   Diagnóstico: http://localhost:${port}/api/diagnostic`)
    console.log(`   Facturas: http://localhost:${port}/api/invoices/by-cardcode/{cardcode}`)

    console.log("\nServidor listo para recibir peticiones")
    console.log("Presiona Ctrl+C para detener")
  })

  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.error(`Error: El puerto ${port} está en uso`)
      console.log("Soluciones:")
      console.log("1. Espera unos segundos y vuelve a intentar")
      console.log("2. Cambia el puerto en la línea 'const port = 3005'")
      console.log("3. Mata el proceso que usa el puerto:")
      console.log(`   Windows: netstat -ano | findstr :${port}`)
      console.log(`   Linux/Mac: lsof -ti:${port} | xargs kill`)
    } else {
      console.error("Error al iniciar el servidor:", err.message)
    }
    process.exit(1)
  })

  return server
}

process.on("SIGINT", async () => {
  console.log("\nCerrando servidor...")

  if (globalPool) {
    try {
      await globalPool.close()
      console.log("Desconectado de la base de datos")
    } catch (error) {
      console.error("Error cerrando conexión:", error.message)
    }
  }

  console.log("¡Hasta luego!")
  process.exit(0)
})

process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled Rejection at:", promise)
  console.error("Reason:", reason)
})

process.on("uncaughtException", (error) => {
  console.error("Uncaught Exception:", error.message)
  console.error("Stack:", error.stack)
  process.exit(1)
})

if (require.main === module) {
  startServer().catch((error) => {
    console.error("Error fatal al iniciar:", error.message)
    process.exit(1)
  })
}

module.exports = { app, startServer, connectToDatabase }
