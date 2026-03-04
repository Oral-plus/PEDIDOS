const clientService = require('../services/clientService');
const userService = require('../services/userService');

async function getTodosClientes(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    const esAdmin = req.user.usuario_id === 1;
    const clientes = await clientService.obtenerTodosClientesSAP(datos.nit, esAdmin, datos.tipo_usuario);
    res.json({ success: true, total: clientes.length, data: clientes });
  } catch (err) {
    next(err);
  }
}

async function getClientesNoAsignados(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    const esAdmin = req.user.usuario_id === 1;
    const clientes = await clientService.obtenerClientesNoAsignados(datos.nit, esAdmin, datos.tipo_usuario);
    res.json({ success: true, total: clientes.length, data: clientes });
  } catch (err) {
    next(err);
  }
}

async function getClientesProximos(req, res, next) {
  try {
    const clientes = await clientService.obtenerClientesProximosARevisitar(req.user.usuario_id);
    res.json({ success: true, total: clientes.length, data: clientes });
  } catch (err) {
    next(err);
  }
}

async function getClientePorCodigo(req, res, next) {
  try {
    const { codigo } = req.params;
    const cliente = await clientService.obtenerClientePorCodigo(codigo);
    if (!cliente) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }
    res.json({ success: true, data: cliente });
  } catch (err) {
    next(err);
  }
}

async function getCarteraCliente(req, res, next) {
  try {
    const { codigo } = req.params;
    const cartera = await clientService.obtenerCarteraCliente(codigo);
    if (!cartera) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }
    res.json({ success: true, data: cartera });
  } catch (err) {
    next(err);
  }
}

module.exports = { getTodosClientes, getClientesNoAsignados, getClientesProximos, getClientePorCodigo, getCarteraCliente };
