/* ===========================================================================
   Recaudos que aplicaron a la cartera mas plata de la que el cliente entrego.

   Que paso: al cruzar una factura, la app ponia como abono el SALDO COMPLETO
   de la factura, sin mirar cuanto dinero habia recibido el gestor. Si el
   cliente abonaba 200.000 a una factura de 498.828, quedaba registrado un
   abono de 498.828: la factura se marcaba como cobrada entera y dejaba de
   salir para el siguiente cobro.

   Ya esta corregido en la app y en el backend (modules/cartera.js ->
   revisarCruce). Este script es solo para los registros que quedaron mal.

   NO SE EJECUTA SOLO. Revisar el paso 1, decidir, y recien ahi el paso 3.
   =========================================================================== */

USE Pedidos;
GO

/* --- 1. QUE HAY. Mirar esto antes de tocar nada. ------------------------- */
SELECT  r.id,
        r.numero_recaudo,
        r.fecha,
        r.cliente_id,
        r.cliente_nombre,
        r.vendedor_nombre,
        r.total_recaudo                        AS recibido,
        r.total_aplicado                       AS aplicado,
        r.total_aplicado - r.total_recaudo     AS exceso,
        d.doc_entry,
        d.num_factura,
        d.abono                                AS abono_registrado
FROM    dbo.recaudos r
JOIN    dbo.recaudos_documentos d ON d.recaudo_id = r.id
WHERE   r.total_aplicado - r.total_recaudo > 1
ORDER BY r.fecha DESC;
GO

/* --- 2. COPIA DE SEGURIDAD. Sin esto no se corrige nada. ----------------- */
SELECT * INTO dbo.recaudos_resp_20261019
FROM   dbo.recaudos
WHERE  total_aplicado - total_recaudo > 1;

SELECT d.* INTO dbo.recaudos_documentos_resp_20261019
FROM   dbo.recaudos_documentos d
JOIN   dbo.recaudos r ON r.id = d.recaudo_id
WHERE  r.total_aplicado - r.total_recaudo > 1;
GO

/* --- 3. LA CORRECCION ----------------------------------------------------
   Regla: el abono baja a lo que de verdad se recibio, repartido entre los
   documentos del recaudo en la misma proporcion en que se habia aplicado.
   Hoy todos los recaudos afectados tienen un solo documento, asi que en la
   practica el abono queda igual a total_recaudo.

   Dentro de una transaccion: revisar el SELECT del paso 4 ANTES del COMMIT.
   ------------------------------------------------------------------------- */
BEGIN TRANSACTION;

UPDATE  d
SET     d.abono = CAST(ROUND(d.abono * (r.total_recaudo / NULLIF(s.suma, 0)), 2) AS DECIMAL(18,2))
FROM    dbo.recaudos_documentos d
JOIN    dbo.recaudos r ON r.id = d.recaudo_id
CROSS APPLY (SELECT SUM(x.abono) AS suma
             FROM   dbo.recaudos_documentos x
             WHERE  x.recaudo_id = r.id) s
WHERE   r.total_aplicado - r.total_recaudo > 1
  AND   s.suma > 0;

UPDATE  r
SET     r.total_aplicado = s.suma,
        r.saldo          = r.total_recaudo - s.suma
FROM    dbo.recaudos r
CROSS APPLY (SELECT SUM(x.abono) AS suma
             FROM   dbo.recaudos_documentos x
             WHERE  x.recaudo_id = r.id) s
WHERE   r.id IN (SELECT id FROM dbo.recaudos_resp_20261019);

/* --- 4. COMPROBAR ANTES DEL COMMIT --------------------------------------- */
SELECT  r.numero_recaudo, r.cliente_id, r.cliente_nombre,
        v.total_recaudo AS recibido,
        v.total_aplicado AS aplicado_antes,
        r.total_aplicado AS aplicado_ahora,
        r.saldo
FROM    dbo.recaudos r
JOIN    dbo.recaudos_resp_20261019 v ON v.id = r.id
ORDER BY r.fecha DESC;

-- Debe dar 0:
SELECT COUNT(*) AS siguen_excedidos
FROM   dbo.recaudos
WHERE  total_aplicado - total_recaudo > 1;

-- COMMIT TRANSACTION;    <- descomentar solo si lo de arriba esta bien
-- ROLLBACK TRANSACTION;  <- si algo no cuadra
GO

/* --- 5. DESPUES ----------------------------------------------------------
   El neteo de cartera se recalcula solo en la siguiente consulta: las 19
   facturas que estaban escondidas vuelven a salir con el saldo que de verdad
   falta por cobrar. No hay que tocar SAP: alli estas facturas nunca se
   movieron, siguen con su saldo real.

   Las tablas _resp_20261019 se pueden borrar cuando se confirme en campo.
   ------------------------------------------------------------------------- */
