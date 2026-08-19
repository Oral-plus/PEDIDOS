const { Router } = require('express');
const routeController = require('../controllers/routeController');
const { authMiddleware } = require('../middleware/auth');

const router = Router();

router.use(authMiddleware);

router.get('/dashboard', routeController.getDashboard);
router.get('/estadisticas', routeController.getEstadisticas);
router.get('/activas', routeController.getRutasActivas);
router.post('/crear', routeController.crearRuta);
router.put('/estado', routeController.actualizarEstadoRuta);
router.get('/tareas', routeController.getTareasPendientes);
router.put('/tareas/estado', routeController.actualizarEstadoTarea);

module.exports = router;
