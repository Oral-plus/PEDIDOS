const { Router } = require('express');
const clientController = require('../controllers/clientController');
const { authMiddleware } = require('../middleware/auth');

const router = Router();

router.use(authMiddleware);

router.get('/', clientController.getTodosClientes);
router.get('/no-asignados', clientController.getClientesNoAsignados);
router.get('/proximos-revisitar', clientController.getClientesProximos);
router.get('/cartera/:codigo', clientController.getCarteraCliente);
router.get('/:codigo', clientController.getClientePorCodigo);

module.exports = router;
