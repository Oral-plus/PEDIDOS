#!/bin/bash

echo "🚀 Instalador de SkyPagos"
echo "========================="

# Verificar Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js no está instalado"
    echo "📥 Descarga Node.js desde: https://nodejs.org/"
    exit 1
fi

# Verificar Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter no está instalado"
    echo "📥 Descarga Flutter desde: https://flutter.dev/"
    exit 1
fi

echo "✅ Node.js $(node --version) encontrado"
echo "✅ Flutter $(flutter --version | head -n 1) encontrado"

# Instalar dependencias del backend
echo ""
echo "📦 Instalando dependencias del backend..."
cd api
npm install

if [ $? -eq 0 ]; then
    echo "✅ Dependencias del backend instaladas"
else
    echo "❌ Error instalando dependencias del backend"
    exit 1
fi

# Instalar dependencias de Flutter
echo ""
echo "📦 Instalando dependencias de Flutter..."
cd ../flutter_app
flutter pub get

if [ $? -eq 0 ]; then
    echo "✅ Dependencias de Flutter instaladas"
else
    echo "❌ Error instalando dependencias de Flutter"
    exit 1
fi

echo ""
echo "🎉 ¡Instalación completada!"
echo ""
echo "📋 Próximos pasos:"
echo "1. Ejecutar los scripts SQL en SQL Server"
echo "2. Iniciar el backend: cd api && npm start"
echo "3. Ejecutar la app: cd flutter_app && flutter run"
echo ""
echo "📱 Datos de prueba:"
echo "   Teléfono: 70123456"
echo "   PIN: 1234"
