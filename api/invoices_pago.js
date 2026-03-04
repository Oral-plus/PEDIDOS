const express = require("express")
const sql = require("mssql")
const cors = require("cors")
const os = require("os")
const { exec } = require("child_process")

const app = express()
const port = 3006

// Middleware
app.use(cors())
app.use(express.json())

// 🔧 CONFIGURACIÓN DE LA BASE DE DATOS - ACTUALIZADA
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

// 🔗 Función para conectar a la base de datos con reintentos
async function connectToDatabase() {
  if (globalPool && globalPool.connected) {
    return globalPool
  }

  try {
    console.log("🔄 Conectando a la base de datos...")
    console.log(`📍 Servidor: ${dbConfig.server}:${dbConfig.port}`)
    console.log(`🗄️ Base de datos: ${dbConfig.database}`)
    console.log(`👤 Usuario: ${dbConfig.user}`)

    globalPool = new sql.ConnectionPool(dbConfig)
    await globalPool.connect()

    console.log("✅ Conectado a SQL Server exitosamente")

    // Verificar que las tablas principales existen
    const testTables = ["OCRD", "JDT1", "OACT", "OJDT"]
    for (const table of testTables) {
      const testResult = await globalPool.request().query(`
        SELECT COUNT(*) as total 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_NAME = '${table}'
      `)

      if (testResult.recordset[0].total === 0) {
        console.log(`⚠️ ADVERTENCIA: Tabla ${table} no encontrada`)
      } else {
        console.log(`✅ Tabla ${table} encontrada`)
      }
    }

    return globalPool
  } catch (err) {
    console.error("❌ Error conectando a la base de datos:", err.message)
    console.log("💡 Verifica:")
    console.log("   - Que SQL Server esté ejecutándose")
    console.log("   - Las credenciales sean correctas")
    console.log("   - El servidor sea accesible desde esta máquina")
    console.log("   - El puerto 1433 esté abierto")
    throw err
  }
}

// 📅 Función para formatear fecha
function formatDate(date) {
  if (!date) return ""
  const d = new Date(date)
  return d.toLocaleDateString("es-CO")
}

