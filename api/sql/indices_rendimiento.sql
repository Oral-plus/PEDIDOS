
USE Pedidos;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pedidos_vendedor_fecha' AND object_id = OBJECT_ID('dbo.pedidos'))
  CREATE INDEX IX_pedidos_vendedor_fecha ON dbo.pedidos(vendedor, fecha_creacion DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pedidos_cliente_fecha' AND object_id = OBJECT_ID('dbo.pedidos'))
  CREATE INDEX IX_pedidos_cliente_fecha ON dbo.pedidos(codigo_cliente, fecha_creacion DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_historial_pedido_fecha' AND object_id = OBJECT_ID('dbo.pedidos_historial'))
  CREATE INDEX IX_historial_pedido_fecha ON dbo.pedidos_historial(pedido_id, fecha DESC);
IF OBJECT_ID('dbo.recaudos_documentos') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_recaudos_doc_recaudo' AND object_id = OBJECT_ID('dbo.recaudos_documentos'))
  CREATE INDEX IX_recaudos_doc_recaudo ON dbo.recaudos_documentos(recaudo_id);
IF OBJECT_ID('dbo.recaudos') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_recaudos_cliente_fecha' AND object_id = OBJECT_ID('dbo.recaudos'))
  CREATE INDEX IX_recaudos_cliente_fecha ON dbo.recaudos(cliente_id, fecha DESC);
GO

USE Ruta;
GO

IF OBJECT_ID('dbo.visitas_clientes') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_visitas_cliente_fecha' AND object_id = OBJECT_ID('dbo.visitas_clientes'))
  CREATE INDEX IX_visitas_cliente_fecha ON dbo.visitas_clientes(cliente_id, fecha DESC);
IF OBJECT_ID('dbo.visitas_clientes') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_visitas_vendedor_fecha' AND object_id = OBJECT_ID('dbo.visitas_clientes'))
  CREATE INDEX IX_visitas_vendedor_fecha ON dbo.visitas_clientes(vendedor_id, fecha DESC);
IF OBJECT_ID('dbo.encuestas_visitas') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_encuestas_cliente' AND object_id = OBJECT_ID('dbo.encuestas_visitas'))
  CREATE INDEX IX_encuestas_cliente ON dbo.encuestas_visitas(cliente_id, id DESC);
IF OBJECT_ID('dbo.rutas') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rutas_vendedor_fecha' AND object_id = OBJECT_ID('dbo.rutas'))
  CREATE INDEX IX_rutas_vendedor_fecha ON dbo.rutas(vendedor_id, fecha_programada DESC);
IF OBJECT_ID('dbo.rutas') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rutas_cliente_fecha' AND object_id = OBJECT_ID('dbo.rutas'))
  CREATE INDEX IX_rutas_cliente_fecha ON dbo.rutas(cliente_id, fecha_programada DESC);
GO
