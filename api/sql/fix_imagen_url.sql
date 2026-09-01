
USE Pedidos;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('pedidos_detalle') 
    AND name = 'imagen_url'
)
BEGIN
    ALTER TABLE pedidos_detalle DROP COLUMN imagen_url;
    PRINT 'Columna imagen_url eliminada de pedidos_detalle.';
END
ELSE
    PRINT 'La columna imagen_url no existe en pedidos_detalle (correcto).';

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

PRINT 'Correccion aplicada. Reinicia el servidor API.';
