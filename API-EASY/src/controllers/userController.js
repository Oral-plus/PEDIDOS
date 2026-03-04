const userService = require('../services/userService');

async function getPerfil(req, res, next) {
  try {
    const perfil = await userService.obtenerPerfilUsuario(req.user.usuario_id);
    res.json({ success: true, data: perfil });
  } catch (err) {
    next(err);
  }
}

async function syncNombreSAP(req, res, next) {
  try {
    const result = await userService.sincronizarNombreSAP(req.user.usuario_id);
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
}

async function getOSLPAsociados(req, res, next) {
  try {
    const datos = await userService.obtenerNitUsuario(req.user.usuario_id);
    if (datos.tipo_usuario !== 'COACH' || !datos.nit) {
      return res.json({ success: true, data: [], message: 'No es un usuario COACH o no tiene NIT' });
    }
    const oslp = await userService.obtenerOSLPAsociadosACoach(datos.nit);
    res.json({ success: true, data: oslp });
  } catch (err) {
    next(err);
  }
}

module.exports = { getPerfil, syncNombreSAP, getOSLPAsociados };
