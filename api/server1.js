const express = require("express")
const sql = require("mssql")
const cors = require("cors")
const os = require("os")

const app = express()
const port = 3006

// Middleware
app.use(cors())
app.use(express.json())

// 🔧 CONFIGURACIÓN DE LA BASE DE DATOS - USANDO TUS CREDENCIALES EXACTAS
const dbConfig = {
  user: "sa",
  password: "Sky2022*!",
  server: "192.168.2.244",
  database: "RBOSKY3",
  port: 1433,
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

// Variable global para el pool de conexiones
let globalPool = null

// 🔗 Función para conectar a la base de datos
async function connectToDatabase() {
  if (globalPool && globalPool.connected) {
    return globalPool
  }

  try {
    console.log("🔄 Conectando a SAP Business One...")
    console.log(`📍 Servidor: ${dbConfig.server}:${dbConfig.port}`)
    console.log(`🗄️ Base de datos: ${dbConfig.database}`)
    console.log(`👤 Usuario: ${dbConfig.user}`)

    globalPool = new sql.ConnectionPool(dbConfig)
    await globalPool.connect()

    console.log("✅ Conectado a SAP Business One exitosamente")
    return globalPool
  } catch (err) {
    console.error("❌ Error conectando a SAP Business One:", err.message)
    throw err
  }
}

// 🌐 Función para obtener IPs de la máquina
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

// 👤 ENDPOINT PRINCIPAL: Obtener datos del cliente por CardCode (TU CÓDIGO MEJORADO)
app.get("/api/client/data/:cardCode", async (req, res) => {
  const startTime = Date.now()
  const cardCode = req.params.cardCode

  console.log(`👤 [${new Date().toISOString()}] Consulta de cliente SAP - CardCode: ${cardCode}`)

  // Validar que se proporcionó el CardCode
  if (!cardCode || cardCode.trim() === "") {
    console.log("❌ CardCode vacío o no proporcionado")
    return res.status(400).json({
      success: false,
      error: "CardCode no puede estar vacío",
    })
  }

  try {
    // Usar el pool global de conexión
    const pool = await connectToDatabase()

    // Query SQL: Socio de Negocio por CardCode - TODOS los clientes (sin filtrar por grupo/canal TAT)
    const query = `
            SELECT 
                T0.[CardName],
                T0.[Address],
                T0.[Phone1],
                T0.E_Mail,
                T0.[CardCode]
            FROM OCRD T0
            WHERE T0.CardCode = @cardCode
        `

    console.log("🔍 Ejecutando consulta SQL en SAP...")
    console.log("📋 CardCode:", cardCode)
    console.log("📝 Query:", query.replace("@cardCode", cardCode))

    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(query)

    const queryTime = Date.now() - startTime
    console.log(`⏱️ Consulta SAP ejecutada en ${queryTime}ms`)
    console.log(`📊 Registros encontrados: ${result.recordset.length}`)

    if (result.recordset.length === 0) {
      console.log("📭 No se encontraron datos en SAP para el CardCode proporcionado")
      console.log("💡 Posible causa: CardCode no existe en Socios de Negocio (OCRD)")

      // EXACTO como tu PHP: retornar array cuando no encuentra
      res.setHeader("Content-Type", "application/json")
      return res.json(["No se encontraron datos para la cédula proporcionada"])
    }

    const clientData = result.recordset[0]

    console.log("✅ Datos del cliente encontrados en SAP:")
    console.log(`   👤 Nombre: ${clientData.CardName}`)
    console.log(`   📍 Dirección: ${clientData.Address || "N/A"}`)
    console.log(`   📞 Teléfono: ${clientData.Phone1 || "N/A"}`)
    console.log(`   📧 Email: ${clientData.E_Mail || "N/A"}`)

    // EXACTO como tu PHP: retornar objeto cuando encuentra
    res.setHeader("Content-Type", "application/json")
    res.json({
      CardName: clientData.CardName || "",
      Address: clientData.Address || "",
      Phone1: clientData.Phone1 || "",
      E_Mail: clientData.E_Mail || "",
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("❌ Error en consulta de cliente SAP:", error.message)
    console.error("🔧 Detalles del error:", error)

    res.status(500).json({
      success: false,
      error: "Error interno del servidor al consultar datos del cliente en SAP",
      details: error.message,
      cardCode: cardCode,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  }
})

// 🔍 ENDPOINT DEBUG: Verificar por qué un CardCode no pasa los filtros
app.get("/api/client/debug/:cardCode", async (req, res) => {
  const startTime = Date.now()
  const cardCode = req.params.cardCode

  console.log(`🔍 [${new Date().toISOString()}] DEBUG SAP - CardCode: ${cardCode}`)

  try {
    const pool = await connectToDatabase()

    // 1. Verificar si el cliente existe sin filtros
    console.log("🔍 Paso 1: Verificando si el cliente existe en SAP...")
    const basicQuery = `
            SELECT 
                CardCode, 
                CardName, 
                GroupCode, 
                U_CANAL_DISTRIBUCION 
            FROM OCRD 
            WHERE CardCode = @cardCode
        `

    const basicResult = await pool.request().input("cardCode", sql.VarChar, cardCode).query(basicQuery)

    if (basicResult.recordset.length === 0) {
      console.log("❌ Cliente no existe en SAP")
      return res.json({
        exists: false,
        message: "Cliente no existe en tabla OCRD de SAP",
        cardCode: cardCode,
      })
    }

    const client = basicResult.recordset[0]
    console.log(`✅ Cliente encontrado en SAP: ${client.CardName}`)
    console.log(`📋 GroupCode: ${client.GroupCode}`)
    console.log(`📋 Canal: ${client.U_CANAL_DISTRIBUCION}`)

    // 2. Verificar información del grupo
    console.log("🔍 Paso 2: Verificando grupo del cliente...")
    const groupQuery = `
            SELECT GroupCode, GroupName 
            FROM OCRG 
            WHERE GroupCode = @groupCode
        `

    const groupResult = await pool.request().input("groupCode", sql.Int, client.GroupCode).query(groupQuery)

    // 3. Verificar información del canal
    console.log("🔍 Paso 3: Verificando canal de distribución...")
    const canalQuery = `
            SELECT Code, Name 
            FROM [@DISTRIBUCION] 
            WHERE Code = @canal
        `

    const canalResult = await pool
      .request()
      .input("canal", sql.VarChar, client.U_CANAL_DISTRIBUCION || "")
      .query(canalQuery)

    const group = groupResult.recordset[0] || null
    const canal = canalResult.recordset[0] || null

    // 4. Evaluar filtros
    const passesGroupFilter =
      group && group.GroupName !== "Droguerias Cadenas" && group.GroupName !== "Canal Grandes Superf"

    const passesCanalFilter =
      canal && canal.Name !== "HARD DISCOUNT NACIONALES" && canal.Name !== "HARD DISCOUNT INDEPENDIENTES"

    console.log("📊 Resultados del análisis:")
    console.log(`   👤 Cliente: ${client.CardName}`)
    console.log(`   📊 Grupo: ${group?.GroupName || "No encontrado"}`)
    console.log(`   🏪 Canal: ${canal?.Name || "No encontrado"}`)
    console.log(`   ✅ Pasa filtro grupo: ${passesGroupFilter}`)
    console.log(`   ✅ Pasa filtro canal: ${passesCanalFilter}`)
    console.log(`   🎯 Pasa todos los filtros: ${passesGroupFilter && passesCanalFilter}`)

    const queryTime = Date.now() - startTime

    res.json({
      exists: true,
      client: client,
      group: group,
      canal: canal,
      filters: {
        groupName: group?.GroupName,
        canalName: canal?.Name,
        passesGroupFilter: passesGroupFilter,
        passesCanalFilter: passesCanalFilter,
        passesAllFilters: passesGroupFilter && passesCanalFilter,
      },
      reasons: {
        groupExcluded:
          group && (group.GroupName === "Droguerias Cadenas" || group.GroupName === "Canal Grandes Superf"),
        canalExcluded:
          canal && (canal.Name === "HARD DISCOUNT NACIONALES" || canal.Name === "HARD DISCOUNT INDEPENDIENTES"),
      },
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("❌ Error en debug SAP:", error.message)
    res.status(500).json({
      error: error.message,
      cardCode: cardCode,
      timestamp: new Date().toISOString(),
    })
  }
})

// 🧪 ENDPOINT DE PRUEBA ESPECÍFICO para C39536225
app.get("/api/test/client/C39536225", async (req, res) => {
  console.log("🧪 Test específico para CardCode C39536225 en SAP")

  try {
    const cardCode = "C39536225"

    // Llamar al endpoint principal
    console.log("📞 Llamando al endpoint principal...")
    const clientResponse = await fetch(`http://localhost:${port}/api/client/data/${cardCode}`)
    const clientData = await clientResponse.json()

    // Llamar al endpoint de debug
    console.log("🔍 Llamando al endpoint de debug...")
    const debugResponse = await fetch(`http://localhost:${port}/api/client/debug/${cardCode}`)
    const debugData = await debugResponse.json()

    console.log("📋 Resultado del test completo:")
    console.log("   📄 Datos cliente:", JSON.stringify(clientData, null, 2))
    console.log("   🔍 Debug info:", JSON.stringify(debugData, null, 2))

    res.json({
      testCardCode: cardCode,
      clientData: clientData,
      debugInfo: debugData,
      testTime: new Date().toISOString(),
      summary: {
        clientExists: debugData.exists,
        clientName: debugData.client?.CardName,
        passesFilters: debugData.filters?.passesAllFilters,
        groupName: debugData.group?.GroupName,
        canalName: debugData.canal?.Name,
      },
    })
  } catch (error) {
    console.error("❌ Error en test específico:", error)
    res.status(500).json({
      error: "Error en test específico",
      details: error.message,
      testCardCode: "C39536225",
      timestamp: new Date().toISOString(),
    })
  }
})

// 🧪 Endpoint de prueba de conexión
app.get("/api/test", async (req, res) => {
  const startTime = Date.now()
  try {
    console.log("🧪 Ejecutando test de conexión a SAP...")
    const pool = await connectToDatabase()
    const result = await pool.request().query("SELECT 1 as test, GETDATE() as server_time")

    const queryTime = Date.now() - startTime
    const networkIPs = getNetworkIPs()

    console.log("✅ Test de conexión SAP exitoso")

    res.json({
      success: true,
      status: "API SAP Business One funcionando correctamente",
      database: "Conectado a SAP Business One",
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
    console.error("❌ Error en test de conexión SAP:", error.message)
    res.status(500).json({
      success: false,
      status: "Error en la API SAP",
      error: error.message,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  }
})

// 🚫 Manejo de rutas no encontradas
app.use("*", (req, res) => {
  res.status(404).json({
    success: false,
    error: "Ruta no encontrada",
    path: req.originalUrl,
    availableEndpoints: [
      "GET /api/test - Prueba de conexión SAP",
      "GET /api/client/data/:cardcode - Datos del cliente SAP (PHP replica exacta)",
      "GET /api/client/debug/:cardcode - Debug del cliente SAP (análisis de filtros)",
      "GET /api/test/client/C39536225 - Test específico para C39536225",
    ],
    timestamp: new Date().toISOString(),
  })
})

// 🚀 Función para iniciar el servidor
async function startServer() {
  console.log("🚀 Iniciando servidor SAP Business One...")
  console.log("=".repeat(60))

  // Mostrar información del sistema
  console.log(`🖥️ Sistema: ${os.platform()} ${os.arch()}`)
  console.log(`📍 Host: ${os.hostname()}`)
  console.log(`🔧 Node.js: ${process.version}`)

  // Mostrar configuración de base de datos
  console.log("\n🗄️ Configuración SAP Business One:")
  console.log(`   Servidor: ${dbConfig.server}:${dbConfig.port}`)
  console.log(`   Base de datos: ${dbConfig.database}`)
  console.log(`   Usuario: ${dbConfig.user}`)

  // Intentar conectar a SAP
  try {
    await connectToDatabase()
  } catch (error) {
    console.log("\n❌ No se pudo conectar a SAP Business One")
    console.log("⚠️ El servidor iniciará pero las consultas fallarán")
  }

  // Iniciar servidor HTTP
  const server = app.listen(port, "0.0.0.0", () => {
    console.log("\n🎉 ¡Servidor SAP iniciado exitosamente!")
    console.log("=".repeat(60))
    console.log(`🌐 Puerto: ${port}`)
    console.log(`🔗 URL local: http://localhost:${port}/api`)

    // Mostrar todas las IPs disponibles
    const networkIPs = getNetworkIPs()
    if (networkIPs.length > 0) {
      console.log("\n📡 URLs de red disponibles:")
      networkIPs.forEach(({ interface: iface, ip, url }) => {
        console.log(`   ${iface}: ${url}`)
      })
    }

    console.log("\n🧪 Endpoints SAP disponibles:")
    console.log(`   Test conexión: http://localhost:${port}/api/test`)
    console.log(`   Cliente SAP: http://localhost:${port}/api/client/data/{cardcode}`)
    console.log(`   Debug SAP: http://localhost:${port}/api/client/debug/{cardcode}`)
    console.log(`   Test C39536225: http://localhost:${port}/api/test/client/C39536225`)

    console.log("\n💡 Para probar:")
    console.log(`   curl http://localhost:${port}/api/client/data/C39536225`)
    console.log(`   curl http://localhost:${port}/api/client/debug/C39536225`)
    console.log(`   curl http://localhost:${port}/api/test/client/C39536225`)

    console.log("\n✅ Servidor SAP listo - Conectado a Business One")
    console.log("🛑 Presiona Ctrl+C para detener")
  })

  return server
}

// 🛑 Manejo de cierre graceful
process.on("SIGINT", async () => {
  console.log("\n🛑 Cerrando servidor SAP...")
  if (globalPool) {
    try {
      await globalPool.close()
      console.log("🔌 Desconectado de SAP Business One")
    } catch (error) {
      console.error("❌ Error cerrando conexión SAP:", error.message)
    }
  }
  console.log("👋 ¡Hasta luego!")
  process.exit(0)
})

// 🚀 Iniciar el servidor
if (require.main === module) {
  startServer().catch((error) => {
    console.error("❌ Error fatal al iniciar servidor SAP:", error.message)
    process.exit(1)
  })
}

module.exports = { app, startServer, connectToDatabase }
