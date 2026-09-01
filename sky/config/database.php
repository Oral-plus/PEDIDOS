<?php

$__envFile = __DIR__ . '/.env';
if (is_file($__envFile)) {
    foreach (file($__envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $__line) {
        $__line = trim($__line);
        if ($__line === '' || $__line[0] === '#' || strpos($__line, '=') === false) continue;
        list($__k, $__v) = explode('=', $__line, 2);
        $__k = trim($__k);
        $__v = trim($__v, " \t\"'");
        if (getenv($__k) === false) putenv($__k . '=' . $__v);
    }
}
unset($__envFile, $__line, $__k, $__v);

define('DB_HOST', getenv('DB_SERVER') ?: '');
define('DB_NAME', getenv('DB_NAME') ?: 'SkyPagos1');
define('DB_USER', getenv('DB_USER') ?: '');
define('DB_PASS', getenv('DB_PASSWORD') ?: '');
define('DB_PORT', (int)(getenv('DB_PORT') ?: 1433));
define('DB_CHARSET', getenv('DB_CHARSET') ?: 'UTF-8');

if (DB_PASS === '') {
    throw new Exception('Falta el archivo .env con DB_PASSWORD junto a config/database.php');
}

function getDbConnection() {
    $connectionInfo = array(
        "Database" => DB_NAME,
        "UID" => DB_USER,
        "PWD" => DB_PASS,
        "CharacterSet" => DB_CHARSET,
        "TrustServerCertificate" => true,
        "Encrypt" => false
    );
    
    $conn = sqlsrv_connect(DB_HOST . ',' . DB_PORT, $connectionInfo);
    
    if ($conn === false) {
        throw new Exception("Error de conexión: " . print_r(sqlsrv_errors(), true));
    }
    
    return $conn;
}

function closeDbConnection($conn) {
    if ($conn) {
        sqlsrv_close($conn);
    }
}

function executeQuery($conn, $sql, $params = []) {
    $stmt = sqlsrv_prepare($conn, $sql, $params);
    
    if ($stmt === false) {
        throw new Exception("Error preparando consulta: " . print_r(sqlsrv_errors(), true));
    }
    
    if (sqlsrv_execute($stmt) === false) {
        throw new Exception("Error ejecutando consulta: " . print_r(sqlsrv_errors(), true));
    }
    
    return $stmt;
}

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

echo "<h2>Prueba de Conexión a la Base de Datos</h2>";
echo "<p><strong>Servidor:</strong> " . DB_HOST . ":" . DB_PORT . "</p>";
echo "<p><strong>Base de Datos:</strong> " . DB_NAME . "</p>";
echo "<p><strong>Usuario:</strong> " . DB_USER . "</p>";
echo "<hr>";

try {
    $conn = getDbConnection();
    
    echo "<div style='color: green; font-size: 18px; font-weight: bold;'>";
    echo "¡CONEXIÓN EXITOSA!";
    echo "</div>";
    echo "<p>Te conectaste correctamente a la base de datos.</p>";
    
    $sql = "SELECT @@VERSION as version, DB_NAME() as current_database";
    $stmt = sqlsrv_query($conn, $sql);
    
    if ($stmt !== false) {
        $row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
        echo "<p><strong>Base de datos actual:</strong> " . $row['current_database'] . "</p>";
        echo "<p><strong>Versión del servidor:</strong> " . substr($row['version'], 0, 100) . "...</p>";
        sqlsrv_free_stmt($stmt);
    }
    
    
} catch (Exception $e) {
    echo "<div style='color: red; font-size: 18px; font-weight: bold;'>";
    echo "ERROR DE CONEXIÓN";
    echo "</div>";
    echo "<p style='color: red;'>No se pudo conectar a la base de datos.</p>";
    echo "<p><strong>Error:</strong> " . $e->getMessage() . "</p>";
    
    echo "<h3>Posibles soluciones:</h3>";
    echo "<ul>";
    echo "<li>Verificar que SQL Server esté ejecutándose</li>";
    echo "<li>Comprobar la IP y puerto del servidor</li>";
    echo "<li>Verificar usuario y contraseña</li>";
    echo "<li>Revisar que la extensión sqlsrv esté habilitada en PHP</li>";
    echo "</ul>";
}
?>
