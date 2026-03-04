const { Router } = require('express');
const userController = require('../controllers/userController');
const { authMiddleware } = require('../middleware/auth');

const router = Router();

router.use(authMiddleware);

router.get('/perfil', userController.getPerfil);
router.post('/sync-sap', userController.syncNombreSAP);
router.get('/oslp-asociados', userController.getOSLPAsociados);

module.exports = router;
