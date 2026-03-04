const orderService = require('../services/orderService');

async function createOrder(req, res, next) {
  try {
    const { cedula, nombre, correo, telefono, direccion, subtotal, productos, observaciones } = req.body;

    if (!cedula || !nombre || !correo) {
      return res.status(400).json({
        success: false,
        message: 'Cédula, nombre y correo son requeridos',
      });
    }

    if (!productos || !Array.isArray(productos) || productos.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Debe incluir al menos un producto',
      });
    }

    const result = await orderService.crearPedido({
      cedula,
      nombre,
      correo,
      telefono,
      direccion,
      subtotal: subtotal || 0,
      productos,
      observaciones,
    });

    res.status(200).json(result);
  } catch (err) {
    console.error('Error al crear pedido:', err.message);
    next(err);
  }
}

module.exports = { createOrder };
