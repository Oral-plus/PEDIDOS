const { sql, getDbPool } = require('../config/database');
const { obtenerOSLPAsociadosACoach } = require('./userService');

async function obtenerUsuarioIdsParaCoach(pool, usuario_id, oslpAsociados) {
  const ids = [usuario_id];
  for (const oslp of oslpAsociados) {
    const result = await pool
      .request()
      .input('nit', sql.NVarChar, oslp.SlpCode)
      .query('SELECT id FROM usuarios_ruta WHERE nit = @nit');
    for (const row of result.recordset) {
      ids.push(row.id);
    }
  }
  return ids;
}

async function obtenerEstadisticas(usuario_id, tipoUsuario, nit) {
  const pool = await getDbPool();
  const esAdmin = usuario_id === 1;

  let oslpAsociados = [];
  if (tipoUsuario === 'COACH' && nit) {
    oslpAsociados = await obtenerOSLPAsociadosACoach(nit);
  }

  const estadisticas = {
    rutas_activas: 0,
    rutas_completadas: 0,
    tareas_pendientes: 0,
    tareas_completadas: 0,
  };

  let usuarioIds = [usuario_id];
  if (tipoUsuario === 'COACH' && oslpAsociados.length > 0) {
    usuarioIds = await obtenerUsuarioIdsParaCoach(pool, usuario_id, oslpAsociados);
  }

  if (tipoUsuario === 'COACH' && usuarioIds.length > 1) {
    const placeholders = usuarioIds.map((_, i) => `@uid${i}`).join(',');
    const req = pool.request();
    usuarioIds.forEach((id, i) => req.input(`uid${i}`, sql.Int, id));

    const activas = await req.query(`
      SELECT COUNT(*) as total FROM Ruta.dbo.rutas
      WHERE cliente_id IS NOT NULL AND cliente_id != ''
      AND DATEDIFF(day, fecha_creacion, GETDATE()) < 15
      AND usuario_id IN (${placeholders})
    `);
    estadisticas.rutas_activas = activas.recordset[0].total;

    const req2 = pool.request();
    usuarioIds.forEach((id, i) => req2.input(`uid${i}`, sql.Int, id));
    const completadas = await req2.query(`
      SELECT COUNT(*) as total FROM Ruta.dbo.rutas
      WHERE estado = 'completada' AND usuario_id IN (${placeholders})
    `);
    estadisticas.rutas_completadas = completadas.recordset[0].total;
  } else {
    const activas = await pool
      .request()
      .input('uid', sql.Int, usuario_id)
      .input('admin', sql.Int, esAdmin ? 1 : 0)
      .query(`
        SELECT COUNT(*) as total FROM Ruta.dbo.rutas
        WHERE cliente_id IS NOT NULL AND cliente_id != ''
        AND DATEDIFF(day, fecha_creacion, GETDATE()) < 15
        AND (usuario_id = @uid OR @admin = 1)
      `);
    estadisticas.rutas_activas = activas.recordset[0].total;

    const completadas = await pool
      .request()
      .input('uid', sql.Int, usuario_id)
      .input('admin', sql.Int, esAdmin ? 1 : 0)
      .query(`
        SELECT COUNT(*) as total FROM Ruta.dbo.rutas
        WHERE estado = 'completada' AND (usuario_id = @uid OR @admin = 1)
      `);
    estadisticas.rutas_completadas = completadas.recordset[0].total;
  }

  const tareasPend = await pool
    .request()
    .input('uid', sql.Int, usuario_id)
    .input('admin', sql.Int, esAdmin ? 1 : 0)
    .query(`
      SELECT COUNT(*) as total FROM Ruta.dbo.tareas t
      INNER JOIN Ruta.dbo.rutas r ON t.ruta_id = r.id
      WHERE t.estado = 'pendiente' AND (r.usuario_id = @uid OR @admin = 1)
    `);
  estadisticas.tareas_pendientes = tareasPend.recordset[0].total;

  const tareasComp = await pool
    .request()
    .input('uid', sql.Int, usuario_id)
    .input('admin', sql.Int, esAdmin ? 1 : 0)
    .query(`
      SELECT COUNT(*) as total FROM Ruta.dbo.tareas t
      INNER JOIN Ruta.dbo.rutas r ON t.ruta_id = r.id
      WHERE t.estado = 'completada' AND (r.usuario_id = @uid OR @admin = 1)
    `);
  estadisticas.tareas_completadas = tareasComp.recordset[0].total;

  return estadisticas;
}

