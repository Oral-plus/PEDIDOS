<?php
// api/transactions.php
require_once '../config/database.php';

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
                $sql = "SELECT saldo FROM cuentas WHERE usuario_id = ? AND activa = 1";
                $stmt = executeQuery($conn, $sql, [$userId]);
                
                $account = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                echo json_encode([
                    'success' => true,
                    'data' => ['balance' => $account['saldo'] ?? 0.00]
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'history':
                if (empty($userId)) {
                    throw new Exception('ID de usuario requerido');
                }
                
                $conn = getDbConnection();
                $sql = "SELECT t.*, s.nombre as servicio_nombre, s.icono, s.color 
                       FROM transacciones t 
                       LEFT JOIN servicios s ON t.servicio_id = s.id 
                       WHERE t.usuario_id = ? 
                       ORDER BY t.fecha_transaccion DESC";
                $stmt = executeQuery($conn, $sql, [$userId]);
                
                $transactions = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $transactions[] = $row;
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => $transactions
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'services':
                $conn = getDbConnection();
                $sql = "SELECT * FROM servicios WHERE activo = 1 ORDER BY categoria, nombre";
                $stmt = sqlsrv_query($conn, $sql);
                
                $services = [];
                while ($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) {
                    $services[] = $row;
                }
                
                echo json_encode([
                    'success' => true,
                    'data' => $services
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
                $monto = $input['monto'] ?? 0;
                $numeroDestino = $input['numero_destino'] ?? '';
                $descripcion = $input['descripcion'] ?? '';
                
                if (empty($userId) || empty($servicioId) || $monto <= 0) {
                    throw new Exception('Datos incompletos para el pago');
                }
                
                $conn = getDbConnection();
                
                // Verificar saldo
                $sql = "SELECT id, saldo FROM cuentas WHERE usuario_id = ? AND activa = 1";
                $stmt = executeQuery($conn, $sql, [$userId]);
                $account = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$account || $account['saldo'] < $monto) {
                    throw new Exception('Saldo insuficiente');
                }
                
                // Obtener comisión del servicio
                $sql = "SELECT comision FROM servicios WHERE id = ?";
                $stmt = executeQuery($conn, $sql, [$servicioId]);
                $service = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                $comision = ($monto * $service['comision']) / 100;
                
                $montoTotal = $monto + $comision;
                
                if ($account['saldo'] < $montoTotal) {
                    throw new Exception('Saldo insuficiente (incluye comisión)');
                }
                
                // Generar referencia única
                $referencia = 'TXN' . time() . rand(1000, 9999);
                
                // Registrar transacción
                $sql = "INSERT INTO transacciones (usuario_id, cuenta_id, servicio_id, tipo_transaccion, monto, comision, referencia, descripcion, numero_destino, estado) 
                       VALUES (?, ?, ?, 'PAGO', ?, ?, ?, ?, ?, 'COMPLETADO')";
                executeQuery($conn, $sql, [$userId, $account['id'], $servicioId, $monto, $comision, $referencia, $descripcion, $numeroDestino]);
                
                // Actualizar saldo
                $nuevoSaldo = $account['saldo'] - $montoTotal;
                $sql = "UPDATE cuentas SET saldo = ? WHERE id = ?";
                executeQuery($conn, $sql, [$nuevoSaldo, $account['id']]);
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Pago realizado exitosamente',
                    'data' => [
                        'referencia' => $referencia,
                        'monto' => $monto,
                        'comision' => $comision,
                        'nuevo_saldo' => $nuevoSaldo
                    ]
                ]);
                
                closeDbConnection($conn);
                break;
        }
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
