#requires -Version 5.1
# RESCUSB | Rodolfo Agustín García | https://ragustingarcia.com/
param([ValidateSet('Menu','Diagnostico','Fuentes','Vista')][string]$Modo='Menu')
$ErrorActionPreference='Stop'
try {
    $app=Join-Path $PSScriptRoot 'RESCUSB.ps1'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal $identity
    if($Modo -eq 'Menu' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        # Dispatch, then let the original BAT close. Only the elevated work window remains.
        $null=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$app+'"'),'-Modo',$Modo,'-PausaAlFinal') -PassThru
        exit 0
    }
    & $app -Modo $Modo -PausaAlFinal:($Modo -ne 'Vista')
    exit $LASTEXITCODE
} catch {
    Write-Host 'No se abrió RESCUSB. Windows necesita tu permiso de administrador para preparar el USB.' -ForegroundColor Yellow
    $null=Read-Host 'Enter para cerrar'
    exit 1
}
