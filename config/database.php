<?php
// config/database.php

// Configuración para SQL Server
define('DB_HOST', '192.168.2.244');
define('DB_NAME', 'SkyPagos');
define('DB_USER', 'sa');
define('DB_PASS', 'Sky2022*!');
define('DB_PORT', 1433);
define('DB_CHARSET', 'UTF-8');

// Función para obtener la conexión a la base de datos
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

// Función para cerrar conexión (puedes usarla si quieres cerrar manualmente más adelante)
function closeDbConnection($conn) {
    if ($conn) {
        sqlsrv_close($conn);
    }
}

// Función para ejecutar consultas preparadas
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

// Headers para API
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// PROBAR CONEXIÓN AUTOMÁTICAMENTE
echo "<h2>Prueba de Conexión a la Base de Datos</h2>";
echo "<p><strong>Servidor:</strong> " . DB_HOST . ":" . DB_PORT . "</p>";
echo "<p><strong>Base de Datos:</strong> " . DB_NAME . "</p>";
echo "<p><strong>Usuario:</strong> " . DB_USER . "</p>";
echo "<hr>";

try {
    // Intentar conectar
    $conn = getDbConnection();
    
    // Si llegamos aquí, la conexión fue exitosa
    echo "<div style='color: green; font-size: 18px; font-weight: bold;'>";
    echo "✅ ¡CONEXIÓN EXITOSA!";
    echo "</div>";
    echo "<p>Te conectaste correctamente a la base de datos.</p>";
    
    // Información adicional del servidor
    $sql = "SELECT @@VERSION as version, DB_NAME() as current_database";
    $stmt = sqlsrv_query($conn, $sql);
    
    if ($stmt !== false) {
        $row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
        echo "<p><strong>Base de datos actual:</strong> " . $row['current_database'] . "</p>";
        echo "<p><strong>Versión del servidor:</strong> " . substr($row['version'], 0, 100) . "...</p>";
        sqlsrv_free_stmt($stmt);
    }
    
    // NO CERRAMOS LA CONEXIÓN AQUÍ para mantenerla abierta
    // closeDbConnection($conn);
    // echo "<p style='color: blue;'>Conexión cerrada correctamente.</p>";
    
} catch (Exception $e) {
    // Si hay error, mostrarlo
    echo "<div style='color: red; font-size: 18px; font-weight: bold;'>";
    echo "❌ ERROR DE CONEXIÓN";
    echo "</div>";
    echo "<p style='color: red;'>No se pudo conectar a la base de datos.</p>";
    echo "<p><strong>Error:</strong> " . $e->getMessage() . "</p>";
    
    // Sugerencias de solución
    echo "<h3>Posibles soluciones:</h3>";
    echo "<ul>";
    echo "<li>Verificar que SQL Server esté ejecutándose</li>";
    echo "<li>Comprobar la IP y puerto del servidor</li>";
    echo "<li>Verificar usuario y contraseña</li>";
    echo "<li>Revisar que la extensión sqlsrv esté habilitada en PHP</li>";
    echo "</ul>";
}
?>
