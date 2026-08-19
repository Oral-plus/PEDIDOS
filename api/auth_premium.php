<?php
// api/auth_premium.php
require_once '../config/database.php';
require_once '../utils/security.php';
require_once '../utils/notifications.php';

function hashPassword($password) {
    return password_hash($password, PASSWORD_DEFAULT);
}

function verifyPassword($password, $hash) {
    return password_verify($password, $hash);
}

function generateToken($userId) {
    $payload = [
        'user_id' => $userId,
        'exp' => time() + (24 * 60 * 60),
        'iat' => time(),
        'device_id' => $_SERVER['HTTP_X_DEVICE_ID'] ?? 'unknown'
    ];
    return base64_encode(json_encode($payload));
}

function generateReferralCode($userId) {
    return 'SKY' . str_pad($userId, 4, '0', STR_PAD_LEFT);
}

function logSecurityEvent($userId, $event, $description, $riskLevel = 'BAJO') {
    try {
        $conn = getDbConnection();
        $sql = "INSERT INTO logs_seguridad (usuario_id, evento, descripcion, ip_address, user_agent, nivel_riesgo, dispositivo_id) 
                VALUES (?, ?, ?, ?, ?, ?, ?)";
        
        $params = [
            $userId,
            $event,
            $description,
            $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
            $riskLevel,
            $_SERVER['HTTP_X_DEVICE_ID'] ?? 'unknown'
        ];
        
        executeQuery($conn, $sql, $params);
        closeDbConnection($conn);
    } catch (Exception $e) {
        error_log("Error logging security event: " . $e->getMessage());
    }
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
                $deviceId = $input['device_id'] ?? '';
                $biometricAuth = $input['biometric_auth'] ?? false;
                
                if (empty($email) || empty($password)) {
                    throw new Exception('Email y contraseña son requeridos');
                }
                
                $conn = getDbConnection();
                
                // Verificar intentos fallidos
                $sql = "SELECT COUNT(*) as intentos FROM logs_seguridad 
                       WHERE evento = 'LOGIN_FAILED' AND ip_address = ? 
                       AND fecha_evento > DATEADD(minute, -30, GETDATE())";
                $stmt = executeQuery($conn, $sql, [$_SERVER['REMOTE_ADDR']]);
                $intentos = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if ($intentos['intentos'] >= 5) {
                    logSecurityEvent(null, 'LOGIN_BLOCKED', 'IP bloqueada por múltiples intentos fallidos', 'ALTO');
                    throw new Exception('Demasiados intentos fallidos. Intenta más tarde.');
                }
                
                $sql = "SELECT id, nombre, apellido, email, password_hash, activo, avatar, biometric_enabled, 
                              two_factor_enabled, puntos_recompensa, nivel_verificacion, tema_preferido, 
                              idioma_preferido FROM usuarios WHERE email = ? AND activo = 1";
                $stmt = executeQuery($conn, $sql, [$email]);
                
                $user = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if (!$user || !verifyPassword($password, $user['password_hash'])) {
                    logSecurityEvent($user['id'] ?? null, 'LOGIN_FAILED', 'Credenciales inválidas', 'MEDIO');
                    throw new Exception('Credenciales inválidas');
                }
                
                // Registrar dispositivo si es nuevo
                if (!empty($deviceId)) {
                    $sql = "SELECT id FROM dispositivos WHERE device_id = ? AND usuario_id = ?";
                    $stmt = executeQuery($conn, $sql, [$deviceId, $user['id']]);
                    
                    if (!sqlsrv_fetch_array($stmt)) {
                        $sql = "INSERT INTO dispositivos (usuario_id, device_id, nombre, tipo, sistema_operativo, 
                                                        version_app, ip_address, biometric_available, nfc_available) 
                               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
                        executeQuery($conn, $sql, [
                            $user['id'],
                            $deviceId,
                            $input['device_name'] ?? 'Dispositivo móvil',
                            $input['device_type'] ?? 'mobile',
                            $input['os'] ?? 'unknown',
                            $input['app_version'] ?? '2.0.0',
                            $_SERVER['REMOTE_ADDR'],
                            $input['biometric_available'] ?? 0,
                            $input['nfc_available'] ?? 0
                        ]);
                    }
                }
                
                // Actualizar última actividad
                $sql = "UPDATE usuarios SET ultima_actividad = GETDATE() WHERE id = ?";
                executeQuery($conn, $sql, [$user['id']]);
                
                $token = generateToken($user['id']);
                
                logSecurityEvent($user['id'], 'LOGIN_SUCCESS', 'Login exitoso', 'BAJO');
                
                // Crear notificación de bienvenida
                createNotification($user['id'], 'Bienvenido de vuelta', 
                                 'Has iniciado sesión exitosamente', 'LOGIN', 'success');
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Login exitoso',
                    'data' => [
                        'user' => [
                            'id' => $user['id'],
                            'nombre' => $user['nombre'],
                            'apellido' => $user['apellido'],
                            'email' => $user['email'],
                            'avatar' => $user['avatar'],
                            'puntos_recompensa' => $user['puntos_recompensa'],
                            'nivel_verificacion' => $user['nivel_verificacion'],
                            'biometric_enabled' => $user['biometric_enabled'],
                            'two_factor_enabled' => $user['two_factor_enabled'],
                            'tema_preferido' => $user['tema_preferido'],
                            'idioma_preferido' => $user['idioma_preferido']
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
                $fechaNacimiento = $input['fecha_nacimiento'] ?? '';
                $genero = $input['genero'] ?? '';
                $documentoIdentidad = $input['documento_identidad'] ?? '';
                $codigoReferido = $input['codigo_referido'] ?? '';
                
                if (empty($nombre) || empty($apellido) || empty($email) || empty($password)) {
                    throw new Exception('Todos los campos obligatorios son requeridos');
                }
                
                if (strlen($password) < 8) {
                    throw new Exception('La contraseña debe tener al menos 8 caracteres');
                }
                
                $conn = getDbConnection();
                
                // Verificar si el email ya existe
                $sql = "SELECT id FROM usuarios WHERE email = ?";
                $stmt = executeQuery($conn, $sql, [$email]);
                
                if (sqlsrv_fetch_array($stmt)) {
                    throw new Exception('El email ya está registrado');
                }
                
                // Verificar código de referido si se proporciona
                $referidoPorId = null;
                if (!empty($codigoReferido)) {
                    $sql = "SELECT id FROM usuarios WHERE codigo_referido = ?";
                    $stmt = executeQuery($conn, $sql, [$codigoReferido]);
                    $referido = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                    
                    if ($referido) {
                        $referidoPorId = $referido['id'];
                    }
                }
                
                // Crear usuario
                $passwordHash = hashPassword($password);
                $sql = "INSERT INTO usuarios (nombre, apellido, email, telefono, password_hash, fecha_nacimiento, 
                                            genero, documento_identidad, referido_por, ip_registro, dispositivo_registro) 
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
                
                $stmt = executeQuery($conn, $sql, [
                    $nombre, $apellido, $email, $telefono, $passwordHash, 
                    $fechaNacimiento ?: null, $genero ?: null, $documentoIdentidad ?: null,
                    $referidoPorId, $_SERVER['REMOTE_ADDR'], $_SERVER['HTTP_USER_AGENT']
                ]);
                
                // Obtener ID del usuario creado
                $sql = "SELECT SCOPE_IDENTITY() as id";
                $stmt = sqlsrv_query($conn, $sql);
                $result = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                $userId = $result['id'];
                
                // Generar código de referido
                $codigoReferidoUsuario = generateReferralCode($userId);
                $sql = "UPDATE usuarios SET codigo_referido = ? WHERE id = ?";
                executeQuery($conn, $sql, [$codigoReferidoUsuario, $userId]);
                
                // Crear cuenta principal
                $numeroCuenta = 'SKY' . str_pad($userId, 8, '0', STR_PAD_LEFT);
                $sql = "INSERT INTO cuentas (usuario_id, numero_cuenta, saldo) VALUES (?, ?, 100.00)";
                executeQuery($conn, $sql, [$userId, $numeroCuenta]);
                
                // Bonificación por registro
                $sql = "INSERT INTO recompensas (usuario_id, tipo, puntos, descripcion) 
                       VALUES (?, 'REGISTRO', 500, 'Bonificación por registro')";
                executeQuery($conn, $sql, [$userId]);
                
                // Actualizar puntos del usuario
                $sql = "UPDATE usuarios SET puntos_recompensa = 500 WHERE id = ?";
                executeQuery($conn, $sql, [$userId]);
                
                // Bonificación por referido
                if ($referidoPorId) {
                    $sql = "INSERT INTO recompensas (usuario_id, tipo, puntos, cashback, descripcion) 
                           VALUES (?, 'REFERIDO', 1000, 50.00, 'Bonificación por referir usuario')";
                    executeQuery($conn, $sql, [$referidoPorId]);
                    
                    $sql = "UPDATE usuarios SET puntos_recompensa = puntos_recompensa + 1000 WHERE id = ?";
                    executeQuery($conn, $sql, [$referidoPorId]);
                    
                    // Agregar saldo de bonificación
                    $sql = "UPDATE cuentas SET saldo = saldo + 50.00 WHERE usuario_id = ?";
                    executeQuery($conn, $sql, [$referidoPorId]);
                }
                
                // Crear notificaciones de bienvenida
                createNotification($userId, '¡Bienvenido a SkyPagos!', 
                                 'Tu cuenta ha sido creada exitosamente. Has recibido 500 puntos de bienvenida.', 
                                 'WELCOME', 'success');
                
                logSecurityEvent($userId, 'USER_REGISTERED', 'Usuario registrado exitosamente', 'BAJO');
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Usuario registrado exitosamente',
                    'data' => [
                        'user_id' => $userId,
                        'codigo_referido' => $codigoReferidoUsuario,
                        'puntos_bienvenida' => 500
                    ]
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'biometric_setup':
                $userId = $input['user_id'] ?? '';
                $enabled = $input['enabled'] ?? false;
                
                if (empty($userId)) {
                    throw new Exception('ID de usuario requerido');
                }
                
                $conn = getDbConnection();
                $sql = "UPDATE usuarios SET biometric_enabled = ? WHERE id = ?";
                executeQuery($conn, $sql, [$enabled ? 1 : 0, $userId]);
                
                logSecurityEvent($userId, 'BIOMETRIC_' . ($enabled ? 'ENABLED' : 'DISABLED'), 
                               'Autenticación biométrica ' . ($enabled ? 'activada' : 'desactivada'), 'BAJO');
                
                echo json_encode([
                    'success' => true,
                    'message' => 'Configuración biométrica actualizada'
                ]);
                
                closeDbConnection($conn);
                break;
                
            case 'forgot_password':
                $email = $input['email'] ?? '';
                
                if (empty($email)) {
                    throw new Exception('Email requerido');
                }
                
                $conn = getDbConnection();
                $sql = "SELECT id, nombre FROM usuarios WHERE email = ? AND activo = 1";
                $stmt = executeQuery($conn, $sql, [$email]);
                $user = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
                
                if ($user) {
                    // Generar código de recuperación
                    $resetCode = sprintf('%06d', mt_rand(100000, 999999));
                    
                    // Guardar código en configuración temporal (en producción usar tabla específica)
                    $sql = "INSERT INTO configuracion_avanzada (clave, valor, categoria, descripcion) 
                           VALUES (?, ?, 'TEMP', 'Código de recuperación de contraseña')";
                    executeQuery($conn, $sql, ["reset_code_{$user['id']}", $resetCode]);
                    
                    // Crear notificación
                    createNotification($user['id'], 'Recuperación de contraseña', 
                                     "Tu código de recuperación es: {$resetCode}", 'PASSWORD_RESET', 'warning');
                    
                    logSecurityEvent($user['id'], 'PASSWORD_RESET_REQUESTED', 'Solicitud de recuperación de contraseña', 'MEDIO');
                }
                
                // Siempre responder exitosamente por seguridad
                echo json_encode([
                    'success' => true,
                    'message' => 'Si el email existe, recibirás un código de recuperación'
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
