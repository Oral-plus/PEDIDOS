const express = require("express");
const sql = require("mssql");
const cors = require("cors");
const os = require("os");
const fs = require("fs").promises;
const path = require("path");

const app = express();
const port = 3007;

// 🔧 MIDDLEWARE MEJORADO
app.use(
  cors({
    origin: "*", // Permitir todos los orígenes para desarrollo
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allowedHeaders: ["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"],
    credentials: false,
  })
);

app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

// 🔧 LOGGING MIDDLEWARE
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`📡 [${timestamp}] ${req.method} ${req.url}`);
  console.log(`📋 Headers:`, JSON.stringify(req.headers, null, 2));
  if (req.body && Object.keys(req.body).length > 0) {
    console.log(`📦 Body:`, JSON.stringify(req.body, null, 2));
  }
  next();
});

// 🔧 CONFIGURACIÓN DE LA BASE DE DATOS
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
};

// 📧 CONFIGURACIÓN DE COLA DE CORREO LOCAL
const emailQueueDir = path.join(__dirname, "email_queue");
async function initializeEmailQueue() {
  try {
    await fs.mkdir(emailQueueDir, { recursive: true });
    console.log(`✅ Directorio de cola de correos creado: ${emailQueueDir}`);
  } catch (error) {
    console.error(`❌ Error creando directorio de cola de correos: ${error.message}`);
  }
}

// Variable global para el pool de conexiones
let globalPool = null;

// 🔗 Función para conectar a la base de datos
async function connectToDatabase() {
  if (globalPool && globalPool.connected) {
    return globalPool;
  }
  try {
    console.log("🔄 Conectando a la base de datos...");
    console.log(`📍 Servidor: ${dbConfig.server}:${dbConfig.port}`);
    console.log(`🗄️ Base de datos: ${dbConfig.database}`);
    console.log(`👤 Usuario: ${dbConfig.user}`);

    globalPool = new sql.ConnectionPool(dbConfig);
    await globalPool.connect();
    console.log("✅ Conectado a SQL Server exitosamente");
    return globalPool;
  } catch (err) {
    console.error("❌ Error conectando a la base de datos:", err.message);
    throw err;
  }
}

// 📧 Función para guardar correo en cola local
async function guardarCorreoLocal(destinatario, nombre, subtotal, docNum, docEntry, productos = []) {
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const fileName = `email_${timestamp}_${destinatario.replace(/[@.]/g, "_")}.json`;
    const filePath = path.join(emailQueueDir, fileName);

    const productosData = productos.map(p => ({
      codigo: p.codigo,
      nombre: p.nombre || p.codigo,
      cantidad: p.cantidad,
      precio: Number(p.precio).toLocaleString(),
    }));

    const emailData = {
      to: destinatario,
      subject: `Confirmación de compra para ${nombre}`,
      nombre,
      subtotal,
      docNum,
      docEntry,
      productos: productosData,
      timestamp: new Date().toISOString(),
    };

    await fs.writeFile(filePath, JSON.stringify(emailData, null, 2));
    console.log(`✅ Correo guardado localmente: ${filePath}`);
    return true;
  } catch (error) {
    console.error(`❌ Error guardando correo localmente: ${error.message}`);
    return false;
  }
}

