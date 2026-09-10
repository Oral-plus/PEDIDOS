USE Pedidos;
GO

SELECT i.item_code AS se_borra, c.variante_de AS conserva, i.tamano
FROM dbo.productos_imagenes i
JOIN dbo.productos_config c ON c.item_code = i.item_code AND c.variante_de IS NOT NULL
JOIN dbo.productos_imagenes p ON p.item_code = c.variante_de;
GO

DELETE i
FROM dbo.productos_imagenes i
JOIN dbo.productos_config c ON c.item_code = i.item_code AND c.variante_de IS NOT NULL
JOIN dbo.productos_imagenes p ON p.item_code = c.variante_de;
GO
