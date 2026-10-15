#requires -Version 5.1
# Compatibility entry point | RESCUSB | https://ragustingarcia.com/
param([ValidateSet('Menu','Auditar','Fuentes','Diagnostico','Vista')][string]$Modo='Menu',[switch]$PausaAlFinal)
& (Join-Path $PSScriptRoot 'RESCUSB.ps1') -Modo $Modo -PausaAlFinal:$PausaAlFinal
exit $LASTEXITCODE