// 📦 Función para crear orden en SQL Server
async function crearOrdenSQL(cardCode, productos, observaciones) {
  try {
    const pool = await connectToDatabase();
    const transaction = new sql.Transaction(pool);
    await transaction.begin();

    try {
      // Insertar en ORDR (encabezado de la orden)
      const docDate = new Date().toISOString().split("T")[0];
      const headerQuery = `
        INSERT INTO ORDR (
          CardCode, DocDate, DocDueDate, U_PAGINAWEB, DiscountPercent, Comments, DocStatus, DocType
        )
        OUTPUT INSERTED.DocEntry, INSERTED.DocNum
        VALUES (@CardCode, @DocDate, @DocDate, @PaginaWeb, @DiscountPercent, @Comments, 'O', 'I')
      `;

      const headerRequest = new sql.Request(transaction);
      headerRequest.input("CardCode", sql.VarChar, cardCode);
      headerRequest.input("DocDate", sql.Date, docDate);
      headerRequest.input("PaginaWeb", sql.VarChar, "APP");
      headerRequest.input("DiscountPercent", sql.Float, 3);
      headerRequest.input("Comments", sql.NVarChar, observaciones || "");

      const headerResult = await headerRequest.query(headerQuery);
      const { DocEntry, DocNum } = headerResult.recordset[0];

      console.log(`✅ Orden creada en ORDR - DocEntry: ${DocEntry}, DocNum: ${DocNum}`);

      // Insertar líneas en RDR1
      for (let i = 0; i < productos.length; i++) {
        const p = productos[i];
        const lineQuery = `
          INSERT INTO RDR1 (
            DocEntry, LineNum, ItemCode, Quantity, LineStatus
          )
          VALUES (@DocEntry, @LineNum, @ItemCode, @Quantity, 'O')
        `;

        const lineRequest = new sql.Request(transaction);
        lineRequest.input("DocEntry", sql.Int, DocEntry);
        lineRequest.input("LineNum", sql.Int, i);
        lineRequest.input("ItemCode", sql.VarChar, p.codigo || p.codigoSap);
        lineRequest.input("Quantity", sql.Int, Number.parseInt(p.cantidad));

        await lineRequest.query(lineQuery);
        console.log(`✅ Línea ${i} insertada en RDR1 - ItemCode: ${p.codigo || p.codigoSap}`);
      }

      await transaction.commit();
      console.log("✅ Transacción confirmada");
      return { DocEntry, DocNum };
    } catch (error) {
      await transaction.rollback();
      console.error("❌ Error en transacción SQL:", error.message);
      throw error;
    }
  } catch (error) {
    console.error("❌ Error creando orden en SQL Server:", error.message);
    throw error;
  }
}

