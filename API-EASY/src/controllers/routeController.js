const routeService = require('../services/routeService');
const userService = require('../services/userService');

async function getEstadisticas(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    const estadisticas = await routeService.obtenerEstadisticas(
      req.user.usuario_id,
      datos.tipo_usuario,
      datos.nit
    );
    res.json({ success: true, data: estadisticas });
  } catch (err) {
    next(err);
  }
}

async function getRutasActivas(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    const result = await routeService.obtenerRutasActivas(
      req.user.usuario_id,
      datos.tipo_usuario,
      datos.nit
    );
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
}

async function actualizarEstadoRuta(req, res, next) {
  try {
    const { ruta_id, estado } = req.body;
    if (!ruta_id) {
      return res.status(400).json({ success: false, message: 'ruta_id es requerido' });
    }
    const nuevoEstado = estado === true || estado === 'true' ? 'completada' : 'activa';
    await routeService.actualizarEstadoRuta(ruta_id, nuevoEstado);
    res.json({ success: true, message: 'Estado actualizado correctamente', nuevo_estado: nuevoEstado });
  } catch (err) {
    next(err);
  }
}

async function crearRuta(req, res, next) {
  try {
    const { cliente_codigo, cliente_nombre, descripcion } = req.body;
    if (!cliente_codigo || !cliente_nombre) {
      return res.status(400).json({ success: false, message: 'cliente_codigo y cliente_nombre son requeridos' });
    }
    const rutaId = await routeService.crearNuevaRuta(
      cliente_codigo,
      cliente_nombre,
      req.user.usuario_id,
      descripcion
    );
    res.status(201).json({ success: true, message: 'Ruta creada exitosamente', data: { ruta_id: rutaId } });
  } catch (err) {
    next(err);
  }
}

async function getTareasPendientes(req, res, next) {
  try {
    const tareas = await routeService.obtenerTareasPendientes(req.user.usuario_id);
    res.json({ success: true, total: tareas.length, data: tareas });
  } catch (err) {
    next(err);
  }
}

async function actualizarEstadoTarea(req, res, next) {
  try {
    const { tarea_id, estado } = req.body;
    if (!tarea_id) {
      return res.status(400).json({ success: false, message: 'tarea_id es requerido' });
    }
    const nuevoEstado = estado === true || estado === 'true' ? 'completada' : 'pendiente';
    await routeService.actualizarEstadoTarea(tarea_id, nuevoEstado);
    res.json({ success: true, message: 'Estado de tarea actualizado correctamente', nuevo_estado: nuevoEstado });
  } catch (err) {
    next(err);
  }
}

async function getDashboard(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    const perfil = await userService.obtenerPerfilUsuario(req.user.usuario_id);

    const [estadisticas, rutasActivas, tareasPendientes] = await Promise.all([
      routeService.obtenerEstadisticas(req.user.usuario_id, datos.tipo_usuario, datos.nit),
      routeService.obtenerRutasActivas(req.user.usuario_id, datos.tipo_usuario, datos.nit),
      routeService.obtenerTareasPendientes(req.user.usuario_id),
    ]);

    const clientService = require('../services/clientService');
    const esAdmin = req.user.usuario_id === 1;

    const [todosClientes, clientesNoAsignados, clientesProximos] = await Promise.all([
      clientService.obtenerTodosClientesSAP(datos.nit, esAdmin, datos.tipo_usuario),
      clientService.obtenerClientesNoAsignados(datos.nit, esAdmin, datos.tipo_usuario),
      clientService.obtenerClientesProximosARevisitar(req.user.usuario_id),
    ]);

    res.json({
      success: true,
      data: {
        perfil,
        estadisticas,
        rutas_activas: rutasActivas,
        tareas_pendientes: tareasPendientes,
        clientes_sap_total: todosClientes.length,
        clientes_no_asignados_total: clientesNoAsignados.length,
        clientes_proximos_total: clientesProximos.length,
        clientes_proximos: clientesProximos,
      },
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getEstadisticas,
  getRutasActivas,
  actualizarEstadoRuta,
  crearRuta,
  getTareasPendientes,
  actualizarEstadoTarea,
  getDashboard,
};
