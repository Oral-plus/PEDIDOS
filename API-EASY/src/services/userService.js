const { sql, getDbPool, getSapPool } = require('../config/database');

async function obtenerNitUsuario(usuario_id) {
  const pool = await getDbPool();

  let result;
  try {
    result = await pool
      .request()
      .input('id', sql.Int, usuario_id)
      .query('SELECT nit, nombre, tipo_usuario FROM usuarios_ruta WHERE id = @id');
  } catch {
    result = await pool
      .request()
      .input('id', sql.Int, usuario_id)
      .query('SELECT nit, nombre FROM usuarios_ruta WHERE id = @id');
  }

  if (result.recordset.length === 0) {
    return { nit: null, tipo_usuario: 'OSLP', nombre: null };
  }

  const row = result.recordset[0];
  return {
    nit: row.nit,
    tipo_usuario: row.tipo_usuario || 'OSLP',
    nombre: row.nombre,
  };
}

async function sincronizarNombreSAP(usuario_id) {
  const datosUsuario = await obtenerNitUsuario(usuario_id);
  if (!datosUsuario.nit) {
    return { sincronizado: false, message: 'El usuario no tiene NIT asignado' };
  }

  const sapPool = await getSapPool();
  const dbPool = await getDbPool();

  let sqlQuery;
  if (datosUsuario.tipo_usuario === 'COACH') {
    sqlQuery = `
      SELECT T0.[Name] AS Nombre FROM [dbo].[@COACH] T0 WHERE T0.[Code] = @nit
      UNION ALL
      SELECT T1.SlpName AS Nombre FROM OCRD T0
      INNER JOIN OSLP T1 ON T0.SlpCode = T1.SlpCode
      WHERE T0.validFor = 'Y' AND T1.SlpCode = @nit
    `;
  } else {
    sqlQuery = `
      SELECT T1.SlpName AS Nombre FROM OCRD T0
      INNER JOIN OSLP T1 ON T0.SlpCode = T1.SlpCode
      WHERE T0.validFor = 'Y' AND T1.SlpCode = @nit
      UNION ALL
      SELECT T0.[Name] AS Nombre FROM [dbo].[@COACH] T0
      INNER JOIN OCRD T1 ON T0.[Code] = T1.[U_COACH]
      INNER JOIN OSLP T2 ON T1.[SlpCode] = T2.[SlpCode]
      WHERE T1.validFor = 'Y' AND T2.SlpCode = @nit
    `;
  }

  const sapResult = await sapPool
    .request()
    .input('nit', sql.NVarChar, datosUsuario.nit)
    .query(sqlQuery);

  if (sapResult.recordset.length === 0) {
    return { sincronizado: false, message: 'No se encontró el nombre en SAP' };
  }

  const nombreSap = sapResult.recordset[0].Nombre;

  if (nombreSap !== datosUsuario.nombre) {
    await dbPool
      .request()
      .input('nombre', sql.NVarChar, nombreSap)
      .input('id', sql.Int, usuario_id)
      .query('UPDATE usuarios_ruta SET nombre = @nombre WHERE id = @id');

    return {
      sincronizado: true,
      nombre_anterior: datosUsuario.nombre,
      nombre_nuevo: nombreSap,
      message: 'Nombre actualizado desde SAP',
    };
  }

  return { sincronizado: false, message: 'El nombre ya está actualizado' };
}

async function obtenerOSLPAsociadosACoach(coachCode) {
  const sapPool = await getSapPool();

  const result = await sapPool
    .request()
    .input('code', sql.NVarChar, coachCode)
    .query(`
      SELECT DISTINCT T1.[SlpCode], T1.[SlpName]
      FROM OCRD T0
      INNER JOIN [dbo].[@COACH] T2 ON T0.[U_COACH] = T2.[Code]
      INNER JOIN OSLP T1 ON T0.[SlpCode] = T1.[SlpCode]
      WHERE T0.[validFor] = 'Y' AND T2.[Code] = @code
      ORDER BY T1.[SlpName]
    `);

  return result.recordset.map((r) => ({
    SlpCode: r.SlpCode,
    SlpName: r.SlpName,
  }));
}

async function obtenerPerfilUsuario(usuario_id) {
  const datos = await obtenerNitUsuario(usuario_id);
  const esAdmin = usuario_id === 1;

  let oslpAsociados = [];
  if (datos.tipo_usuario === 'COACH' && datos.nit) {
    oslpAsociados = await obtenerOSLPAsociadosACoach(datos.nit);
  }

  return {
    usuario_id,
    nit: datos.nit,
    nombre: datos.nombre,
    tipo_usuario: datos.tipo_usuario,
    es_admin: esAdmin,
    oslp_asociados: oslpAsociados,
  };
}

module.exports = {
  obtenerNitUsuario,
  sincronizarNombreSAP,
  obtenerOSLPAsociadosACoach,
  obtenerPerfilUsuario,
};
