const { sql, getOrdersPool } = require('../config/database');

async function ensureTables() {
  const pool = await getOrdersPool();
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pedidos')
    BEGIN
      CREATE TABLE pedidos (
        id INT IDENTITY(1,1) PRIMARY KEY,
        numero_pedido NVARCHAR(50) UNIQUE NOT NULL,
        codigo_cliente NVARCHAR(50) NOT NULL DEFAULT '',
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
        sincronizado_sap BIT NOT NULL DEFAULT 0
      );
    END
  `);
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pedidos_detalle')
    BEGIN
      CREATE TABLE pedidos_detalle (
        id INT IDENTITY(1,1) PRIMARY KEY,
        pedido_id INT NOT NULL,
        codigo_producto NVARCHAR(50) NOT NULL,
        nombre_producto NVARCHAR(200) NOT NULL,
        textura NVARCHAR(50) NULL,
        cantidad INT NOT NULL DEFAULT 1,
        precio_unitario DECIMAL(18,2) NOT NULL DEFAULT 0,
        total_linea DECIMAL(18,2) NOT NULL DEFAULT 0,
        CONSTRAINT FK_pedidos_detalle_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE
      );
    END
  `);
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pedidos_historial')
    BEGIN
      CREATE TABLE pedidos_historial (
        id INT IDENTITY(1,1) PRIMARY KEY,
        pedido_id INT NOT NULL,
        estado_anterior NVARCHAR(20) NULL,
        estado_nuevo NVARCHAR(20) NOT NULL,
        comentario NVARCHAR(500) NULL,
        usuario NVARCHAR(100) NULL,
        fecha DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_historial_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE
      );
    END
  `);
  await pool.request().query(`
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'direcciones_entrega')
    BEGIN
      CREATE TABLE direcciones_entrega (
        id INT IDENTITY(1,1) PRIMARY KEY,
        codigo_cliente NVARCHAR(50) NOT NULL,
        nombre_cliente NVARCHAR(200) NULL,
        direccion NVARCHAR(500) NOT NULL,
        ciudad NVARCHAR(100) NULL,
        telefono NVARCHAR(30) NULL,
        vendedor NVARCHAR(100) NULL,
        pedido_id INT NULL,
        numero_pedido NVARCHAR(50) NULL,
        origen NVARCHAR(20) NOT NULL DEFAULT 'APP',
        fecha_registro DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_direccion_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE SET NULL
      );
      CREATE INDEX IX_direccion_cliente ON direcciones_entrega(codigo_cliente);
    END
  `);
}

let tablesReady = false;

async function generarNumeroPedido() {
  const pool = await getOrdersPool();
  const result = await pool.request().query(`
    SELECT TOP 1 numero_pedido FROM pedidos ORDER BY id DESC
  `);

  let siguiente = 1;
  if (result.recordset.length > 0) {
    const ultimo = result.recordset[0].numero_pedido;
    const num = parseInt(ultimo.replace(/\D/g, ''), 10);
    if (!isNaN(num)) siguiente = num + 1;
  }

  const fecha = new Date();
  const yy = fecha.getFullYear().toString().slice(-2);
  const mm = (fecha.getMonth() + 1).toString().padStart(2, '0');
  return `PED-${yy}${mm}-${siguiente.toString().padStart(5, '0')}`;
}

async function crearPedido({ cedula, nombre, correo, telefono, direccion, subtotal, productos, observaciones, codigoCliente, vendedor, ciudad }) {
  if (!tablesReady) {
    await ensureTables();
    tablesReady = true;
  }
  const pool = await getOrdersPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const numeroPedido = await generarNumeroPedido();
    const total = subtotal;

    const insertPedido = new sql.Request(transaction);
    const pedidoResult = await insertPedido
      .input('numero_pedido', sql.NVarChar, numeroPedido)
      .input('codigo_cliente', sql.NVarChar, (codigoCliente || cedula || '').trim())
      .input('cedula_cliente', sql.NVarChar, cedula)
      .input('nombre_cliente', sql.NVarChar, nombre)
      .input('correo', sql.NVarChar, correo)
      .input('telefono', sql.NVarChar, telefono || null)
      .input('direccion', sql.NVarChar, direccion || null)
      .input('subtotal', sql.Decimal(18, 2), subtotal)
      .input('iva', sql.Decimal(18, 2), 0)
      .input('total', sql.Decimal(18, 2), total)
      .input('observaciones', sql.NVarChar, observaciones || null)
      .input('vendedor', sql.NVarChar, ((vendedor || '').trim() || 'Sistema'))
      .query(`
        INSERT INTO pedidos (numero_pedido, codigo_cliente, cedula_cliente, nombre_cliente, correo, telefono, direccion, subtotal, iva, total, observaciones, vendedor)
        OUTPUT INSERTED.id, INSERTED.numero_pedido
        VALUES (@numero_pedido, @codigo_cliente, @cedula_cliente, @nombre_cliente, @correo, @telefono, @direccion, @subtotal, @iva, @total, @observaciones, @vendedor)
      `);

    const pedidoId = pedidoResult.recordset[0].id;

    for (const prod of productos) {
      const insertDetalle = new sql.Request(transaction);
      await insertDetalle
        .input('pedido_id', sql.Int, pedidoId)
        .input('codigo_producto', sql.NVarChar, prod.codigo)
        .input('nombre_producto', sql.NVarChar, prod.nombre || prod.title || '')
        .input('textura', sql.NVarChar, prod.textura || null)
        .input('cantidad', sql.Int, prod.cantidad || 1)
        .input('precio_unitario', sql.Decimal(18, 2), prod.precio || 0)
        .input('total_linea', sql.Decimal(18, 2), prod.total || 0)
        .query(`
          INSERT INTO pedidos_detalle (pedido_id, codigo_producto, nombre_producto, textura, cantidad, precio_unitario, total_linea)
          VALUES (@pedido_id, @codigo_producto, @nombre_producto, @textura, @cantidad, @precio_unitario, @total_linea)
        `);
    }

    // Registrar en historial
    const insertHist = new sql.Request(transaction);
    await insertHist
      .input('pedido_id', sql.Int, pedidoId)
      .input('estado_nuevo', sql.NVarChar, 'PENDIENTE')
      .input('comentario', sql.NVarChar, 'Pedido creado desde la app')
      .input('usuario', sql.NVarChar, ((vendedor || '').trim() || 'APP'))
      .query(`
        INSERT INTO pedidos_historial (pedido_id, estado_nuevo, comentario, usuario)
        VALUES (@pedido_id, @estado_nuevo, @comentario, @usuario)
      `);

    // Registrar dirección de entrega
    if (direccion && direccion.trim()) {
      const insertDir = new sql.Request(transaction);
      await insertDir
        .input('codigo_cliente', sql.NVarChar, (codigoCliente || cedula || '').trim())
        .input('nombre_cliente', sql.NVarChar, nombre || null)
        .input('direccion', sql.NVarChar, direccion.trim())
        .input('ciudad', sql.NVarChar, (ciudad || '').trim() || null)
        .input('telefono', sql.NVarChar, telefono || null)
        .input('vendedor', sql.NVarChar, (vendedor || '').trim() || null)
        .input('pedido_id', sql.Int, pedidoId)
        .input('numero_pedido', sql.NVarChar, numeroPedido)
        .query(`
          INSERT INTO direcciones_entrega (codigo_cliente, nombre_cliente, direccion, ciudad, telefono, vendedor, pedido_id, numero_pedido)
          VALUES (@codigo_cliente, @nombre_cliente, @direccion, @ciudad, @telefono, @vendedor, @pedido_id, @numero_pedido)
        `);
    }

    await transaction.commit();

    console.log(`✅ [BD Pedidos] ${numeroPedido} - ID: ${pedidoId} - $${total}`);

    return {
      success: true,
      message: 'Pedido registrado correctamente',
      docEntry: pedidoId,
      docNum: numeroPedido,
    };
  } catch (err) {
    try { await transaction.rollback(); } catch (_) {}
    throw err;
  }
}

async function obtenerPedidosPorCliente(codigoCliente, estado) {
  if (!codigoCliente || codigoCliente.trim() === '') {
    return { success: false, message: 'Código de cliente requerido', data: [] };
  }
  if (!tablesReady) { await ensureTables(); tablesReady = true; }
  const pool = await getOrdersPool();
  const req = pool.request();
  req.input('cliente', sql.NVarChar, codigoCliente.trim());

  let query = `
    SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
           p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
           p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
           (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_productos,
           (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_unidades
    FROM pedidos p
    WHERE p.codigo_cliente = @cliente
  `;

  if (estado && estado.trim() !== '') {
    query += ' AND p.estado = @estado';
    req.input('estado', sql.NVarChar, estado.trim());
  }
  query += ' ORDER BY p.fecha_creacion DESC';

  const result = await req.query(query);
  const pedidos = result.recordset.map(p => ({
    id: p.id,
    numeroPedido: p.numero_pedido,
    codigoCliente: p.codigo_cliente,
    nombreCliente: p.nombre_cliente,
    direccion: p.direccion || '',
    telefono: p.telefono || '',
    correo: p.correo || '',
    subtotal: parseFloat(p.subtotal) || 0,
    iva: parseFloat(p.iva) || 0,
    total: parseFloat(p.total) || 0,
    estado: p.estado || 'PENDIENTE',
    vendedor: p.vendedor || '',
    fechaCreacion: p.fecha_creacion,
    totalProductos: p.total_productos || 0,
    totalUnidades: p.total_unidades || 0,
  }));
  return { success: true, data: pedidos, total: pedidos.length };
}

async function obtenerPedidosPorVendedor(vendedorNombre, estado) {
  if (!vendedorNombre || vendedorNombre.trim() === '') {
    return { success: false, message: 'Nombre de vendedor requerido', data: [] };
  }
  if (!tablesReady) { await ensureTables(); tablesReady = true; }
  const pool = await getOrdersPool();
  const req = pool.request();
  req.input('vendedor', sql.NVarChar, vendedorNombre.trim());

  let query = `
    SELECT p.id, p.numero_pedido, p.codigo_cliente, p.cedula_cliente, p.nombre_cliente,
           p.direccion, p.telefono, p.correo, p.subtotal, p.iva, p.total,
           p.observaciones, p.estado, p.vendedor, p.fecha_creacion, p.fecha_actualizacion,
           (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_productos,
           (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) as total_unidades
    FROM pedidos p
    WHERE p.vendedor = @vendedor
  `;

  if (estado && estado.trim() !== '') {
    query += ' AND p.estado = @estado';
    req.input('estado', sql.NVarChar, estado.trim());
  }
  query += ' ORDER BY p.fecha_creacion DESC';

  const result = await req.query(query);
  const pedidos = result.recordset.map(p => ({
    id: p.id,
    numeroPedido: p.numero_pedido,
    codigoCliente: p.codigo_cliente,
    nombreCliente: p.nombre_cliente,
    direccion: p.direccion || '',
    telefono: p.telefono || '',
    correo: p.correo || '',
    subtotal: parseFloat(p.subtotal) || 0,
    iva: parseFloat(p.iva) || 0,
    total: parseFloat(p.total) || 0,
    estado: p.estado || 'PENDIENTE',
    vendedor: p.vendedor || '',
    fechaCreacion: p.fecha_creacion,
    totalProductos: p.total_productos || 0,
    totalUnidades: p.total_unidades || 0,
  }));
  console.log(`📋 Pedidos vendedor "${vendedorNombre}": ${pedidos.length}`);
  return { success: true, data: pedidos, total: pedidos.length };
}

async function obtenerDetallePedido(numeroPedido) {
  if (!numeroPedido || numeroPedido.trim() === '') {
    return { success: false, message: 'Número de pedido requerido' };
  }
  if (!tablesReady) { await ensureTables(); tablesReady = true; }
  const pool = await getOrdersPool();
  const req = pool.request();
  req.input('numero_pedido', sql.NVarChar, numeroPedido.trim());

  const headerResult = await req.query(`
    SELECT * FROM pedidos WHERE numero_pedido = @numero_pedido
  `);

  if (headerResult.recordset.length === 0) {
    return { success: false, message: 'Pedido no encontrado' };
  }

  const p = headerResult.recordset[0];
  const req2 = pool.request();
  req2.input('pedido_id', sql.Int, p.id);
  const detalleResult = await req2.query(`
    SELECT * FROM pedidos_detalle WHERE pedido_id = @pedido_id ORDER BY id
  `);

  const pedido = {
    id: p.id,
    numeroPedido: p.numero_pedido,
    codigoCliente: p.codigo_cliente,
    cedulaCliente: p.cedula_cliente,
    nombreCliente: p.nombre_cliente,
    direccion: p.direccion || '',
    telefono: p.telefono || '',
    correo: p.correo || '',
    subtotal: parseFloat(p.subtotal) || 0,
    iva: parseFloat(p.iva) || 0,
    total: parseFloat(p.total) || 0,
    observaciones: p.observaciones || '',
    estado: p.estado || 'PENDIENTE',
    vendedor: p.vendedor || '',
    fechaCreacion: p.fecha_creacion,
  };

  const productos = detalleResult.recordset.map(d => ({
    codigo: d.codigo_producto,
    nombre: d.nombre_producto,
    textura: d.textura || '',
    cantidad: d.cantidad || 0,
    precioUnitario: parseFloat(d.precio_unitario) || 0,
    totalLinea: parseFloat(d.total_linea) || 0,
    
  }));

  return { success: true, data: { pedido, productos } };
}

module.exports = { crearPedido, obtenerPedidosPorCliente, obtenerPedidosPorVendedor, obtenerDetallePedido };
