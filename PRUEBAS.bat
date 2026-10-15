@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Probar.ps1"
set "RESULTADO=%ERRORLEVEL%"
if not "%RESULTADO%"=="0" goto fin
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Probar-Rescusb.ps1"
set "RESULTADO=%ERRORLEVEL%"
if not "%RESULTADO%"=="0" goto fin
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Probar-Revalidacion.ps1"
set "RESULTADO=%ERRORLEVEL%"
:fin
pause
exit /b %RESULTADO%
