@echo off
rem Mantiene la API de PEDIDOS corriendo; si se cae, la reinicia a los 5s.
cd /d "%~dp0"
:loop
"C:\Program Files\nodejs\node.exe" server.js >> server.log 2>&1
timeout /t 5 /nobreak >nul
goto loop
