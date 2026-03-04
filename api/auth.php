<?php
// api/auth.php
require_once '../config/database.php';

function hashPassword($password) {
    return password_hash($password, PASSWORD_DEFAULT);
}

function verifyPassword($password, $hash) {
    return password_verify($password, $hash);
}

function generateToken($userId) {
    $payload = [
        'user_id' => $userId,
        'exp' => time() + (24 * 60 * 60) // 24 horas
    ];
    return base64_encode(json_encode($payload));
}

try {
    $method = $_SERVER['REQUEST_METHOD'];
    $input = json_decode(file_get_contents('php://input'), true);
    
    if ($method === 'POST') {
        $action = $_GET['action'] ?? '';
        
        switch ($action) {
            case 'login':
                $email = $input['email'] ?? '';
                $password = $input['password'] ?? '';
                
                if (empty($email) || empty($password)) {
                    throw new Exception('Email y contraseña son requeridos');
                }
                
                $conn = getDbConnection();
                $sql = "SELECT id, nombre, apellido, email, password_hash, activo, avatar FROM usuarios WHERE email = ? AND activo = 1";
                $stmt = executeQuery($conn, $sql, [$email]);
                
                $user = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$user || !verifyPassword($password, $user['password_hash'])) {
                    throw new Exception('Credenciales inválidas');
                }
                
                $token = generateToken($user['id']);
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Login exitoso',
                    'data' => [
                        'user' => [
                            'id' => $user['id'],
                            'nombre' => $user['nombre'],
                            'apellido' => $user['apellido'],
                            'email' => $user['email'],
                            'avatar' => $user['avatar']
                        ],
                        'token' => $token
                    ]
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'register':
                $nombre = $input['nombre'] ?? '';
                $apellido = $input['apellido'] ?? '';
                $email = $input['email'] ?? '';
                $telefono = $input['telefono'] ?? '';
                $password = $input['password'] ?? '';
                
                if (empty($nombre) || empty($apellido) || empty($email) || empty($password)) {
                    throw new Exception('Todos los campos son requeridos');
                }
                
                $conn = getDbConnection();
                
                // Verificar si el email ya existe
                $sql = "SELECT id FROM usuarios WHERE email = ?";
                $stmt = executeQuery($conn, $sql, [$email]);
                
                if (sqlsrv_fetch_array($stmt)) {
                    throw new Exception('El email ya está registrado');
                }
                
                // Crear usuario
                $passwordHash = hashPassword($password);
                $sql = "INSERT INTO usuarios (nombre, apellido, email, telefono, password_hash) VALUES (?, ?, ?, ?, ?)";
                $stmt = executeQuery($conn, $sql, [$nombre, $apellido, $email, $telefono, $passwordHash]);
                
                // Obtener ID del usuario creado
                $sql = "SELECT SCOPE_IDENTITY() as id";
                $stmt = sqlsrv_query($conn, $sql);
                $result = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                $userId = $result['id'];
                
                // Crear cuenta principal
                $numeroCuenta = 'SKY' . str_pad($userId, 8, '0', STR_PAD_LEFT);
                $sql = "INSERT INTO cuentas (usuario_id, numero_cuenta, saldo) VALUES (?, ?, 0.00)";
                executeQuery($conn, $sql, [$userId, $numeroCuenta]);
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Usuario registrado exitosamente',
                    'data' => ['user_id' => $userId]
                ]);
                
                closeDbConnection($conn);
                break;
                
            default:
                throw new Exception('Acción no válida');
        }
    } else {
        throw new Exception('Método no permitido');
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
?>
