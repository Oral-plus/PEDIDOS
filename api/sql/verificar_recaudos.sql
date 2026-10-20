/* ===========================================================================
   Como verificar que un recaudo quedo bien guardado.

   Un recaudo se reparte en TRES tablas de la base Pedidos:

     dbo.recaudos             cabecera: un renglon por recaudo. Quien cobro,
                              a que cliente, cuanta plata entro, forma de pago
                              y el numero de recibo de caja.
     dbo.recaudos_documentos  detalle: un renglon por cada factura cruzada,
                              con el abono que se le aplico. Se enlaza por
                              recaudo_id.
     dbo.evidencias_archivos  las fotos del soporte. Se enlazan por recaudo_id
                              (y tambien guardan numero_recaudo).

   La regla que debe cumplirse siempre:
     total_recaudo  = la plata que el cliente entrego
     total_aplicado = SUMA(abono) del detalle
     total_aplicado <= total_recaudo        <- si se pasa, algo esta mal
     saldo          = total_recaudo - total_aplicado
   =========================================================================== */

USE Pedidos;
GO

/* --- A. UN RECAUDO EN CONCRETO ------------------------------------------
   Cambia el numero y corre todo el bloque. Es lo que hay que mirar cuando
   un gestor dice "cobre y no aparece".
   ------------------------------------------------------------------------- */
DECLARE @recaudo NVARCHAR(60) = 'REC-20261001-5947';   -- <<< cambia esto

-- A.1 La cabecera
SELECT  r.numero_recaudo, r.fecha, r.cliente_id, r.cliente_nombre,
        r.vendedor_nombre, r.forma_pago, r.banco_pago, r.referencia_pago,
        r.total_recaudo        AS entrego_el_cliente,
        r.total_aplicado       AS se_aplico_a_facturas,
        r.saldo                AS sobrante,
        r.recibo_prefijo, r.recibo_caja, r.notas
FROM    dbo.recaudos r
WHERE   r.numero_recaudo = @recaudo;

-- A.2 Las facturas que cruzo
SELECT  d.doc_entry, d.num_factura, d.doc_num,
        d.saldo  AS saldo_de_la_factura_ese_dia,
        d.abono  AS se_le_abono,
        d.due_date
FROM    dbo.recaudos_documentos d
JOIN    dbo.recaudos r ON r.id = d.recaudo_id
WHERE   r.numero_recaudo = @recaudo;

-- A.3 El veredicto: las tres cifras tienen que cuadrar
SELECT  r.numero_recaudo,
        r.total_recaudo        AS entrego,
        r.total_aplicado       AS cabecera_dice,
        SUM(d.abono)           AS detalle_suma,
        CASE
          WHEN ABS(r.total_aplicado - SUM(d.abono)) > 1 THEN 'MAL: cabecera y detalle no cuadran'
          WHEN r.total_aplicado - r.total_recaudo  > 1 THEN 'MAL: aplica mas plata de la que entro'
          ELSE 'BIEN'
        END                    AS veredicto
FROM    dbo.recaudos r
JOIN    dbo.recaudos_documentos d ON d.recaudo_id = r.id
WHERE   r.numero_recaudo = @recaudo
GROUP BY r.numero_recaudo, r.total_recaudo, r.total_aplicado;

-- A.4 Las fotos del soporte (sin traerse el contenido)
SELECT  e.id, e.mime, e.tamano, e.ancho, e.alto, e.fecha
FROM    dbo.evidencias_archivos e
JOIN    dbo.recaudos r ON r.id = e.recaudo_id
WHERE   r.numero_recaudo = @recaudo;
GO

/* --- B. TODO LO COBRADO HOY, DE UN VISTAZO -------------------------------
   Para revisar al cierre del dia. Cualquier renglon que no diga BIEN hay que
   mirarlo.
   ------------------------------------------------------------------------- */
SELECT  r.numero_recaudo,
        CONVERT(varchar(16), r.fecha, 120) AS fecha,
        r.vendedor_nombre, r.cliente_nombre,
        r.total_recaudo AS entrego, r.total_aplicado AS aplicado, r.saldo,
        (SELECT COUNT(*) FROM dbo.recaudos_documentos WHERE recaudo_id = r.id) AS facturas,
        (SELECT COUNT(*) FROM dbo.evidencias_archivos WHERE recaudo_id = r.id) AS fotos,
        CASE WHEN r.total_aplicado - r.total_recaudo > 1
             THEN 'MAL: aplica de mas' ELSE 'BIEN' END AS veredicto
FROM    dbo.recaudos r
WHERE   CAST(r.fecha AS date) = CAST(GETDATE() AS date)
ORDER BY r.fecha DESC;
GO

/* --- C. SALUD DE TODA LA TABLA -------------------------------------------
   Las cuatro cifras de abajo tienen que dar CERO. Si alguna no da cero, el
   detalle de cual esta mal sale en el bloque D.
   ------------------------------------------------------------------------- */
SELECT
  (SELECT COUNT(*) FROM dbo.recaudos
    WHERE total_aplicado - total_recaudo > 1)                        AS aplican_de_mas,
  (SELECT COUNT(*) FROM dbo.recaudos r
    OUTER APPLY (SELECT SUM(abono) s FROM dbo.recaudos_documentos WHERE recaudo_id = r.id) d
    WHERE d.s IS NULL OR ABS(r.total_aplicado - d.s) > 1)            AS cabecera_vs_detalle,
  (SELECT COUNT(*) FROM dbo.recaudos_documentos d
    LEFT JOIN dbo.recaudos r ON r.id = d.recaudo_id
    WHERE r.id IS NULL)                                              AS detalle_huerfano,
  (SELECT COUNT(*) FROM (SELECT recibo_prefijo, recibo_caja
                         FROM dbo.recaudos WHERE recibo_caja IS NOT NULL
                         GROUP BY recibo_prefijo, recibo_caja
                         HAVING COUNT(*) > 1) x)                     AS recibos_repetidos;
GO

/* --- D. LOS QUE ESTAN MAL, UNO POR UNO ----------------------------------- */
SELECT  r.numero_recaudo, CONVERT(varchar(16), r.fecha, 120) AS fecha,
        r.cliente_id, r.cliente_nombre, r.vendedor_nombre,
        r.total_recaudo AS entrego, r.total_aplicado AS aplicado,
        r.total_aplicado - r.total_recaudo AS de_mas
FROM    dbo.recaudos r
WHERE   r.total_aplicado - r.total_recaudo > 1
ORDER BY r.fecha DESC;
GO

/* --- E. UN CLIENTE: TODO LO QUE SE LE HA COBRADO POR FACTURA -------------
   Responde "cuanto le llevo recaudado a esta factura y cuanto falta".
   ------------------------------------------------------------------------- */
DECLARE @cliente NVARCHAR(50) = 'C1030648937';   -- <<< cambia esto

SELECT  d.doc_entry, d.num_factura,
        COUNT(*)        AS veces_cobrada,
        SUM(d.abono)    AS recaudado_en_la_app,
        MAX(d.saldo)    AS debia_cuando_se_cobro
FROM    dbo.recaudos_documentos d
JOIN    dbo.recaudos r ON r.id = d.recaudo_id
WHERE   r.cliente_id = @cliente
GROUP BY d.doc_entry, d.num_factura
ORDER BY d.doc_entry;
GO
