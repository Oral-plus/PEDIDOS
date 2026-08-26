-- Usuario SQL dedicado para la API de pedidos, con permisos mínimos.
-- Ejecutar en SSMS como administrador del servidor 192.168.2.244.
-- Reemplazar <contraseña> por una contraseña fuerte y luego poner en api/.env:
--   DB_USER=pedidos_app
--   DB_PASSWORD=<contraseña>
-- Con esto el .env que recibe el proveedor deja de llevar la cuenta sa.

USE master;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'pedidos_app')
  CREATE LOGIN [pedidos_app] WITH PASSWORD = '<contraseña>', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [Pedidos];
GO

-- SkyPagos: usuarios y autenticación (lectura y escritura)
USE [SkyPagos];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'pedidos_app') CREATE USER [pedidos_app] FOR LOGIN [pedidos_app];
ALTER ROLE db_datareader ADD MEMBER [pedidos_app];
ALTER ROLE db_datawriter ADD MEMBER [pedidos_app];
GO

-- Pedidos: la API crea y modifica sus propias tablas
USE [Pedidos];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'pedidos_app') CREATE USER [pedidos_app] FOR LOGIN [pedidos_app];
ALTER ROLE db_datareader ADD MEMBER [pedidos_app];
ALTER ROLE db_datawriter ADD MEMBER [pedidos_app];
ALTER ROLE db_ddladmin ADD MEMBER [pedidos_app];
GO

-- Ruta: rutas, visitas, encuestas (crea tablas y columnas)
USE [Ruta];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'pedidos_app') CREATE USER [pedidos_app] FOR LOGIN [pedidos_app];
ALTER ROLE db_datareader ADD MEMBER [pedidos_app];
ALTER ROLE db_datawriter ADD MEMBER [pedidos_app];
ALTER ROLE db_ddladmin ADD MEMBER [pedidos_app];
GO

-- SAP: solo lectura (la API nunca escribe en SAP)
USE [RBOSKY3];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'pedidos_app') CREATE USER [pedidos_app] FOR LOGIN [pedidos_app];
ALTER ROLE db_datareader ADD MEMBER [pedidos_app];
GO
