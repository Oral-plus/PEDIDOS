-- Crear base de datos SkyPagos si no existe
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'SkyPagos')
BEGIN
    CREATE DATABASE SkyPagos;
END
GO

USE SkyPagos;
GO

-- Tabla de usuarios
CREATE TABLE usuarios (
    id INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(100) NOT NULL,
    apellido NVARCHAR(100) NOT NULL,
    telefono NVARCHAR(20) UNIQUE NOT NULL,
    email NVARCHAR(150) UNIQUE,
    pin NVARCHAR(255) NOT NULL, -- PIN encriptado
    documento NVARCHAR(20) UNIQUE NOT NULL,
    tipo_documento NVARCHAR(10) NOT NULL DEFAULT 'CI',
    fecha_nacimiento DATE,
    estado NVARCHAR(20) DEFAULT 'ACTIVO', -- ACTIVO, INACTIVO, BLOQUEADO
    saldo DECIMAL(15,2) DEFAULT 0.00,
    limite_diario DECIMAL(15,2) DEFAULT 5000.00,
    limite_mensual DECIMAL(15,2) DEFAULT 50000.00,
    foto_perfil NVARCHAR(500),
    fecha_registro DATETIME DEFAULT GETDATE(),
    fecha_actualizacion DATETIME DEFAULT GETDATE()
);

-- Tabla de tipos de transacción
CREATE TABLE tipos_transaccion (
    id INT IDENTITY(1,1) PRIMARY KEY,
    codigo NVARCHAR(20) UNIQUE NOT NULL,
    nombre NVARCHAR(100) NOT NULL,
    descripcion NVARCHAR(255),
    comision_porcentaje DECIMAL(5,2) DEFAULT 0.00,
    comision_fija DECIMAL(10,2) DEFAULT 0.00,
    monto_minimo DECIMAL(15,2) DEFAULT 1.00,
    monto_maximo DECIMAL(15,2) DEFAULT 10000.00,
    estado NVARCHAR(20) DEFAULT 'ACTIVO'
);

-- Tabla de transacciones
CREATE TABLE transacciones (
    id INT IDENTITY(1,1) PRIMARY KEY,
    codigo_transaccion NVARCHAR(50) UNIQUE NOT NULL,
    usuario_origen_id INT NOT NULL,
    usuario_destino_id INT,
    tipo_transaccion_id INT NOT NULL,
    monto DECIMAL(15,2) NOT NULL,
    comision DECIMAL(15,2) DEFAULT 0.00,
    monto_total DECIMAL(15,2) NOT NULL,
    descripcion NVARCHAR(255),
    referencia NVARCHAR(100),
    telefono_destino NVARCHAR(20),
    nombre_destino NVARCHAR(200),
    estado NVARCHAR(20) DEFAULT 'PENDIENTE', -- PENDIENTE, COMPLETADA, FALLIDA, CANCELADA
    fecha_transaccion DATETIME DEFAULT GETDATE(),
    fecha_procesamiento DATETIME,
    ip_origen NVARCHAR(45),
    dispositivo NVARCHAR(100),
    FOREIGN KEY (usuario_origen_id) REFERENCES usuarios(id),
    FOREIGN KEY (usuario_destino_id) REFERENCES usuarios(id),
    FOREIGN KEY (tipo_transaccion_id) REFERENCES tipos_transaccion(id)
);

-- Tabla de beneficiarios
CREATE TABLE beneficiarios (
    id INT IDENTITY(1,1) PRIMARY KEY,
    usuario_id INT NOT NULL,
    nombre NVARCHAR(100) NOT NULL,
    telefono NVARCHAR(20) NOT NULL,
    alias NVARCHAR(50),
    fecha_agregado DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Tabla de sesiones
CREATE TABLE sesiones (
    id INT IDENTITY(1,1) PRIMARY KEY,
    usuario_id INT NOT NULL,
    token NVARCHAR(500) NOT NULL,
    dispositivo NVARCHAR(100),
    ip_address NVARCHAR(45),
    fecha_inicio DATETIME DEFAULT GETDATE(),
    fecha_expiracion DATETIME NOT NULL,
    activa BIT DEFAULT 1,
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Tabla de notificaciones
CREATE TABLE notificaciones (
    id INT IDENTITY(1,1) PRIMARY KEY,
    usuario_id INT NOT NULL,
    titulo NVARCHAR(100) NOT NULL,
    mensaje NVARCHAR(500) NOT NULL,
    tipo NVARCHAR(50) DEFAULT 'INFO', -- INFO, SUCCESS, WARNING, ERROR
    leida BIT DEFAULT 0,
    fecha_creacion DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Índices para optimización
CREATE INDEX IX_transacciones_usuario_origen ON transacciones(usuario_origen_id);
CREATE INDEX IX_transacciones_fecha ON transacciones(fecha_transaccion);
CREATE INDEX IX_transacciones_estado ON transacciones(estado);
CREATE INDEX IX_usuarios_telefono ON usuarios(telefono);
CREATE INDEX IX_sesiones_token ON sesiones(token);

PRINT 'Base de datos SkyPagos creada exitosamente';