async function obtenerRutasActivas(usuario_id, tipoUsuario, nit) {
  const pool = await getDbPool();
  const esAdmin = usuario_id === 1;

  let oslpAsociados = [];
  if (tipoUsuario === 'COACH' && nit) {
    oslpAsociados = await obtenerOSLPAsociadosACoach(nit);
  }

  let usuarioIds = [usuario_id];
  if (tipoUsuario === 'COACH' && oslpAsociados.length > 0) {
    usuarioIds = await obtenerUsuarioIdsParaCoach(pool, usuario_id, oslpAsociados);
  }

  let result;
  if (tipoUsuario === 'COACH' && usuarioIds.length > 1) {
    const placeholders = usuarioIds.map((_, i) => `@uid${i}`).join(',');
    const req = pool.request();
    usuarioIds.forEach((id, i) => req.input(`uid${i}`, sql.Int, id));

    result = await req.query(`
      SELECT r.id, r.cliente_codigo, r.cliente_nombre, r.descripcion, r.estado,
             r.fecha_creacion, r.usuario_id, u.nombre as usuario_nombre, u.nit as usuario_nit
      FROM Ruta.dbo.rutas r
      INNER JOIN usuarios_ruta u ON r.usuario_id = u.id
      WHERE r.cliente_id IS NOT NULL AND r.cliente_id != ''
      AND DATEDIFF(day, r.fecha_creacion, GETDATE()) < 15
      AND r.usuario_id IN (${placeholders})
      ORDER BY u.nombre, r.fecha_creacion DESC
    `);
  } else {
    result = await pool
      .request()
      .input('uid', sql.Int, usuario_id)
      .input('admin', sql.Int, esAdmin ? 1 : 0)
      .query(`
        SELECT r.id, r.cliente_codigo, r.cliente_nombre, r.descripcion, r.estado,
               r.fecha_creacion, r.usuario_id, u.nombre as usuario_nombre, u.nit as usuario_nit
        FROM Ruta.dbo.rutas r
        LEFT JOIN usuarios_ruta u ON r.usuario_id = u.id
        WHERE r.cliente_id IS NOT NULL AND r.cliente_id != ''
        AND DATEDIFF(day, r.fecha_creacion, GETDATE()) < 15
        AND (r.usuario_id = @uid OR @admin = 1)
        ORDER BY r.fecha_creacion DESC
      `);
  }

  const rutas = result.recordset;

  if (tipoUsuario === 'COACH') {
    const agrupadas = {};
    for (const ruta of rutas) {
      const vendedor = ruta.usuario_nombre || 'Sin asignar';
      if (!agrupadas[vendedor]) {
        agrupadas[vendedor] = {
          vendedor_nombre: vendedor,
          vendedor_nit: ruta.usuario_nit || '',
          rutas: [],
        };
      }
      agrupadas[vendedor].rutas.push(ruta);
    }
    return { rutas, agrupadas_por_vendedor: Object.values(agrupadas) };
  }

  return { rutas, agrupadas_por_vendedor: null };
}

async function actualizarEstadoRuta(ruta_id, nuevoEstado) {
  const pool = await getDbPool();
  await pool
    .request()
    .input('estado', sql.NVarChar, nuevoEstado)
    .input('id', sql.Int, ruta_id)
    .query('UPDATE Ruta.dbo.rutas SET estado = @estado WHERE id = @id');
  return true;
}

async function crearNuevaRuta(clienteCodigo, clienteNombre, usuario_id, descripcion) {
  const pool = await getDbPool();

  await pool
    .request()
    .input('cliente_codigo', sql.NVarChar, clienteCodigo)
    .input('cliente_nombre', sql.NVarChar, clienteNombre)
    .input('usuario_id', sql.Int, usuario_id)
    .input('descripcion', sql.NVarChar, descripcion || '')
    .query(`
      INSERT INTO Ruta.dbo.rutas (cliente_codigo, cliente_nombre, usuario_id, descripcion, estado, fecha_creacion)
      VALUES (@cliente_codigo, @cliente_nombre, @usuario_id, @descripcion, 'activa', GETDATE())
    `);

  const idResult = await pool.request().query('SELECT SCOPE_IDENTITY() as ruta_id');
  return idResult.recordset[0].ruta_id;
}

async function obtenerTareasPendientes(usuario_id) {
  const pool = await getDbPool();
  const esAdmin = usuario_id === 1;

  const result = await pool
    .request()
    .input('uid', sql.Int, usuario_id)
    .input('admin', sql.Int, esAdmin ? 1 : 0)
    .query(`
      SELECT t.id, t.titulo, t.descripcion, t.prioridad, t.estado, t.fecha_creacion, r.cliente_nombre
      FROM Ruta.dbo.tareas t
      INNER JOIN Ruta.dbo.rutas r ON t.ruta_id = r.id
      WHERE t.estado = 'pendiente' AND (r.usuario_id = @uid OR @admin = 1)
      ORDER BY
        CASE t.prioridad WHEN 'alta' THEN 1 WHEN 'media' THEN 2 WHEN 'baja' THEN 3 END,
        t.fecha_creacion DESC
    `);

  return result.recordset;
}

async function actualizarEstadoTarea(tarea_id, nuevoEstado) {
  const pool = await getDbPool();
  await pool
    .request()
    .input('estado', sql.NVarChar, nuevoEstado)
    .input('id', sql.Int, tarea_id)
    .query('UPDATE Ruta.dbo.tareas SET estado = @estado, fecha_actualizacion = GETDATE() WHERE id = @id');
  return true;
}

module.exports = {
  obtenerEstadisticas,
  obtenerRutasActivas,
  actualizarEstadoRuta,
  crearNuevaRuta,
  obtenerTareasPendientes,
  actualizarEstadoTarea,
};
