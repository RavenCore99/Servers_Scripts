@echo off
REM Portable: cualquier unidad/ruta (C:, E:, USB...). Siempre usa la carpeta del .cmd
cd /d "%~dp0"
echo [*] Iniciando desde: %CD%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar.ps1"
set ERR=%ERRORLEVEL%
if not %ERR%==0 (
  echo.
  echo [ERROR] Codigo %ERR%. Revisa el mensaje anterior.
  pause
)
exit /b %ERR%
