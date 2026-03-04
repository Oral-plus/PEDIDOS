USE SkyPagos;
GO

-- Insertar tipos de transacción
INSERT INTO tipos_transaccion (codigo, nombre, descripcion, comision_porcentaje, comision_fija, monto_minimo, monto_maximo) VALUES
('ENVIO_DINERO', 'Envío de Dinero', 'Transferencia entre usuarios de SkyPagos', 0.50, 0.00, 1.00, 10000.00),
('RECARGA_SALDO', 'Recarga de Saldo', 'Recarga de saldo desde tarjeta o cuenta bancaria', 1.00, 2.00, 10.00, 5000.00),
('PAGO_SERVICIOS', 'Pago de Servicios', 'Pago de servicios básicos', 0.00, 3.00, 1.00, 2000.00),
('RETIRO_EFECTIVO', 'Retiro de Efectivo', 'Retiro en puntos autorizados', 1.50, 5.00, 50.00, 3000.00),
('RECARGA_CELULAR', 'Recarga Celular', 'Recarga de saldo celular', 0.00, 1.00, 5.00, 500.00);

-- Insertar usuarios de prueba
INSERT INTO usuarios (nombre, apellido, telefono, email, pin, documento, saldo) VALUES
('Juan Carlos', 'Pérez López', '70123456', 'juan.perez@email.com', '1234', '12345678', 1500.00),
('María Elena', 'González Ruiz', '75987654', 'maria.gonzalez@email.com', '1234', '87654321', 2300.50),
('Carlos Alberto', 'Mamani Quispe', '68456789', 'carlos.mamani@email.com', '1234', '11223344', 850.75),
('Ana Sofía', 'Rodríguez Vega', '77555888', 'ana.rodriguez@email.com', '1234', '55667788', 3200.25),
('Luis Fernando', 'Morales Castro', '69874563', 'luis.morales@email.com', '1234', '99887766', 1750.80);

-- Insertar algunas transacciones de ejemplo
INSERT INTO transacciones (codigo_transaccion, usuario_origen_id, usuario_destino_id, tipo_transaccion_id, monto, comision, monto_total, descripcion, telefono_destino, nombre_destino, estado, fecha_procesamiento) VALUES
('SKY' + FORMAT(GETDATE(), 'yyyyMMddHHmmss') + '001', 1, 2, 1, 100.00, 0.50, 100.50, 'Pago de almuerzo', '75987654', 'María Elena González', 'COMPLETADA', GETDATE()),
('SKY' + FORMAT(GETDATE(), 'yyyyMMddHHmmss') + '002', 2, 1, 1, 50.00, 0.25, 50.25, 'Devolución préstamo', '70123456', 'Juan Carlos Pérez', 'COMPLETADA', GETDATE()),
('SKY' + FORMAT(GETDATE(), 'yyyyMMddHHmmss') + '003', 3, 4, 1, 200.00, 1.00, 201.00, 'Pago de servicios', '77555888', 'Ana Sofía Rodríguez', 'COMPLETADA', GETDATE());

-- Insertar beneficiarios
INSERT INTO beneficiarios (usuario_id, nombre, telefono, alias) VALUES
(1, 'María Elena González', '75987654', 'María'),
(1, 'Carlos Alberto Mamani', '68456789', 'Carlos'),
(2, 'Juan Carlos Pérez', '70123456', 'Juan'),
(2, 'Ana Sofía Rodríguez', '77555888', 'Ana'),
(3, 'Luis Fernando Morales', '69874563', 'Luis');

-- Insertar notificaciones de ejemplo
INSERT INTO notificaciones (usuario_id, titulo, mensaje, tipo) VALUES
(1, 'Bienvenido a SkyPagos', 'Tu cuenta ha sido creada exitosamente', 'SUCCESS'),
(1, 'Transacción completada', 'Has enviado Bs. 100.00 a María Elena González', 'INFO'),
(2, 'Dinero recibido', 'Has recibido Bs. 100.00 de Juan Carlos Pérez', 'SUCCESS');

PRINT 'Datos de prueba insertados exitosamente';
