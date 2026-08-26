# Solicitud: actualizar un endpoint de la API SAP (pedidos.oral-plus.com)

**De:** Oral-Plus (sistemas@oral-plus.com)
**Para:** proveedor que administra la API SAP en `pedidos.oral-plus.com`

## Qué cambia

Solo el endpoint `GET /api/obtener_precios_sap` del servicio Node.js de la API
SAP (archivo `Datos.js`, contenedor del puerto 3006). Ningún otro endpoint se
toca.

Hoy la app móvil hace tres llamadas antes de pedir los precios de un cliente
(`/api/test`, `/api/obtener_lista_precios_cliente`, `/api/obtener_listas_precios`)
solo para saber qué lista de precios usar. Con el cambio, el propio endpoint
toma la lista del cliente en SAP (`OCRD.ListNum`) dentro de la misma consulta
SQL y la devuelve en la respuesta.

## Compatibilidad

- Si la petición trae `lista_precios`, se respeta tal cual (comportamiento
  actual). Las integraciones existentes no cambian.
- Si no la trae, se usa la lista del cliente indicado en `cliente`; si el
  cliente no existe o no tiene lista, se usa la 1 (igual que hoy).
- La respuesta conserva todos los campos actuales y agrega tres:
  `lista_precios_usada` (ya existía), `nombre_lista_precios` y
  `lista_resuelta: true`. La app usa `lista_resuelta` para saber que el
  servidor ya tiene el cambio; mientras no esté desplegado, la app sigue
  funcionando con el método anterior.

## Cómo aplicarlo

Reemplazar el manejador de `app.get("/api/obtener_precios_sap", ...)` por el
que va en el `Datos.js` adjunto (líneas del bloque `try` hasta `res.json`).
El resto del archivo adjunto es idéntico a la versión que ya tienen, salvo ese
bloque. Reconstruir el contenedor y reiniciarlo.

## Cómo verificar

Con un cliente que tenga una lista de precios distinta de la 1:

```
curl "https://pedidos.oral-plus.com/api/obtener_precios_sap?codigos=50360251&cliente=C12345678"
```

La respuesta debe incluir `"lista_resuelta": true`, `"lista_precios_usada"`
con la lista real del cliente y `"nombre_lista_precios"` con su nombre en SAP.
Enviando además `&lista_precios=1` debe responder con la lista 1, como antes.
