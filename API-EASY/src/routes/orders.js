const { Router } = require('express');
const orderController = require('../controllers/orderController');

const router = Router();

router.post('/', orderController.createOrder);

module.exports = router;
