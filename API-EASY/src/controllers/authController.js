const authService = require('../services/authService');

async function login(req, res, next) {
  try {
    const { usuario, password } = req.body;
    if (!usuario || !password) {
      return res.status(400).json({ success: false, message: 'Usuario y contraseña son requeridos' });
    }
    const result = await authService.login(usuario, password);
    const status = result.success ? 200 : 401;
    res.status(status).json(result);
  } catch (err) {
    next(err);
  }
}

async function register(req, res, next) {
  try {
    const { nombre, usuario, password, nit, tipo_usuario } = req.body;
    if (!nombre || !usuario || !password) {
      return res.status(400).json({ success: false, message: 'Nombre, usuario y contraseña son requeridos' });
    }
    const result = await authService.register(nombre, usuario, password, nit, tipo_usuario);
    const status = result.success ? 201 : 409;
    res.status(status).json(result);
  } catch (err) {
    next(err);
  }
}

module.exports = { login, register };