// 💰 Función para formatear moneda
function formatCurrency(amount) {
  if (!amount) return "$0"
  return new Intl.NumberFormat("es-CO", {
    style: "currency",
    currency: "COP",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount)
}

// 💰 Función para parsear moneda formateada de SQL Server
function parseCurrencyFromSQL(formattedCurrency) {
  if (!formattedCurrency) return 0
  // Remover símbolos de moneda y convertir a número
  const cleanValue = formattedCurrency
    .toString()
    .replace(/[$,\s]/g, "")
    .replace(/\./g, "")
  return Number.parseFloat(cleanValue) || 0
}

// ⏰ Función para calcular días hasta vencimiento
function calculateDaysUntilDue(dueDate) {
  if (!dueDate) return 0
  const today = new Date()
  const due = new Date(dueDate)
  const diffTime = due - today
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
  return diffDays
}

// 📊 Función para determinar el estado de la factura
function getInvoiceStatus(daysUntilDue, origen) {
  // Si es PR (Pago Recibido), está pagada
  if (origen === "PR") return "Pagada"

  if (daysUntilDue < 0) return "Vencida"
  if (daysUntilDue <= 3) return "Urgente"
  if (daysUntilDue <= 7) return "Próxima"
  return "Vigente"
}

// 🎯 Función para obtener el icono del estado
function getStatusIcon(status) {
  switch (status) {
    case "Pagada":
      return "check_circle"
    case "Vencida":
      return "warning"
    case "Urgente":
      return "schedule"
    case "Próxima":
      return "schedule"
    default:
      return "receipt"
  }
}

// 🔢 Función para obtener la prioridad (para ordenamiento)
function getPriority(status) {
  switch (status) {
    case "Pagada":
      return 0 // Las pagadas van primero en historial
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

// 📝 Query principal para obtener cartera de un cliente
const CARTERA_QUERY = `
SELECT 
    T0.CardCode, 
    T0.CardName, 
    T4.BaseRef AS 'Doc_Interno', 
    T1.BaseRef,
    CASE 
        WHEN T1.[TransType] = 13 THEN 'FR'
        WHEN T1.[TransType] = 24 THEN 'PR'
        WHEN T1.[TransType] = 321 THEN 'ID'
        WHEN T1.[TransType] = 14 THEN 'RC'
        ELSE CAST(T1.[TransType] AS VARCHAR)
    END AS Origen,
    T1.Ref2, 
    T1.RefDate, 
    T1.DueDate,

    -- Importe total bruto
    CASE 
        WHEN Y1.DocTotal IS NULL THEN (T1.Debit - T1.Credit)
        ELSE Y1.DocTotal
    END AS 'importe_total_raw',

    -- Importe total formateado
    FORMAT(
        CASE 
            WHEN Y1.DocTotal IS NULL THEN (T1.Debit - T1.Credit)
            ELSE Y1.DocTotal
        END, 'C', 'es-CO') AS 'importe_total',

    -- Saldo = igual a importe total
    CASE 
        WHEN Y1.DocTotal IS NULL THEN (T1.Debit - T1.Credit)
        ELSE Y1.DocTotal
    END AS 'saldo_raw',

    FORMAT(
        CASE 
            WHEN Y1.DocTotal IS NULL THEN (T1.Debit - T1.Credit)
            ELSE Y1.DocTotal
        END, 'C', 'es-CO') AS 'Saldo',

    -- Campos adicionales
    Y1.DocEntry AS 'DocEntry',
    Y1.NumAtCard AS 'NumeroCliente',

    -- Para control
    T1.TransId, 
    T1.[TransType]

FROM dbo.OCRD T0
INNER JOIN dbo.JDT1 T1 ON T1.ShortName = T0.CardCode
INNER JOIN dbo.OACT T2 ON T2.AcctCode = T1.Account
INNER JOIN dbo.OJDT T4 ON T4.TransId = T1.TransId
LEFT JOIN dbo.OINV Y1 ON Y1.TransId = T1.TransId
LEFT JOIN dbo.ORIN Y2 ON Y2.TransId = T1.TransId
LEFT JOIN dbo.OSLP Y3 ON Y3.SlpCode = Y1.SlpCode OR Y3.SlpCode = Y2.SlpCode
LEFT JOIN (
    SELECT 
        X0.ShortName AS 'SN', 
        X0.TransId AS 'TransId', 
        SUM(X0.ReconSum) AS 'ReconSum', 
        X0.IsCredit AS 'DebHab', 
        X0.TransRowId AS 'Linea'
    FROM dbo.ITR1 X0
    INNER JOIN dbo.OITR X1 ON X1.ReconNum = X0.ReconNum
    GROUP BY X0.ShortName, X0.TransId, X0.IsCredit, X0.TransRowId
) T3 ON T3.TransId = T1.TransId AND T3.SN = T1.ShortName AND T3.Linea = T1.Line_ID

WHERE 
    T0.CardType = 'C' 
    AND T0.CardCode = @cardCode

GROUP BY 
    Y3.SlpName, 
    T0.CardCode, 
    T0.CardName, 
    T1.TransId, 
    T4.BaseRef, 
    T4.Folionum, 
    T1.RefDate, 
    T1.TaxDate, 
    T1.DueDate, 
    Y1.DocTotal, 
    Y1.DocEntry,
    Y1.NumAtCard,
    T1.Debit, 
    T1.Credit, 
    T3.ReconSum, 
    Y3.SlpCode,
    T1.Ref2,
    T1.BaseRef,
    T1.[TransType]

ORDER BY T1.DueDate DESC
`;


// 🚀 ENDPOINT PRINCIPAL: Obtener facturas por CardCode (TODAS)
app.get("/api/invoices/by-cardcode/:cardcode", async (req, res) => {
  const startTime = Date.now()

  try {
    const cardCode = req.params.cardcode.trim()

    console.log(`🔍 [${new Date().toISOString()}] Consultando TODAS las facturas para CardCode: ${cardCode}`)

    if (!cardCode) {
      return res.status(400).json({
        success: false,
        error: "CardCode es requerido",
        message: "Debe proporcionar un CardCode válido",
        timestamp: new Date().toISOString(),
      })
    }

    const pool = await connectToDatabase()

    // Ejecutar query principal
    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(CARTERA_QUERY)

    const queryTime = Date.now() - startTime
    console.log(`📄 Registros encontrados: ${result.recordset.length} (${queryTime}ms)`)

    // Si no hay resultados
    if (result.recordset.length === 0) {
      console.log(`🎉 Usuario a paz y salvo: ${cardCode}`)
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

    // Procesar las facturas encontradas
    const invoices = result.recordset.map((row) => {
      const daysUntilDue = calculateDaysUntilDue(row.DueDate)
      const status = getInvoiceStatus(daysUntilDue, row.Origen)
      const amount = row.importe_total_raw || 0
      const saldo = row.saldo_raw || 0

      // Generar datos para Wompi
      const amountInCents = Math.round(Math.abs(saldo) * 100)
      const reference = `ORAL-${row.BaseRef || row.TransId}-${Date.now()}`

      return {
        cardCode: row.CardCode,
        cardName: row.CardName,
        cardFName: row.CardName, // Usar CardName como fallback
        docNum: row.BaseRef || row.Doc_Interno || row.TransId.toString(),
        docDueDate: row.DueDate,
        formattedDueDate: formatDate(row.DueDate),
        refDate: row.RefDate,
        formattedRefDate: formatDate(row.RefDate),
        amount: Math.abs(saldo), // Usar saldo para el monto a pagar
        formattedAmount: formatCurrency(Math.abs(saldo)),
        originalAmount: amount,
        formattedOriginalAmount: row.importe_total,
        saldo: saldo,
        formattedSaldo: row.Saldo,
        daysUntilDue: daysUntilDue,
        status: status,
        statusIcon: getStatusIcon(status),
        statusText: status,
        priority: getPriority(status),
        origen: row.Origen,
        transType: row.TransType,
        transId: row.TransId,
        ref2: row.Ref2,
        isPaid: row.Origen === "PR",
        isOverdue: daysUntilDue < 0 && row.Origen !== "PR",
        isUrgent: daysUntilDue >= 0 && daysUntilDue <= 3 && row.Origen !== "PR",
        isUpcoming: daysUntilDue > 3 && daysUntilDue <= 7 && row.Origen !== "PR",
        dueInfo:
          row.Origen === "PR"
            ? `Pagada el ${formatDate(row.RefDate)}`
            : daysUntilDue < 0
              ? `Vencida hace ${Math.abs(daysUntilDue)} días`
              : daysUntilDue === 0
                ? "Vence hoy"
                : `Vence en ${daysUntilDue} días`,
        description: `${row.Origen === "PR" ? "Pago recibido" : "Factura"} ${row.BaseRef || row.TransId} - ${row.CardName}`,
        wompiData: {
          reference: reference,
          amountInCents: amountInCents,
          currency: "COP",
          customerName: row.CardName,
        },
      }
    })

    // Calcular estadísticas
    const paid = invoices.filter((i) => i.isPaid).length
    const overdue = invoices.filter((i) => i.isOverdue).length
    const urgent = invoices.filter((i) => i.isUrgent).length
    const upcoming = invoices.filter((i) => i.isUpcoming).length
    const normal = invoices.length - paid - overdue - urgent - upcoming
    const totalAmount = invoices.reduce((sum, invoice) => sum + (invoice.isPaid ? 0 : invoice.amount), 0)
    const overdueAmount = invoices.filter((i) => i.isOverdue).reduce((sum, invoice) => sum + invoice.amount, 0)
    const paidAmount = invoices.filter((i) => i.isPaid).reduce((sum, invoice) => sum + invoice.amount, 0)

    console.log(`📊 Estadísticas para ${cardCode}:`)
    console.log(`   - Total: ${invoices.length}`)
    console.log(`   - Pagadas: ${paid}`)
    console.log(`   - Vencidas: ${overdue}`)
    console.log(`   - Urgentes: ${urgent}`)
    console.log(`   - Próximas: ${upcoming}`)
    console.log(`   - Vigentes: ${normal}`)
    console.log(`   - Monto pendiente: $${totalAmount.toLocaleString()}`)
    console.log(`   - Monto pagado: $${paidAmount.toLocaleString()}`)

    // Ordenar por prioridad
    invoices.sort((a, b) => a.priority - b.priority)

    res.json({
      success: true,
      message: `${invoices.length} registros encontrados para ${cardCode}`,
      cardCode: cardCode,
      count: invoices.length,
      invoices: invoices,
      statistics: {
        total: invoices.length,
        paid: paid,
        overdue: overdue,
        urgent: urgent,
        upcoming: upcoming,
        normal: normal,
        totalAmount: totalAmount,
        overdueAmount: overdueAmount,
        paidAmount: paidAmount,
      },
      paidCount: paid,
      overdueCount: overdue,
      urgentCount: urgent,
      upcomingCount: upcoming,
      normalCount: normal,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("❌ Error en consulta por CardCode:", error.message)
    console.error("📍 Stack trace:", error.stack)

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

// 💰 NUEVO ENDPOINT: Obtener SOLO facturas PAGADAS (PR) por CardCode
app.get("/api/invoices/paid/:cardcode", async (req, res) => {
  const startTime = Date.now()

  try {
    const cardCode = req.params.cardcode.trim()

    console.log(`💰 [${new Date().toISOString()}] Consultando facturas PAGADAS (PR) para CardCode: ${cardCode}`)

    if (!cardCode) {
      return res.status(400).json({
        success: false,
        error: "CardCode es requerido",
        message: "Debe proporcionar un CardCode válido",
        timestamp: new Date().toISOString(),
      })
    }

    const pool = await connectToDatabase()

    // Query modificado para obtener SOLO las facturas pagadas (PR)
    const paidQuery = CARTERA_QUERY.replace(
      "WHERE T0.CardType = 'C' AND T0.CardCode = @cardCode",
      "WHERE T0.CardType = 'C' AND T0.CardCode = @cardCode AND T1.[TransType] = 24",
    )

    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(paidQuery)

    const queryTime = Date.now() - startTime
    console.log(`💰 Facturas pagadas encontradas: ${result.recordset.length} (${queryTime}ms)`)

    // Si no hay facturas pagadas
    if (result.recordset.length === 0) {
      console.log(`📭 No hay facturas pagadas para: ${cardCode}`)
      return res.json({
        success: true,
        message: "No tienes facturas pagadas registradas",
        cardCode: cardCode,
        count: 0,
        paidInvoices: [],
        queryTime: queryTime,
        timestamp: new Date().toISOString(),
      })
    }

    // Procesar las facturas pagadas
    const paidInvoices = result.recordset.map((row) => {
      const amount = Math.abs(row.importe_total_raw || 0)

      return {
        cardCode: row.CardCode,
        cardName: row.CardName,
        cardFName: row.CardName,
        docNum: row.BaseRef || row.Doc_Interno || row.TransId.toString(),
        docDueDate: row.DueDate, // Fecha original de vencimiento
        formattedDueDate: formatDate(row.DueDate),
        paymentDate: row.RefDate, // Fecha real de pago
        formattedPaymentDate: formatDate(row.RefDate),
        amount: amount,
        formattedAmount: formatCurrency(amount),
        saldo: row.saldo_raw || 0,
        formattedSaldo: row.Saldo,
        status: "Pagada",
        statusIcon: "check_circle",
        statusText: "PAGADA",
        priority: 0,
        origen: row.Origen,
        transType: row.TransType,
        transId: row.TransId,
        ref2: row.Ref2,
        isPaid: true,
        paymentInfo: `Pagada el ${formatDate(row.RefDate)}`,
        description: `Pago recibido ${row.BaseRef || row.TransId} - ${row.CardName}`,
        wompiData: {
          reference: `PAID-${row.BaseRef || row.TransId}-${Date.now()}`,
          amountInCents: Math.round(amount * 100),
          currency: "COP",
          customerName: row.CardName,
        },
      }
    })

    // Calcular estadísticas de pagos
    const totalPaidAmount = paidInvoices.reduce((sum, invoice) => sum + invoice.amount, 0)
    const currentMonth = new Date().getMonth()
    const currentYear = new Date().getFullYear()

    const thisMonthPaid = paidInvoices.filter((invoice) => {
      const paymentDate = new Date(invoice.paymentDate)
      return paymentDate.getMonth() === currentMonth && paymentDate.getFullYear() === currentYear
    })

    const thisMonthAmount = thisMonthPaid.reduce((sum, invoice) => sum + invoice.amount, 0)

    console.log(`💰 Estadísticas de pagos para ${cardCode}:`)
    console.log(`   - Total facturas pagadas: ${paidInvoices.length}`)
    console.log(`   - Monto total pagado: $${totalPaidAmount.toLocaleString()}`)
    console.log(`   - Pagos este mes: ${thisMonthPaid.length}`)
    console.log(`   - Monto este mes: $${thisMonthAmount.toLocaleString()}`)

    // Ordenar por fecha de pago más reciente primero
    paidInvoices.sort((a, b) => new Date(b.paymentDate) - new Date(a.paymentDate))

    res.json({
      success: true,
      message: `${paidInvoices.length} facturas pagadas encontradas para ${cardCode}`,
      cardCode: cardCode,
      count: paidInvoices.length,
      paidInvoices: paidInvoices,
      statistics: {
        totalPaid: paidInvoices.length,
        totalPaidAmount: totalPaidAmount,
        thisMonthPaid: thisMonthPaid.length,
        thisMonthAmount: thisMonthAmount,
        averagePayment: paidInvoices.length > 0 ? totalPaidAmount / paidInvoices.length : 0,
      },
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    const queryTime = Date.now() - startTime
    console.error("❌ Error en consulta de facturas pagadas:", error.message)
    console.error("📍 Stack trace:", error.stack)

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

// 📋 ENDPOINT: Obtener SOLO facturas PENDIENTES (sin PR) por CardCode
app.get("/api/invoices/pending/:cardcode", async (req, res) => {
  const startTime = Date.now()

  try {
    const cardCode = req.params.cardcode.trim()

    console.log(`📋 [${new Date().toISOString()}] Consultando facturas PENDIENTES para CardCode: ${cardCode}`)

    if (!cardCode) {
      return res.status(400).json({
        success: false,
        error: "CardCode es requerido",
        message: "Debe proporcionar un CardCode válido",
        timestamp: new Date().toISOString(),
      })
    }

    const pool = await connectToDatabase()

    // Query modificado para obtener SOLO las facturas pendientes (NO PR)
    const pendingQuery = CARTERA_QUERY.replace(
      "WHERE T0.CardType = 'C' AND T0.CardCode = @cardCode",
      "WHERE T0.CardType = 'C' AND T0.CardCode = @cardCode AND T1.[TransType] != 24",
    )

    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(pendingQuery)

    const queryTime = Date.now() - startTime
    console.log(`📋 Facturas pendientes encontradas: ${result.recordset.length} (${queryTime}ms)`)

    // Si no hay facturas pendientes
    if (result.recordset.length === 0) {
      console.log(`🎉 Usuario a paz y salvo: ${cardCode}`)
      return res.json({
        success: true,
        message: "¡Felicitaciones! Te encuentras a paz y salvo",
        cardCode: cardCode,
        count: 0,
        pendingInvoices: [],
        queryTime: queryTime,
        timestamp: new Date().toISOString(),
      })
    }

    // Procesar las facturas pendientes (igual que el endpoint principal pero sin PR)
    const pendingInvoices = result.recordset.map((row) => {
      const daysUntilDue = calculateDaysUntilDue(row.DueDate)
      const status = getInvoiceStatus(daysUntilDue, row.Origen)
      const saldo = Math.abs(row.saldo_raw || 0)

      const amountInCents = Math.round(saldo * 100)
      const reference = `ORAL-${row.BaseRef || row.TransId}-${Date.now()}`

      return {
        cardCode: row.CardCode,
        cardName: row.CardName,
        cardFName: row.CardName,
        docNum: row.BaseRef || row.Doc_Interno || row.TransId.toString(),
        docDueDate: row.DueDate,
        formattedDueDate: formatDate(row.DueDate),
        refDate: row.RefDate,
        formattedRefDate: formatDate(row.RefDate),
        amount: saldo,
        formattedAmount: formatCurrency(saldo),
        daysUntilDue: daysUntilDue,
        status: status,
        statusIcon: getStatusIcon(status),
        statusText: status,
        priority: getPriority(status),
        origen: row.Origen,
        transType: row.TransType,
        transId: row.TransId,
        ref2: row.Ref2,
        isPaid: false,
        isOverdue: daysUntilDue < 0,
        isUrgent: daysUntilDue >= 0 && daysUntilDue <= 3,
        isUpcoming: daysUntilDue > 3 && daysUntilDue <= 7,
        dueInfo:
          daysUntilDue < 0
            ? `Vencida hace ${Math.abs(daysUntilDue)} días`
            : daysUntilDue === 0
              ? "Vence hoy"
              : `Vence en ${daysUntilDue} días`,
        description: `Factura ${row.BaseRef || row.TransId} - ${row.CardName}`,
        wompiData: {
          reference: reference,
          amountInCents: amountInCents,
          currency: "COP",
          customerName: row.CardName,
        },
      }
    })

    // Calcular estadísticas de pendientes
    const overdue = pendingInvoices.filter((i) => i.isOverdue).length
    const urgent = pendingInvoices.filter((i) => i.isUrgent).length
    const upcoming = pendingInvoices.filter((i) => i.isUpcoming).length
    const normal = pendingInvoices.length - overdue - urgent - upcoming
    const totalAmount = pendingInvoices.reduce((sum, invoice) => sum + invoice.amount, 0)
    const overdueAmount = pendingInvoices.filter((i) => i.isOverdue).reduce((sum, invoice) => sum + invoice.amount, 0)

    console.log(`📋 Estadísticas pendientes para ${cardCode}:`)
    console.log(`   - Total pendientes: ${pendingInvoices.length}`)
    console.log(`   - Vencidas: ${overdue}`)
    console.log(`   - Urgentes: ${urgent}`)
    console.log(`   - Próximas: ${upcoming}`)
    console.log(`   - Vigentes: ${normal}`)
    console.log(`   - Monto total: $${totalAmount.toLocaleString()}`)

    // Ordenar por prioridad
    pendingInvoices.sort((a, b) => a.priority - b.priority)

    res.json({
      success: true,
      message: `${pendingInvoices.length} facturas pendientes encontradas para ${cardCode}`,
      cardCode: cardCode,
      count: pendingInvoices.length,
      pendingInvoices: pendingInvoices,
      statistics: {
        total: pendingInvoices.length,
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
    console.error("❌ Error en consulta de facturas pendientes:", error.message)
    console.error("📍 Stack trace:", error.stack)

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

// 🧪 Endpoint de prueba de conexión MEJORADO
app.get("/api/test", async (req, res) => {
  const startTime = Date.now()

  try {
    console.log("🧪 Ejecutando test de conexión...")

    const pool = await connectToDatabase()
    const result = await pool.request().query("SELECT 1 as test, GETDATE() as server_time")

    const queryTime = Date.now() - startTime
    const networkIPs = getNetworkIPs()

    console.log("✅ Test de conexión exitoso")

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
    console.error("❌ Error en test de conexión:", error.message)

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

// 📋 Endpoint para diagnóstico completo del sistema
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

  // Test de base de datos
  try {
    const pool = await connectToDatabase()
    diagnostic.database.status = "connected"
    diagnostic.database.connected = pool.connected

    // Test de consulta básica en las tablas principales
    const testResult = await pool.request().query("SELECT COUNT(*) as total FROM OCRD WHERE CardType = 'C'")
    diagnostic.tests.table_access = {
      success: true,
      total_clients: testResult.recordset[0].total,
    }

    // Test del query principal
    const queryTest = await pool.request().input("cardCode", sql.VarChar, "TEST").query(CARTERA_QUERY)

    diagnostic.tests.main_query = {
      success: true,
      query_executed: true,
    }
  } catch (error) {
    diagnostic.database.status = "error"
    diagnostic.database.error = error.message
    diagnostic.tests.table_access = {
      success: false,
      error: error.message,
    }
  }

  // Test de endpoints
  diagnostic.tests.endpoints = {
    test: "/api/test",
    invoices_all: "/api/invoices/by-cardcode/{cardcode}",
    invoices_paid: "/api/invoices/paid/{cardcode}",
    invoices_pending: "/api/invoices/pending/{cardcode}",
    diagnostic: "/api/diagnostic",
  }

  res.json(diagnostic)
})

// 🔍 Endpoint para buscar facturas por múltiples criterios
app.get("/api/invoices/search", async (req, res) => {
  try {
    const { cardCode, docNum, cardName, origen, limit = 50 } = req.query

    let whereClause = "WHERE T0.CardType = 'C'"
    const inputs = []

    if (cardCode) {
      whereClause += " AND T0.CardCode LIKE @cardCode"
      inputs.push({ name: "cardCode", type: sql.VarChar, value: `%${cardCode}%` })
    }

    if (docNum) {
      whereClause += " AND T4.BaseRef LIKE @docNum"
      inputs.push({ name: "docNum", type: sql.VarChar, value: `%${docNum}%` })
    }

    if (cardName) {
      whereClause += " AND T0.CardName LIKE @cardName"
      inputs.push({ name: "cardName", type: sql.VarChar, value: `%${cardName}%` })
    }

    if (origen) {
      const transType =
        origen === "PR" ? 24 : origen === "FR" ? 13 : origen === "RC" ? 14 : origen === "ID" ? 321 : null
      if (transType) {
        whereClause += " AND T1.[TransType] = @transType"
        inputs.push({ name: "transType", type: sql.Int, value: transType })
      }
    }

    const pool = await connectToDatabase()
    const request = pool.request()

    inputs.forEach((input) => {
      request.input(input.name, input.type, input.value)
    })

    const searchQuery = CARTERA_QUERY.replace(
      "WHERE T0.CardType = 'C' AND T0.CardCode = @cardCode",
      whereClause,
    ).replace(
      "ORDER BY T1.DueDate DESC",
      `ORDER BY T1.DueDate DESC OFFSET 0 ROWS FETCH NEXT ${Number.parseInt(limit)} ROWS ONLY`,
    )

    const result = await request.query(searchQuery)

    res.json({
      success: true,
      count: result.recordset.length,
      invoices: result.recordset,
      searchCriteria: { cardCode, docNum, cardName, origen, limit },
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("❌ Error en búsqueda:", error.message)
    res.status(500).json({
      success: false,
      error: error.message,
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
      "GET /api/test - Prueba de conexión",
      "GET /api/diagnostic - Diagnóstico completo del sistema",
      "GET /api/invoices/by-cardcode/:cardcode - TODAS las facturas por CardCode",
      "GET /api/invoices/paid/:cardcode - SOLO facturas PAGADAS (PR) por CardCode",
      "GET /api/invoices/pending/:cardcode - SOLO facturas PENDIENTES por CardCode",
      "GET /api/invoices/search - Búsqueda avanzada de facturas",
    ],
    timestamp: new Date().toISOString(),
  })
})

// 🔧 Función para verificar dependencias
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
    console.log("❌ Módulos faltantes:", missing.join(", "))
    console.log("💡 Ejecuta: npm install", missing.join(" "))
    return false
  }

  return true
}

// 🚀 Función para iniciar el servidor
async function startServer() {
  console.log("🚀 Iniciando servidor ORAL-PLUS...")
  console.log("=".repeat(50))

  // Verificar dependencias
  if (!checkDependencies()) {
    process.exit(1)
  }

  // Mostrar información del sistema
  console.log(`🖥️ Sistema: ${os.platform()} ${os.arch()}`)
  console.log(`📍 Host: ${os.hostname()}`)
  console.log(`🔧 Node.js: ${process.version}`)
  console.log(`📂 Directorio: ${process.cwd()}`)

  // Mostrar configuración de base de datos
  console.log("\n🗄️ Configuración de Base de Datos:")
  console.log(`   Servidor: ${dbConfig.server}:${dbConfig.port}`)
  console.log(`   Base de datos: ${dbConfig.database}`)
  console.log(`   Usuario: ${dbConfig.user}`)

  // Intentar conectar a la base de datos
  try {
    await connectToDatabase()
  } catch (error) {
    console.log("\n❌ No se pudo conectar a la base de datos")
    console.log("⚠️ El servidor iniciará pero las consultas fallarán")
    console.log("💡 Verifica la configuración en dbConfig")
  }

  // Iniciar servidor HTTP
  const server = app.listen(port, "0.0.0.0", () => {
    console.log("\n🎉 ¡Servidor iniciado exitosamente!")
    console.log("=".repeat(50))
    console.log(`🌐 Puerto: ${port}`)
    console.log(`🔗 URL local: http://localhost:${port}/api`)

    // Mostrar todas las IPs disponibles
    const networkIPs = getNetworkIPs()
    if (networkIPs.length > 0) {
      console.log("\n📡 URLs de red disponibles:")
      networkIPs.forEach(({ interface: iface, ip, url }) => {
        console.log(`   ${iface}: ${url}`)
      })
      console.log("\n💡 Usa cualquiera de estas URLs en tu app Flutter")
    }

    console.log("\n🧪 Endpoints disponibles:")
    console.log(`   Test: http://localhost:${port}/api/test`)
    console.log(`   Diagnóstico: http://localhost:${port}/api/diagnostic`)
    console.log(`   Todas las facturas: http://localhost:${port}/api/invoices/by-cardcode/{cardcode}`)
    console.log(`   Solo pagadas (PR): http://localhost:${port}/api/invoices/paid/{cardcode}`)
    console.log(`   Solo pendientes: http://localhost:${port}/api/invoices/pending/{cardcode}`)
    console.log(`   Búsqueda: http://localhost:${port}/api/invoices/search`)

    console.log("\n✅ Servidor listo para recibir peticiones")
    console.log("🛑 Presiona Ctrl+C para detener")
  })

  // Manejo de errores del servidor
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.error(`❌ Error: El puerto ${port} está en uso`)
      console.log("💡 Soluciones:")
      console.log("1. Espera unos segundos y vuelve a intentar")
      console.log("2. Cambia el puerto en la línea 'const port = 3006'")
      console.log("3. Mata el proceso que usa el puerto:")
      console.log(`   Windows: netstat -ano | findstr :${port}`)
      console.log(`   Linux/Mac: lsof -ti:${port} | xargs kill`)
    } else {
      console.error("❌ Error al iniciar el servidor:", err.message)
    }
    process.exit(1)
  })

  return server
}

// 🛑 Manejo de cierre graceful
process.on("SIGINT", async () => {
  console.log("\n🛑 Cerrando servidor...")

  if (globalPool) {
    try {
      await globalPool.close()
      console.log("🔌 Desconectado de la base de datos")
    } catch (error) {
      console.error("❌ Error cerrando conexión:", error.message)
    }
  }

  console.log("👋 ¡Hasta luego!")
  process.exit(0)
})

// 🚨 Manejo de errores no capturados
process.on("unhandledRejection", (reason, promise) => {
  console.error("❌ Unhandled Rejection at:", promise)
  console.error("📍 Reason:", reason)
})

process.on("uncaughtException", (error) => {
  console.error("❌ Uncaught Exception:", error.message)
  console.error("📍 Stack:", error.stack)
  process.exit(1)
})

// 🚀 Iniciar el servidor
if (require.main === module) {
  startServer().catch((error) => {
    console.error("❌ Error fatal al iniciar:", error.message)
    process.exit(1)
  })
}

module.exports = { app, startServer, connectToDatabase }
