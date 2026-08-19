const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { sql, getDbPool } = require('../config/database');

async function login(usuario, password) {
  const pool = await getDbPool();

  const result = await pool
    .request()
    .input('usuario', sql.NVarChar, usuario)
    .query('SELECT id, nombre, usuario, password FROM usuarios_ruta WHERE usuario = @usuario');

  if (result.recordset.length === 0) {
    return { success: false, message: 'Usuario no encontrado' };
  }

  const row = result.recordset[0];
  const passwordValid = await bcrypt.compare(password, row.password);

  if (!passwordValid) {
    return { success: false, message: 'Contraseña incorrecta' };
  }

  const token = jwt.sign(
    { usuario_id: row.id, nombre: row.nombre, usuario: row.usuario },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
  );

  return {
    success: true,
    message: 'Inicio de sesión exitoso',
    data: {
      token,
      usuario: { id: row.id, nombre: row.nombre, usuario: row.usuario },
    },
  };
}

async function register(nombre, usuario, password, nit, tipo_usuario = 'OSLP') {
  const pool = await getDbPool();

  const existing = await pool
    .request()
    .input('usuario', sql.NVarChar, usuario)
    .query('SELECT id FROM usuarios_ruta WHERE usuario = @usuario');

  if (existing.recordset.length > 0) {
    return { success: false, message: 'El usuario ya existe' };
  }

  const hashedPassword = await bcrypt.hash(password, 10);

  await pool
    .request()
    .input('nombre', sql.NVarChar, nombre)
    .input('usuario', sql.NVarChar, usuario)
    .input('password', sql.NVarChar, hashedPassword)
    .input('nit', sql.NVarChar, nit || null)
    .input('tipo_usuario', sql.NVarChar, tipo_usuario)
    .query(
      'INSERT INTO usuarios_ruta (nombre, usuario, password, nit, tipo_usuario) VALUES (@nombre, @usuario, @password, @nit, @tipo_usuario)'
    );

  return { success: true, message: 'Usuario registrado correctamente' };
}

module.exports = { login, register };
