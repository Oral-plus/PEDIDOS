<?php
// api/transactions_premium.php
require_once '../config/database.php';
require_once '../utils/notifications.php';
require_once '../utils/analytics.php';

function calculateCashback($userId, $serviceId, $amount) {
    try {
        $conn = getDbConnection();
        
        // Obtener cashback del servicio
        $sql = "SELECT cashback_porcentaje FROM servicios WHERE id = ?";
        $stmt = executeQuery($conn, $sql, [$serviceId]);
        $service = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
        
        $baseCashback = ($amount * $service['cashback_porcentaje']) / 100;
        
        // Verificar promociones activas
        $sql = "SELECT cashback_extra FROM promociones 
               WHERE activa = 1 AND fecha_inicio <= GETDATE() AND fecha_fin >= GETDATE()
               AND (servicios_aplicables IS NULL OR servicios_aplicables LIKE '%{$serviceId}%')";
        $stmt = sqlsrv_query($conn, $sql);
        
        $extraCashback = 0;
        while ($promo = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
            $extraCashback += ($amount * $promo['cashback_extra']) / 100;
        }
        
        closeDbConnection($conn);
        return $baseCashback + $extraCashback;
        
    } catch (Exception $e) {
        return 0;
    }
}

function calculatePoints($amount) {
    return floor($amount); // 1 punto por boliviano
}

function generateReference() {
    return 'TXN' . date('Ymd') . sprintf('%06d', mt_rand(100000, 999999));
}

function updateSpendingLimits($userId, $amount) {
    try {
        $conn = getDbConnection();
        
        // Verificar si necesitamos resetear límites diarios/mensuales
        $sql = "SELECT id, gasto_diario, gasto_mensual, fecha_ultimo_reset_diario, fecha_ultimo_reset_mensual,
                       limite_diario, limite_mensual
                FROM cuentas WHERE usuario_id = ? AND activa = 1";
        $stmt = executeQuery($conn, $sql, [$userId]);
        $account = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
        
        if (!$account) return false;
        
        $today = date('Y-m-d');
        $thisMonth = date('Y-m-01');
        
        $newDailySpent = $account['gasto_diario'];
        $newMonthlySpent = $account['gasto_mensual'];
        
        // Reset diario si es necesario
        if ($account['fecha_ultimo_reset_diario']->format('Y-m-d') != $today) {
            $newDailySpent = 0;
        }
        
        // Reset mensual si es necesario
        if ($account['fecha_ultimo_reset_mensual']->format('Y-m-01') != $thisMonth) {
            $newMonthlySpent = 0;
        }
        
        $newDailySpent += $amount;
        $newMonthlySpent += $amount;
        
        // Verificar límites
        if ($newDailySpent > $account['limite_diario']) {
            throw new Exception('Límite diario excedido');
        }
        
        if ($newMonthlySpent > $account['limite_mensual']) {
            throw new Exception('Límite mensual excedido');
        }
        
        // Actualizar gastos
        $sql = "UPDATE cuentas SET 
                gasto_diario = ?, 
                gasto_mensual = ?,
                fecha_ultimo_reset_diario = ?,
                fecha_ultimo_reset_mensual = ?
                WHERE id = ?";
        
        executeQuery($conn, $sql, [
            $newDailySpent,
            $newMonthlySpent,
            $today,
            $thisMonth,
            $account['id']
        ]);
        
        closeDbConnection($conn);
        return true;
        
    } catch (Exception $e) {
        throw $e;
    }
}

