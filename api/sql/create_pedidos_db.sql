-- ============================================================
-- SCRIPT SQL - BASE DE DATOS INDEPENDIENTE: Pedidos
-- Base de datos completamente separada de SkyPagos
-- Para almacenar todos los pedidos de ORAL-PLUS
-- ============================================================

-- Crear la base de datos Pedidos si no existe
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'Pedidos')
BEGIN
    CREATE DATABASE Pedidos;
    PRINT 'Base de datos [Pedidos] creada correctamente.';
END
ELSE
    PRINT 'Base de datos [Pedidos] ya existe.';
GO

USE Pedidos;
GO

-- ============================================================
-- TABLA: pedidos (Encabezado del pedido)
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'pedidos')
BEGIN
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
    );

    CREATE INDEX IX_pedidos_codigo_cliente ON pedidos(codigo_cliente);
    CREATE INDEX IX_pedidos_cedula ON pedidos(cedula_cliente);
    CREATE INDEX IX_pedidos_fecha ON pedidos(fecha_creacion DESC);
    CREATE INDEX IX_pedidos_estado ON pedidos(estado);
    CREATE INDEX IX_pedidos_numero ON pedidos(numero_pedido);

    PRINT 'Tabla [pedidos] creada correctamente.';
END
ELSE
    PRINT 'Tabla [pedidos] ya existe.';
GO

-- ============================================================
-- TABLA: pedidos_detalle (Productos de cada pedido)
-- ============================================================
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
        CONSTRAINT FK_detalle_pedido FOREIGN KEY (pedido_id) 
            REFERENCES pedidos(id) ON DELETE CASCADE
    );

    CREATE INDEX IX_detalle_pedido ON pedidos_detalle(pedido_id);
    CREATE INDEX IX_detalle_codigo ON pedidos_detalle(codigo_producto);

    PRINT 'Tabla [pedidos_detalle] creada correctamente.';
END
ELSE
    PRINT 'Tabla [pedidos_detalle] ya existe.';
GO

-- ============================================================
-- TABLA: pedidos_historial (Log de cambios de estado)
-- ============================================================
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
        CONSTRAINT FK_historial_pedido FOREIGN KEY (pedido_id)
            REFERENCES pedidos(id) ON DELETE CASCADE
    );

    CREATE INDEX IX_historial_pedido ON pedidos_historial(pedido_id);
    CREATE INDEX IX_historial_fecha ON pedidos_historial(fecha DESC);

    PRINT 'Tabla [pedidos_historial] creada correctamente.';
END
ELSE
    PRINT 'Tabla [pedidos_historial] ya existe.';
GO

-- ============================================================
-- TABLA: direcciones_entrega (Direcciones registradas por pedido)
-- ============================================================
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
        CONSTRAINT FK_direccion_pedido FOREIGN KEY (pedido_id)
            REFERENCES pedidos(id) ON DELETE SET NULL
    );

    CREATE INDEX IX_direccion_cliente ON direcciones_entrega(codigo_cliente);
    CREATE INDEX IX_direccion_fecha ON direcciones_entrega(fecha_registro DESC);

    PRINT 'Tabla [direcciones_entrega] creada correctamente.';
END
ELSE
    PRINT 'Tabla [direcciones_entrega] ya existe.';
GO

-- ============================================================
-- VISTA: Resumen de pedidos
-- ============================================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'v_pedidos_resumen')
    DROP VIEW v_pedidos_resumen;
GO

CREATE VIEW v_pedidos_resumen AS
SELECT 
    p.id,
    p.numero_pedido,
    p.codigo_cliente,
    p.cedula_cliente,
    p.nombre_cliente,
    p.correo,
    p.telefono,
    p.subtotal,
    p.iva,
    p.total,
    p.estado,
    p.vendedor,
    p.fecha_creacion,
    p.sincronizado_sap,
    (SELECT COUNT(*) FROM pedidos_detalle d WHERE d.pedido_id = p.id) AS cantidad_productos,
    (SELECT SUM(d.cantidad) FROM pedidos_detalle d WHERE d.pedido_id = p.id) AS total_unidades
FROM pedidos p;
GO

-- ============================================================
-- VISTA: Detalle completo de pedidos
-- ============================================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'v_pedidos_detalle_completo')
    DROP VIEW v_pedidos_detalle_completo;
GO

CREATE VIEW v_pedidos_detalle_completo AS
SELECT
    p.numero_pedido,
    p.codigo_cliente,
    p.nombre_cliente,
    p.estado,
    p.fecha_creacion,
    p.total AS total_pedido,
    d.codigo_producto,
    d.nombre_producto,
    d.textura,
    d.cantidad,
    d.precio_unitario,
    d.total_linea
FROM pedidos p
INNER JOIN pedidos_detalle d ON d.pedido_id = p.id;
GO

PRINT '====================================================';
PRINT 'Base de datos [Pedidos] configurada correctamente.';
PRINT '====================================================';
GO
