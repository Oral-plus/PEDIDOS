const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Token no proporcionado' });
  }

  const token = header.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ success: false, message: 'Token inválido o expirado' });
  }
}

function adminOnly(req, res, next) {
  if (req.user.usuario_id !== 1) {
    return res.status(403).json({ success: false, message: 'Acceso denegado: solo administradores' });
  }
  next();
}

module.exports = { authMiddleware, adminOnly };
