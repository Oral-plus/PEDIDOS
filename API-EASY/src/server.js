require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const clientRoutes = require('./routes/clients');
const routeRoutes = require('./routes/routes');
const errorHandler = require('./middleware/errorHandler');
const { closeAll } = require('./config/database');
const orderService = require('./services/orderService');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/api/test', (_req, res) => {
  res.json({ success: true, message: 'API funcionando', timestamp: new Date().toISOString() });
});

app.use('/api/auth', authRoutes);
app.use('/api/usuarios', userRoutes);
app.use('/api/clientes', clientRoutes);
app.use('/api/rutas', routeRoutes);

app.post('/api/orders', async (req, res) => {
  try {
    const { cedula, nombre, correo, telefono, direccion, subtotal, productos, observaciones, codigoCliente, vendedor, ciudad } = req.body;
    if (!cedula || !nombre || !correo) {
      return res.status(400).json({ success: false, message: 'Cédula, nombre y correo son requeridos' });
    }
    if (!productos || !Array.isArray(productos) || productos.length === 0) {
      return res.status(400).json({ success: false, message: 'Debe incluir al menos un producto' });
    }
    const result = await orderService.crearPedido({ cedula, nombre, correo, telefono, direccion, subtotal: subtotal || 0, productos, observaciones, codigoCliente, vendedor, ciudad });
    res.status(200).json(result);
  } catch (err) {
    console.error('Error al crear pedido:', err.message);
    res.status(500).json({ success: false, message: err.message || 'Error interno del servidor' });
  }
});

app.get('/api/orders', async (req, res) => {
  try {
    const result = await orderService.obtenerPedidosPorCliente(req.query.cliente, req.query.estado);
    res.json(result);
  } catch (err) {
    console.error('Error consultando pedidos:', err.message);
    res.status(500).json({ success: false, message: err.message, data: [] });
  }
});

app.get('/api/orders/vendedor/:nombre', async (req, res) => {
  try {
    const result = await orderService.obtenerPedidosPorVendedor(decodeURIComponent(req.params.nombre), req.query.estado);
    res.json(result);
  } catch (err) {
    console.error('Error consultando pedidos vendedor:', err.message);
    res.status(500).json({ success: false, message: err.message, data: [] });
  }
});

app.get('/api/orders/detail/:numeroPedido', async (req, res) => {
  try {
    const result = await orderService.obtenerDetallePedido(decodeURIComponent(req.params.numeroPedido));
    res.json(result);
  } catch (err) {
    console.error('Error consultando detalle pedido:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

app.use(errorHandler);

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`API corriendo en http://0.0.0.0:${PORT}`);
  console.log(`Acceso red local: http://192.168.2.244:${PORT}`);
  console.log(`Documentación: http://192.168.2.244:${PORT}/api/health`);
});

async function shutdown() {
  console.log('\nCerrando servidor...');
  server.close();
  await closeAll();
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('uncaughtException', (err) => {
  console.error('Excepción no capturada:', err.message);
});
process.on('unhandledRejection', (reason) => {
  console.error('Promesa rechazada:', reason);
});