try {
    $method = $_SERVER['REQUEST_METHOD'];
    $input = json_decode(file_get_contents('php://input'), true);
    
    if ($method === 'GET') {
        $action = $_GET['action'] ?? '';
        $userId = $_GET['user_id'] ?? '';
        
        switch ($action) {
            case 'balance':
                if (empty($userId)) {
                    throw new Exception('ID de usuario requerido');
                }
                
                $conn = getDbConnection();
                $sql = "SELECT c.saldo, c.saldo_bloqueado, c.numero_cuenta, c.limite_diario, c.limite_mensual,
                              c.gasto_diario, c.gasto_mensual, u.puntos_recompensa
                       FROM cuentas c 
                       JOIN usuarios u ON c.usuario_id = u.id
                       WHERE c.usuario_id = ? AND c.activa = 1";
                $stmt = executeQuery($conn, $sql, [$userId]);
                
                $account = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$account) {
                    throw new Exception('Cuenta no encontrada');
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => [
                        'balance' => floatval($account['saldo']),
                        'balance_blocked' => floatval($account['saldo_bloqueado']),
                        'account_number' => $account['numero_cuenta'],
                        'daily_limit' => floatval($account['limite_diario']),
                        'monthly_limit' => floatval($account['limite_mensual']),
                        'daily_spent' => floatval($account['gasto_diario']),
                        'monthly_spent' => floatval($account['gasto_mensual']),
                        'reward_points' => intval($account['puntos_recompensa'])
                    ]
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'history':
                if (empty($userId)) {
                    throw new Exception('ID de usuario requerido');
                }
                
                $limit = $_GET['limit'] ?? 50;
                $offset = $_GET['offset'] ?? 0;
                $category = $_GET['category'] ?? '';
                
                $conn = getDbConnection();
                
                $whereClause = "WHERE t.usuario_id = ?";
                $params = [$userId];
                
                if (!empty($category)) {
                    $whereClause .= " AND s.categoria = ?";
                    $params[] = $category;
                }
                
                $sql = "SELECT t.*, s.nombre as servicio_nombre, s.icono, s.color, s.categoria
                       FROM transacciones t 
                       LEFT JOIN servicios s ON t.servicio_id = s.id 
                       {$whereClause}
                       ORDER BY t.fecha_transaccion DESC
                       OFFSET ? ROWS FETCH NEXT ? ROWS ONLY";
                
                $params[] = $offset;
                $params[] = $limit;
                
                $stmt = executeQuery($conn, $sql, $params);
                
                $transactions = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $transactions[] = [
                        'id' => $row['id'],
                        'tipo_transaccion' => $row['tipo_transaccion'],
                        'monto' => floatval($row['monto']),
                        'comision' => floatval($row['comision']),
                        'cashback' => floatval($row['cashback']),
                        'referencia' => $row['referencia'],
                        'descripcion' => $row['descripcion'],
                        'estado' => $row['estado'],
                        'fecha_transaccion' => $row['fecha_transaccion']->format('Y-m-d H:i:s'),
                        'numero_destino' => $row['numero_destino'],
                        'servicio_nombre' => $row['servicio_nombre'],
                        'icono' => $row['icono'],
                        'color' => $row['color'],
                        'categoria' => $row['categoria'],
                        'puntos_ganados' => intval($row['puntos_ganados'])
                    ];
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => $transactions
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'services':
                $category = $_GET['category'] ?? '';
                $popular = $_GET['popular'] ?? '';
                
                $conn = getDbConnection();
                
                $whereClause = "WHERE activo = 1";
                $params = [];
                
                if (!empty($category)) {
                    $whereClause .= " AND categoria = ?";
                    $params[] = $category;
                }
                
                if ($popular === 'true') {
                    $whereClause .= " AND popular = 1";
                }
                
                $sql = "SELECT * FROM servicios {$whereClause} ORDER BY orden_visualizacion, categoria, nombre";
                $stmt = executeQuery($conn, $sql, $params);
                
                $services = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $services[] = [
                        'id' => $row['id'],
                        'nombre' => $row['nombre'],
                        'descripcion' => $row['descripcion'],
                        'categoria' => $row['categoria'],
                        'subcategoria' => $row['subcategoria'],
                        'icono' => $row['icono'],
                        'color' => $row['color'],
                        'comision' => floatval($row['comision']),
                        'monto_minimo' => floatval($row['monto_minimo']),
                        'monto_maximo' => floatval($row['monto_maximo']),
                        'cashback_porcentaje' => floatval($row['cashback_porcentaje']),
                        'popular' => $row['popular'],
                        'nuevo' => $row['nuevo'],
                        'promocion' => $row['promocion']
                    ];
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => $services
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'analytics':
                if (empty($userId)) {
                    throw new Exception('ID de usuario requerido');
                }
                
                $period = $_GET['period'] ?? 'month'; // month, week, year
                
                $analytics = generateSpendingAnalytics($userId, $period);
                
                echo json_encode([
                    'success' => true,
                    'data' => $analytics
                ]);
                break;
                
            case 'promotions':
                $conn = getDbConnection();
                $sql = "SELECT * FROM promociones 
                       WHERE activa = 1 AND fecha_inicio <= GETDATE() AND fecha_fin >= GETDATE()
                       ORDER BY prioridad DESC, fecha_inicio DESC";
                $stmt = sqlsrv_query($conn, $sql);
                
                $promotions = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $promotions[] = [
                        'id' => $row['id'],
                        'titulo' => $row['titulo'],
                        'descripcion' => $row['descripcion'],
                        'tipo' => $row['tipo'],
                        'descuento_porcentaje' => floatval($row['descuento_porcentaje']),
                        'cashback_extra' => floatval($row['cashback_extra']),
                        'fecha_fin' => $row['fecha_fin']->format('Y-m-d H:i:s'),
                        
                    ];
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => $promotions
                ]);
                
                closeDbConnection($conn);
                break;
        }
    } elseif ($method === 'POST') {
        $action = $_GET['action'] ?? '';
        
        switch ($action) {
            case 'payment':
                $userId = $input['user_id'] ?? '';
                $servicioId = $input['servicio_id'] ?? '';
                $monto = floatval($input['monto'] ?? 0);
                $numeroDestino = $input['numero_destino'] ?? '';
                $descripcion = $input['descripcion'] ?? '';
                $ubicacionLat = $input['ubicacion_lat'] ?? null;
                $ubicacionLng = $input['ubicacion_lng'] ?? null;
                $metodoAuth = $input['metodo_auth'] ?? 'PASSWORD';
                
                if (empty($userId) || empty($servicioId) || $monto <= 0) {
                    throw new Exception('Datos incompletos para el pago');
                }
                
                $conn = getDbConnection();
                
                // Verificar límites de gasto
                updateSpendingLimits($userId, $monto);
                
                // Verificar saldo
                $sql = "SELECT id, saldo FROM cuentas WHERE usuario_id = ? AND activa = 1";
                $stmt = executeQuery($conn, $sql, [$userId]);
                $account = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$account) {
                    throw new Exception('Cuenta no encontrada');
                }
                
                // Obtener información del servicio
                $sql = "SELECT * FROM servicios WHERE id = ? AND activo = 1";
                $stmt = executeQuery($conn, $sql, [$servicioId]);
                $service = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$service) {
                    throw new Exception('Servicio no disponible');
                }
                
                // Verificar montos mínimos y máximos
                if ($monto < $service['monto_minimo'] || $monto > $service['monto_maximo']) {
                    throw new Exception("Monto debe estar entre {$service['monto_minimo']} y {$service['monto_maximo']}");
                }
                
                // Calcular comisión
                $comision = ($monto * $service['comision']) / 100;
                if ($service['comision_fija'] > 0) {
                    $comision += $service['comision_fija'];
                }
                
                // Calcular cashback
                $cashback = calculateCashback($userId, $servicioId, $monto);
                
                // Calcular puntos
                $puntos = calculatePoints($monto);
                
                $montoTotal = $monto + $comision;
                
                if ($account['saldo'] < $montoTotal) {
                    throw new Exception('Saldo insuficiente (incluye comisión)');
                }
                
                // Generar referencia única
                $referencia = generateReference();
                
                // Iniciar transacción
                sqlsrv_begin_transaction($conn);
                
                try {
                    // Registrar transacción
                    $sql = "INSERT INTO transacciones (usuario_id, cuenta_id, servicio_id, tipo_transaccion, 
                                                     monto, comision, cashback, referencia, descripcion, 
                                                     numero_destino, estado, ip_origen, dispositivo_origen,
                                                     ubicacion_lat, ubicacion_lng, metodo_autenticacion,
                                                     puntos_ganados, categoria_gasto) 
                           VALUES (?, ?, ?, 'PAGO', ?, ?, ?, ?, ?, ?, 'COMPLETADO', ?, ?, ?, ?, ?, ?, ?)";
                    
                    executeQuery($conn, $sql, [
                        $userId, $account['id'], $servicioId, $monto, $comision, $cashback,
                        $referencia, $descripcion, $numeroDestino, $_SERVER['REMOTE_ADDR'],
                        $_SERVER['HTTP_USER_AGENT'], $ubicacionLat, $ubicacionLng,
                        $metodoAuth, $puntos, $service['categoria']
                    ]);
                    
                    // Actualizar saldo
                    $nuevoSaldo = $account['saldo'] - $montoTotal + $cashback;
                    $sql = "UPDATE cuentas SET saldo = ? WHERE id = ?";
                    executeQuery($conn, $sql, [$nuevoSaldo, $account['id']]);
                    
                    // Actualizar puntos del usuario
                    $sql = "UPDATE usuarios SET puntos_recompensa = puntos_recompensa + ? WHERE id = ?";
                    executeQuery($conn, $sql, [$puntos, $userId]);
                    
                    // Registrar recompensa
                    if ($cashback > 0 || $puntos > 0) {
                        $sql = "INSERT INTO recompensas (usuario_id, tipo, puntos, cashback, descripcion) 
                               VALUES (?, 'TRANSACCION', ?, ?, ?)";
                        executeQuery($conn, $sql, [
                            $userId, $puntos, $cashback, 
                            "Recompensa por pago de {$service['nombre']}"
