@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
title RESCUSB
cd /d "%~dp0"
set "MODO=Menu"
if /i "%~1"=="/diagnostico" set "MODO=Diagnostico"
if /i "%~1"=="/fuentes" set "MODO=Fuentes"
if /i "%~1"=="/vista" set "MODO=Vista"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Lanzar-RESCUSB.ps1" -Modo "%MODO%"
exit /b %ERRORLEVEL%
