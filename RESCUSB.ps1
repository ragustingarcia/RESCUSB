#requires -Version 5.1
# RESCUSB | Rodolfo Agustín García | https://ragustingarcia.com/
[CmdletBinding()]
param([ValidateSet('Menu','Auditar','Fuentes','Diagnostico','Vista')][string]$Modo='Menu',[switch]$PausaAlFinal)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
foreach($name in @('Rescate.Core.psm1','Rescusb.Microsoft.psm1','Rescusb.UI.psm1')){
    Import-Module (Join-Path $PSScriptRoot $name) -Force -DisableNameChecking
}
Initialize-RescusbTerminal -OwnWindow:($Modo -eq 'Menu')
$mutex=$null;$ownsMutex=$false;$exitCode=0;$fatal=$false
try {
    $catalog=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'catalogo.json') -Raw|ConvertFrom-Json
    Assert-Catalog $catalog
    $state=Join-Path $PSScriptRoot 'estado'
    $null=Assert-SafeDirectory $state
    $settings=Get-RescusbSettings $state $catalog
    if($Modo -eq 'Vista') {Write-RescusbMenu $settings}
    elseif($Modo -in @('Auditar','Diagnostico')) {
        Write-RescusbHeader
        Write-Host '  COMPROBACIÓN LOCAL | No se prepara ni borra ningún dispositivo.' -ForegroundColor Cyan
        $null=Get-CurlPath
        if(-not(Test-Path -LiteralPath $state)){$null=New-Item -ItemType Directory -Path $state}
        Save-JsonAtomic ([ordered]@{product='RESCUSB';date=(Get-Date).ToString('o');paths='OK';catalog='OK';curl='OK';diskWrites=$false}) (Join-Path $state 'diagnostico.json')
        Write-Host '  [OK] Programa, OneDrive, catálogo y guardado del estado local.' -ForegroundColor Green
        Show-UsbCandidates @(Get-UsbCandidates @(Get-DiskInventory))
        Write-Host '  Comprobación terminada. No se ejecutó Ventoy.' -ForegroundColor Gray
    } elseif($Modo -eq 'Fuentes') {
        Write-RescusbHeader
        if(-not(Test-Path -LiteralPath $state)){$null=New-Item -ItemType Directory -Path $state}
        Write-Host '  COMPROBANDO LAS FUENTES | Sin descargas de ISO ni borrado de USB.' -ForegroundColor Cyan
        $plan=Get-RescusbPreparedPlan $catalog $settings $state -IncludeVentoy
        Write-RescusbSourceHint $plan @($settings.images)
        Assert-RescusbPlanComplete $plan $settings.images
        Write-Host '  [OK] Todas las fuentes elegidas están disponibles, incluido Windows.' -ForegroundColor Green
    } else {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal $identity
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
            throw 'Abrí INICIAR.bat para que RESCUSB gestione el permiso de administrador.'
        }
        if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'RESCUSB requiere Windows x64 Intel/AMD.'}
        $mutex=New-Object Threading.Mutex($false,'Global\USBRescate64-Exclusive')
        $ownsMutex=$mutex.WaitOne(0)
        if(-not $ownsMutex){throw 'Hay otra sesión del preparador abierta. Cerrá la ventana anterior y volvé a iniciar RESCUSB.'}
        if(-not(Test-Path -LiteralPath $state)){$null=New-Item -ItemType Directory -Path $state}
        while($true){
            $settings=Get-RescusbSettings $state $catalog
            Write-RescusbMenu $settings
            $choice=(Read-Host '  ¿Qué querés hacer?').Trim()
            if($choice -in @('0','')){break}
            try {
                switch($choice){
                    {$_ -in @('1','2')} {
                        if($choice -eq '1'){Assert-NoVentoyProcess}
                        Write-RescusbHeader -Clear
                        Write-RescusbStep 1 'Elegir tu pendrive' 'Solo se muestran pendrives USB extraíbles compatibles. Dejalo conectado.'
                        $target=Select-Usb
                        $failed=Start-RescusbJob $catalog $settings $target $state -Resume:($choice -eq '2')
                        if($failed){$exitCode=2}else{$exitCode=0}
                    }
                    '3' {
                        Write-RescusbHeader -Clear
                        Write-Host '  COMPROBAR ANTES DE EMPEZAR | No se borra ni prepara el USB.' -ForegroundColor Cyan
                        $null=Get-CurlPath
                        Show-UsbCandidates @(Get-UsbCandidates @(Get-DiskInventory))
                        $plan=Get-RescusbPreparedPlan $catalog $settings $state -IncludeVentoy
                        Write-RescusbSourceHint $plan @($settings.images)
                        Assert-RescusbPlanComplete $plan $settings.images
                        Write-Host '  [OK] Fuentes disponibles. Podés volver al menú y preparar el pendrive.' -ForegroundColor Green
                    }
                    '4' {
                        Write-RescusbHeader -Clear
                        Write-Host '  AJUSTES | El paquete recomendado viene elegido por defecto.' -ForegroundColor Cyan
                        Write-Host '  [1] Idioma de Windows'
                        Write-Host '  [2] Elegir herramientas (opcional)'
                        Write-Host '  [3] Restablecer el paquete recomendado (sin Windows 10)'
                        Write-Host '  [0] Volver'
                        $option=Read-Host '  Elegir ajuste'
                        if($option -eq '1'){
                            Write-Host '  [1] Español  [2] Español (Latinoamérica)  [3] Inglés'
                            $lang=Read-Host '  Elegir idioma'
                            if($lang -notin @('1','2','3')){throw [OperationCanceledException]::new('Sin cambios.')}
                            $settings.language=@('Spanish','Spanish (Mexico)','English')[[int]$lang-1]
                        } elseif($option -eq '2'){
                            $n=0;foreach($item in $catalog.images){$n++;Write-Host ('  ['+$n+'] '+$item.name)}
                            $list=Read-Host '  Números separados por coma | Enter para incluir todas'
                            if(-not $list){$settings.images=@($catalog.images.id)}
                            else{
                                if($list -notmatch '^\s*[1-7](\s*,\s*[1-7])*\s*$'){throw 'Usá los números mostrados, separados por coma.'}
                                $settings.images=@($list.Split(',')|ForEach-Object {$catalog.images[[int]$_.Trim()-1].id}|Select-Object -Unique)
                            }
                        } elseif($option -eq '3'){$settings.images=@(Get-RescusbDefaultImages $catalog)}
                        else{throw [OperationCanceledException]::new('Sin cambios.')}
                        Save-JsonAtomic $settings (Join-Path $state 'configuracion.json')
                        Write-Host '  [OK] Ajustes guardados.' -ForegroundColor Green
                    }
                    '5' {Show-RescusbHelp $catalog}
                    default {Write-Host '  Elegí una opción del 0 al 5.' -ForegroundColor Yellow}
                }
            } catch [OperationCanceledException] {
                Write-Host '  Volvemos al menú. No se inició una preparación.' -ForegroundColor Gray
            } catch {
                $exitCode=1
                Write-Host ''
                Write-Host ('  [PENDIENTE] '+$_.Exception.Message) -ForegroundColor Yellow
                Save-JsonAtomic ([ordered]@{product='RESCUSB';date=(Get-Date).ToString('o');message=$_.Exception.Message}) (Join-Path $state 'ultimo-error.json')
            }
            $null=Read-Host '  Enter para volver al menú'
        }
    }
} catch {
    $fatal=$true;$exitCode=1
    Write-Host ('  [NO SE PUDO INICIAR] '+$_.Exception.Message) -ForegroundColor Yellow
} finally {
    if($ownsMutex){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
}
if($PausaAlFinal -and (($Modo -notin @('Menu','Vista')) -or $fatal)){$null=Read-Host '  Enter para cerrar RESCUSB'}
exit $exitCode