// ✅ ENDPOINT: Obtener cliente SAP (sin .php)
app.get("/api/obtener_cliente_sap", async (req, res) => {
  const startTime = Date.now();
  const cardCode = req.query.cardcode;

  console.log(`👤 [${new Date().toISOString()}] Consulta cliente SAP - CardCode: ${cardCode}`);

  if (!cardCode || cardCode.trim() === "") {
    console.log("❌ CardCode vacío");
    return res.json(["CardCode no puede estar vacío"]);
  }

  try {
    const pool = await connectToDatabase();

    const query = `
      SELECT 
        T0.[CardName],
        T0.[Address], 
        T0.[Phone1],
        T0.E_Mail,
        T0.[CardCode]
      FROM OCRD T0
      INNER JOIN OCRG T1 ON T0.[GroupCode] = T1.[GroupCode] 
      INNER JOIN dbo.[@DISTRIBUCION] T2 ON T0.U_CANAL_DISTRIBUCION = T2.Code
      WHERE T0.CardCode = @cardCode 
        AND T1.[GroupName] <> 'Droguerias Cadenas'
        AND T1.[GroupName] <> 'Canal Grandes Superf' 
        AND T2.Name <> 'HARD DISCOUNT NACIONALES' 
        AND T2.Name <> 'HARD DISCOUNT INDEPENDIENTES'
    `;

    console.log("🔍 Ejecutando consulta SQL...");
    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta SAP ejecutada en ${queryTime}ms`);
    console.log(`📊 Registros encontrados: ${result.recordset.length}`);

    if (result.recordset.length === 0) {
      console.log("📭 Cliente no encontrado");
      return res.json(["No se encontraron datos para la cédula proporcionada"]);
    }

    const clientData = result.recordset[0];
    console.log("✅ Datos del cliente encontrados en SAP:");
    console.log(`   👤 Nombre: ${clientData.CardName}`);
    console.log(`   📍 Dirección: ${clientData.Address || "N/A"}`);
    console.log(`   📞 Teléfono: ${clientData.Phone1 || "N/A"}`);
    console.log(`   📧 Email: ${clientData.E_Mail || "N/A"}`);

    res.json({
      CardName: clientData.CardName || "",
      Address: clientData.Address || "",
      Phone1: clientData.Phone1 || "",
      E_Mail: clientData.E_Mail || "",
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error en consulta cliente SAP:", error.message);
    res.status(500).json({
      error: "Error interno del servidor",
      details: error.message,
      queryTime: queryTime,
    });
  }
});

// ✅ ENDPOINT: Obtener todas las listas de precios disponibles
app.get("/api/obtener_listas_precios", async (req, res) => {
  const startTime = Date.now();
  console.log(`💰 [${new Date().toISOString()}] Consultando todas las listas de precios`);

  try {
    const pool = await connectToDatabase();
    const query = `
      SELECT 
        ListNum as id,
        ListName as nombre
      FROM OPLN
      ORDER BY ListNum
    `;

    console.log("🔍 Ejecutando consulta SQL...");
    const result = await pool.request().query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta ejecutada en ${queryTime}ms`);
    console.log(`📊 Listas de precios encontradas: ${result.recordset.length}`);

    res.json({
      success: true,
      listasPrecios: result.recordset,
      total: result.recordset.length,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error obteniendo listas de precios:", error.message);
    res.status(500).json({
      success: false,
      error: "Error interno del servidor al obtener listas de precios",
      details: error.message,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  }
});

// ✅ ENDPOINT: Obtener lista de precios del cliente
app.get("/api/obtener_lista_precios_cliente", async (req, res) => {
  const startTime = Date.now();
  const { cardcode } = req.query;

  console.log(`📋 [${new Date().toISOString()}] Consulta lista de precios SAP - CardCode: ${cardcode}`);

  if (!cardcode || cardcode.trim() === "") {
    console.log("❌ CardCode vacío");
    return res.status(400).json({
      success: false,
      error: "CardCode es requerido",
    });
  }

  try {
    const pool = await connectToDatabase();
    const query = `
      SELECT ISNULL(T0.ListNum, 1) as ListaPrecios
      FROM OCRD T0
      WHERE T0.CardCode = @cardCode
    `;

    console.log("🔍 Ejecutando consulta SQL...");
    const result = await pool.request().input("cardCode", sql.VarChar, cardcode).query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta SAP ejecutada en ${queryTime}ms`);

    const listaPrecios = result.recordset.length > 0 ? parseInt(result.recordset[0].ListaPrecios) : 1;
    console.log(`✅ Lista de precios obtenida: ${listaPrecios}`);

    res.json({
      success: true,
      listaPrecios: listaPrecios,
      cardCode: cardcode,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error obteniendo lista de precios SAP:", error.message);
    res.status(500).json({
      success: false,
      error: `Error obteniendo lista de precios: ${error.message}`,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  }
});

// ✅ ENDPOINT: Obtener precios SAP (sin .php)
app.get("/api/obtener_precios_sap", async (req, res) => {
  const startTime = Date.now();
  const { codigos, cliente, lista_precios } = req.query;

  console.log(`💰 [${new Date().toISOString()}] Consulta precios SAP`);
  console.log(`📋 Códigos: ${codigos}`);
  console.log(`👤 Cliente: ${cliente}`);
  console.log(`📋 Lista de precios: ${lista_precios}`);

  if (!codigos || !cliente) {
    return res.json({
      error: "Códigos y cliente son requeridos",
      success: false,
    });
  }

  try {
    const pool = await connectToDatabase();
    const codigosArray = codigos.split(",");
    const priceList = parseInt(lista_precios) || 1;

    const query = `
      SELECT 
        T0.ItemCode,
        T0.ItemName,
        ISNULL(T1.Price, 0) as Price,
        T0.OnHand,
        T0.IsCommited,
        T0.OnOrder,
        (T0.OnHand - T0.IsCommited) as Available
      FROM OITM T0
      LEFT JOIN ITM1 T1 ON T0.ItemCode = T1.ItemCode AND T1.PriceList = @PriceList
      WHERE T0.ItemCode IN (${codigosArray.map((_, i) => `@codigo${i}`).join(",")})
    `;

    const request = pool.request().input("PriceList", sql.Int, priceList);
    codigosArray.forEach((codigo, i) => {
      request.input(`codigo${i}`, sql.VarChar, codigo.trim());
    });

    console.log("💰 Consultando precios SAP...");
    const result = await request.query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta precios ejecutada en ${queryTime}ms`);

    const precios = {};
    result.recordset.forEach((item) => {
      precios[item.ItemCode] = {
        codigo: item.ItemCode,
        nombre: item.ItemName,
        precio: item.Price.toString(),
        disponible: item.Available,
        stock: item.OnHand,
      };
    });

    console.log(`✅ PRECIOS SAP OBTENIDOS: ${Object.keys(precios).length} productos`);

    res.json({
      success: true,
      precios: precios,
      total: Object.keys(precios).length,
      lista_precios_usada: priceList,
      cliente: cliente,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error obteniendo precios SAP:", error.message);
    res.json({
      error: `Error obteniendo precios: ${error.message}`,
      success: false,
      queryTime: queryTime,
    });
  }
});

// ✅ ENDPOINT: Obtener estados productos SAP (sin .php)
app.get("/api/obtener_estados_productos_sap", async (req, res) => {
  const startTime = Date.now();
  const { codigos, cliente } = req.query;

  console.log(`📦 [${new Date().toISOString()}] Consulta estados SAP`);
  console.log(`📋 Códigos: ${codigos}`);
  console.log(`👤 Cliente: ${cliente}`);

  if (!codigos || !cliente) {
    return res.json({
      error: "Códigos y cliente son requeridos",
      success: false,
      productos: {},
    });
  }

  try {
    const pool = await connectToDatabase();
    const codigosArray = codigos.split(",");

    const query = `
      SELECT 
        T0.ItemCode,
        T0.ItemName,
        T0.OnHand,
        T0.IsCommited,
        T0.OnOrder,
        (T0.OnHand - T0.IsCommited) as Available,
        CASE 
          WHEN (T0.OnHand - T0.IsCommited) > 0 THEN 'Disponible'
          ELSE 'Sin stock'
        END as Estado
      FROM OITM T0
      WHERE T0.ItemCode IN (${codigosArray.map((_, i) => `@codigo${i}`).join(",")})
    `;

    const request = pool.request();
    codigosArray.forEach((codigo, i) => {
      request.input(`codigo${i}`, sql.VarChar, codigo.trim());
    });

    console.log("📦 Consultando estados SAP...");
    const result = await request.query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta estados ejecutada en ${queryTime}ms`);

    const productos = {};
    result.recordset.forEach((item) => {
      productos[item.ItemCode] = {
        codigo: item.ItemCode,
        nombre: item.ItemName,
        disponible: item.Available > 0,
        stock: item.OnHand,
        comprometido: item.IsCommited,
        disponible_cantidad: item.Available,
        estado: item.Estado,
        mensaje: item.Available > 0 ? "Producto disponible" : "Sin stock disponible",
      };
    });

    console.log(`✅ ESTADOS SAP OBTENIDOS: ${Object.keys(productos).length} productos`);

    res.json({
      success: true,
      productos: productos,
      total: Object.keys(productos).length,
      cliente: cliente,
      codigos_consultados: codigosArray.length,
      codigos_encontrados: Object.keys(productos).length,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error obteniendo estados SAP:", error.message);
    res.json({
      error: `Error obteniendo estados: ${error.message}`,
      success: false,
      productos: {},
      queryTime: queryTime,
    });
  }
});

// 👤 ENDPOINT: Obtener datos del cliente por CardCode
app.get("/api/client/data/:cardCode", async (req, res) => {
  const startTime = Date.now();
  const cardCode = req.params.cardCode;
  console.log(`👤 [${new Date().toISOString()}] Consulta de cliente SAP - CardCode: ${cardCode}`);

  if (!cardCode || cardCode.trim() === "") {
    console.log("❌ CardCode vacío o no proporcionado");
    return res.status(400).json({
      success: false,
      error: "CardCode no puede estar vacío",
    });
  }

  try {
    const pool = await connectToDatabase();
    const query = `
      SELECT 
        T0.[CardName],
        T0.[Address],
        T0.[Phone1],
        T0.E_Mail,
        T0.[CardCode]
      FROM OCRD T0
      INNER JOIN OCRG T1 ON T0.[GroupCode] = T1.[GroupCode] 
      INNER JOIN dbo.[@DISTRIBUCION] T2 ON T0.U_CANAL_DISTRIBUCION = T2.Code
      WHERE T0.CardCode = @cardCode 
        AND T1.[GroupName] <> 'Droguerias Cadenas'
        AND T1.[GroupName] <> 'Canal Grandes Superf' 
        AND T2.Name <> 'HARD DISCOUNT NACIONALES' 
        AND T2.Name <> 'HARD DISCOUNT INDEPENDIENTES'
    `;

    console.log("🔍 Ejecutando consulta SQL en SAP...");
    const result = await pool.request().input("cardCode", sql.VarChar, cardCode).query(query);

    const queryTime = Date.now() - startTime;
    console.log(`⏱️ Consulta SAP ejecutada en ${queryTime}ms`);
    console.log(`📊 Registros encontrados: ${result.recordset.length}`);

    if (result.recordset.length === 0) {
      console.log("📭 No se encontraron datos en SAP para el CardCode proporcionado");
      res.setHeader("Content-Type", "application/json");
      return res.json(["No se encontraron datos para la cédula proporcionada"]);
    }

    const clientData = result.recordset[0];
    console.log("✅ Datos del cliente encontrados en SAP:");
    console.log(`   👤 Nombre: ${clientData.CardName}`);
    console.log(`   📍 Dirección: ${clientData.Address || "N/A"}`);
    console.log(`   📞 Teléfono: ${clientData.Phone1 || "N/A"}`);
    console.log(`   📧 Email: ${clientData.E_Mail || "N/A"}`);

    res.setHeader("Content-Type", "application/json");
    res.json({
      CardName: clientData.CardName || "",
      Address: clientData.Address || "",
      Phone1: clientData.Phone1 || "",
      E_Mail: clientData.E_Mail || "",
    });
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error en consulta de cliente SAP:", error.message);
    res.status(500).json({
      success: false,
      error: "Error interno del servidor al consultar datos del cliente en SAP",
      details: error.message,
      cardCode: cardCode,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    });
  }
});

// 🛒 ENDPOINT: Procesar compra
app.post("/api/purchase/process", async (req, res) => {
  const startTime = Date.now();
  console.log(`🛒 [${new Date().toISOString()}] === PROCESANDO COMPRA SAP ===`);
  console.log("📦 Datos recibidos:", JSON.stringify(req.body, null, 2));

  res.setHeader("Content-Type", "application/json");
  try {
    const { cedula, productos, correo, nombre, subtotal, direccion, telefono, observaciones } = req.body;

    if (!cedula || cedula.trim() === "") {
      console.log("❌ Validación fallida: Cédula vacía");
      return res.status(400).json({
        success: false,
        message: "La cédula es requerida",
      });
    }

    if (!productos || !Array.isArray(productos) || productos.length === 0) {
      console.log("❌ Validación fallida: Productos vacíos");
      return res.status(400).json({
        success: false,
        message: "La lista de productos es requerida",
      });
    }

    for (let i = 0; i < productos.length; i++) {
      const p = productos[i];
      const codigo = p.codigo || p.codigoSap;
      if (!codigo || !p.cantidad) {
        console.log(`❌ Validación fallida: Producto #${i + 1} incompleto`);
        return res.status(400).json({
          success: false,
          message: `Faltan datos en el producto #${i + 1}`,
        });
      }
    }

    console.log(`📋 Procesando compra para: ${nombre} (${cedula})`);
    console.log(`📧 Correo: ${correo}`);
    console.log(`📦 Productos: ${productos.length}`);
    console.log(`💰 Subtotal: ${subtotal}`);

    console.log("📦 Creando orden en SQL Server...");
    const { DocEntry, DocNum } = await crearOrdenSQL(cedula, productos, observaciones);

    console.log(`✅ Orden creada - DocEntry: ${DocEntry}, DocNum: ${DocNum}`);

    let emailSent = false;
    if (correo && nombre) {
      console.log("📧 Guardando correo en cola local...");
      emailSent = await guardarCorreoLocal(correo, nombre, subtotal, DocNum, DocEntry, productos);
      console.log(`📧 Correo ${emailSent ? "guardado" : "falló"}`);
    }

    const processingTime = Date.now() - startTime;
    console.log(`⏱️ Compra procesada en ${processingTime}ms`);

    const response = {
      success: true,
      message: `Orden creada${emailSent ? " y correo guardado correctamente." : "."}`,
      DocEntry: DocEntry,
      DocNum: DocNum,
      emailSent: emailSent,
      processingTime: processingTime,
    };

    console.log("✅ === COMPRA COMPLETADA EXITOSAMENTE ===");
    console.log("📤 Respuesta:", JSON.stringify(response, null, 2));
    res.json(response);
  } catch (error) {
    const processingTime = Date.now() - startTime;
    console.error("❌ === ERROR EN COMPRA ===");
    console.error("🔧 Error:", error.message);
    console.error("🔧 Stack:", error.stack);

    const errorResponse = {
      success: false,
      message: `Error al procesar la compra: ${error.message}`,
      error: error.message,
      processingTime: processingTime,
      timestamp: new Date().toISOString(),
    };

    console.log("❌ Respuesta de error:", JSON.stringify(errorResponse, null, 2));
    res.status(500).json(errorResponse);
  }
});

// 🧪 ENDPOINT: Validar disponibilidad de productos
app.post("/api/purchase/validate", async (req, res) => {
  const startTime = Date.now();
  console.log(`🧪 [${new Date().toISOString()}] Validando disponibilidad de productos`);

  try {
    const { productos } = req.body;

    if (!productos || !Array.isArray(productos) || productos.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Lista de productos requerida",
      });
    }

    console.log(`📦 Validando ${productos.length} productos...`);

    const pool = await connectToDatabase();
    const codigosArray = productos.map(p => p.codigo || p.codigoSap);

    const query = `
      SELECT 
        T0.ItemCode,
        T0.ItemName,
        (T0.OnHand - T0.IsCommited) as Available
      FROM OITM T0
      WHERE T0.ItemCode IN (${codigosArray.map((_, i) => `@codigo${i}`).join(",")})
    `;

    const request = pool.request();
    codigosArray.forEach((codigo, i) => {
      request.input(`codigo${i}`, sql.VarChar, codigo.trim());
    });

    const result = await request.query(query);

    const validationResults = productos.map((producto) => {
      const item = result.recordset.find(r => r.ItemCode === (producto.codigo || producto.codigoSap));
      const disponible = item ? item.Available : 0;
      const solicitado = Number.parseInt(producto.cantidad) || 0;
      return {
        codigo: producto.codigo || producto.codigoSap,
        nombre: producto.descripcion || (item ? item.ItemName : `Producto ${producto.codigo}`),
        disponible: disponible,
        solicitado: solicitado,
        suficiente: disponible >= solicitado,
      };
    });

    const allAvailable = validationResults.every(r => r.suficiente);
    const validationTime = Date.now() - startTime;

    console.log(`⏱️ Validación completada en ${validationTime}ms`);

    res.json({
      success: allAvailable,
      message: allAvailable ? "Todos los productos están disponibles" : "Algunos productos no están disponibles",
      products: validationResults,
      validationTime: validationTime,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const validationTime = Date.now() - startTime;
    console.error("❌ Error en validación de productos:", error.message);
    res.status(500).json({
      success: false,
      message: "Error interno del servidor al validar productos",
      error: error.message,
      validationTime: validationTime,
      timestamp: new Date().toISOString(),
    });
  }
});

// 🧪 Endpoint de prueba de conexión
app.get("/api/test", async (req, res) => {
  const startTime = Date.now();
  console.log(`🧪 [${new Date().toISOString()}] Test de conexión solicitado`);

  try {
    console.log("🧪 Ejecutando test de conexión a SAP...");
    const pool = await connectToDatabase();
    const result = await pool.request().query("SELECT 1 as test, GETDATE() as server_time");
    const queryTime = Date.now() - startTime;

    console.log("✅ Test de conexión SAP exitoso");

    const response = {
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
      database_info: {
        server: dbConfig.server,
        database: dbConfig.database,
        user: dbConfig.user,
        connected: pool.connected,
      },
      test_query: result.recordset[0],
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    };

    console.log("📤 Enviando respuesta de test:", JSON.stringify(response, null, 2));
    res.json(response);
  } catch (error) {
    const queryTime = Date.now() - startTime;
    console.error("❌ Error en test de conexión SAP:", error.message);
    const errorResponse = {
      success: false,
      status: "Error en la API SAP",
      error: error.message,
      queryTime: queryTime,
      timestamp: new Date().toISOString(),
    };
    console.log("📤 Enviando respuesta de error:", JSON.stringify(errorResponse, null, 2));
    res.status(500).json(errorResponse);
  }
});

// 🚫 Manejo de rutas no encontradas
app.use("*", (req, res) => {
  console.log(`❌ Ruta no encontrada: ${req.method} ${req.originalUrl}`);
  res.status(404).json({
    success: false,
    error: "Ruta no encontrada",
    path: req.originalUrl,
    method: req.method,
    availableEndpoints: [
      "GET /api/test - Prueba de conexión SAP",
      "GET /api/client/data/:cardcode - Datos del cliente SAP",
      "GET /api/obtener_cliente_sap?cardcode=XXX - Cliente SAP (Flutter compatible)",
      "GET /api/obtener_listas_precios - Todas las listas de precios disponibles",
      "GET /api/obtener_lista_precios_cliente?cardcode=XXX - Lista de precios SAP",
      "GET /api/obtener_precios_sap?codigos=XXX&cliente=YYY - Precios SAP (Flutter compatible)",
      "GET /api/obtener_estados_productos_sap?codigos=XXX&cliente=YYY - Estados SAP (Flutter compatible)",
      "POST /api/purchase/process - Procesar compra en SAP",
      "POST /api/purchase/validate - Validar disponibilidad de productos",
    ],
    timestamp: new Date().toISOString(),
  });
});

// 🚀 Función para iniciar el servidor
async function startServer() {
  console.log("🚀 Iniciando servidor SAP Business One...");
  console.log("=".repeat(60));

  console.log(`🖥️ Sistema: ${os.platform()} ${os.arch()}`);
  console.log(`📍 Host: ${os.hostname()}`);
  console.log(`🔧 Node.js: ${process.version}`);

  console.log("\n🗄️ Configuración SAP Business One:");
  console.log(`   Servidor: ${dbConfig.server}:${dbConfig.port}`);
  console.log(`   Base de datos: ${dbConfig.database}`);
  console.log(`   Usuario: ${dbConfig.user}`);

  console.log("\n📧 Configuración de cola de correos local:");
  console.log(`   Directorio: ${emailQueueDir}`);

  try {
    await connectToDatabase();
    await initializeEmailQueue();
  } catch (error) {
    console.log("\n❌ No se pudo conectar a SAP Business One o inicializar cola de correos");
    console.log("⚠️ El servidor iniciará pero algunas funciones pueden fallar");
  }

  const server = app.listen(port, "0.0.0.0", () => {
    console.log("\n🎉 ¡Servidor SAP iniciado exitosamente!");
    console.log("=".repeat(60));
    console.log(`🌐 Puerto: ${port}`);
    console.log(`🔗 URL local: http://localhost:${port}/api`);

    console.log("\n🧪 Endpoints SAP disponibles:");
    console.log(`   Test conexión: http://localhost:${port}/api/test`);
    console.log(`   Cliente SAP: http://localhost:${port}/api/client/data/{cardcode}`);
    console.log(`   Listas de precios: http://localhost:${port}/api/obtener_listas_precios`);
    console.log(`   🛒 PROCESAR COMPRA: http://localhost:${port}/api/purchase/process`);
    console.log(`   🧪 VALIDAR PRODUCTOS: http://localhost:${port}/api/purchase/validate`);

    console.log("\n✅ ENDPOINTS FLUTTER COMPATIBLES:");
    console.log(`   📋 CLIENTE: http://localhost:${port}/api/obtener_cliente_sap?cardcode=XXX`);
    console.log(`   📋 LISTA PRECIOS: http://localhost:${port}/api/obtener_lista_precios_cliente?cardcode=XXX`);
    console.log(`   💰 PRECIOS: http://localhost:${port}/api/obtener_precios_sap?codigos=XXX&cliente=YYY`);
    console.log(`   📦 ESTADOS: http://localhost:${port}/api/obtener_estados_productos_sap?codigos=XXX&cliente=YYY`);

    console.log("\n💡 Para probar desde Flutter:");
    console.log(`   Endpoint: http://localhost:${port}/api/obtener_precios_sap`);
    console.log(`   Método: GET`);
    console.log(`   Parámetros: ?codigos=50360251,50360256&cliente=123456789`);

    console.log("\n✅ Servidor SAP listo - Operando localmente");
    console.log("🛑 Presiona Ctrl+C para detener");
  });

  return server;
}

// 🛑 Manejo de cierre graceful
process.on("SIGINT", async () => {
  console.log("\n🛑 Cerrando servidor SAP...");
  if (globalPool) {
    try {
      await globalPool.close();
      console.log("🔌 Desconectado de SAP Business One");
    } catch (error) {
      console.error("❌ Error cerrando conexión SAP:", error.message);
    }
  }
  console.log("👋 ¡Hasta luego!");
  process.exit(0);
});

// 🚀 Iniciar el servidor
if (require.main === module) {
  startServer().catch((error) => {
    console.error("❌ Error fatal al iniciar servidor SAP:", error.message);
    process.exit(1);
  });
}

module.exports = { app, startServer, connectToDatabase };