# RESCUSB | Rodolfo Agustin Garcia | https://ragustingarcia.com/
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-RescusbTerminal([switch]$OwnWindow) {
    try {
        $Host.UI.RawUI.WindowTitle='RESCUSB | Tu pendrive de rescate'
        $Host.UI.RawUI.BackgroundColor='Black';$Host.UI.RawUI.ForegroundColor='White'
        [Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
    } catch {}
    if(-not $OwnWindow){return}
    # Only in RESCUSB's own work window: never change a console the user brought.
    try {
        # A click in QuickEdit mode freezes the output ("Seleccionar") and a later resize reflows it.
        if(-not ('Rescusb.ConsoleMode' -as [type])){
            Add-Type -Namespace 'Rescusb' -Name 'ConsoleMode' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int handle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr handle, uint mode);
'@
        }
        $handle=[Rescusb.ConsoleMode]::GetStdHandle(-10);$mode=[uint32]0
        if([Rescusb.ConsoleMode]::GetConsoleMode($handle,[ref]$mode)){$null=[Rescusb.ConsoleMode]::SetConsoleMode($handle,(($mode -band (-bnot 0x40)) -bor 0x80))}
    } catch {}
    try {
        # A fixed, compact window keeps the 72-column layout composed instead of stretched.
        $raw=$Host.UI.RawUI;$max=$raw.MaxPhysicalWindowSize
        $width=[Math]::Min(90,$max.Width);$height=[Math]::Min(40,$max.Height)
        if($raw.WindowSize.Width -gt $width){$raw.WindowSize=New-Object Management.Automation.Host.Size($width,$raw.WindowSize.Height)}
        $raw.BufferSize=New-Object Management.Automation.Host.Size($width,9999)
        $raw.WindowSize=New-Object Management.Automation.Host.Size($width,$height)
    } catch {}
}
function Write-RescusbHeader([switch]$Clear) {
    if($Clear){Clear-Host}
    Write-Host ''
    Write-Host '  R E S C U S B' -ForegroundColor Cyan
    Write-Host '  Tu pendrive de rescate. Preparado para cuando algo falla.' -ForegroundColor White
    Write-Host '  Rodolfo Agustín García | ragustingarcia.com' -ForegroundColor DarkGray
    Write-Host ('  '+('-'*70)) -ForegroundColor DarkGray
}
function Write-RescusbMenu($Settings) {
    Write-RescusbHeader -Clear
    Write-Host '  Convierte tu pendrive de 64 GB en una caja de herramientas de rescate.'
    Write-Host '  Instala el arranque, descarga las imágenes oficiales y las verifica.'
    Write-Host '  Elegís el pendrive y confirmás. RESCUSB se encarga del resto.' -ForegroundColor Gray
    Write-Host ''
    $full=@($script:RescusbDefaultIds|Where-Object {$_ -notin $Settings.images}).Count -eq 0
    Write-Host $(if($full){'  [1] Armar mi pendrive completo'}else{'  [1] Armar mi pendrive con el contenido elegido'}) -ForegroundColor Cyan
    Write-Host ('      Primera vez | Prepara Ventoy y '+$Settings.images.Count+' herramientas. Borra el USB.') -ForegroundColor Gray
    Write-Host '  [2] Continuar o completar mi pendrive' -ForegroundColor Cyan
    Write-Host '      Retoma descargas y agrega lo que falta, conservando lo preparado.' -ForegroundColor Gray
    Write-Host '  [3] Comprobar que todo esté disponible' -ForegroundColor White
    Write-Host '      Revisa el pendrive y las fuentes oficiales. No borra ni instala.' -ForegroundColor Gray
    Write-Host '  [4] Ajustes y contenido' -ForegroundColor White
    Write-Host ('      Windows: '+(Get-RescusbLanguageLabel $Settings.language)+' x64 | '+$Settings.images.Count+' de 7 herramientas.') -ForegroundColor Gray
    Write-Host '  [5] Qué hace RESCUSB / Cómo usar el pendrive' -ForegroundColor White
    Write-Host '  [0] Salir' -ForegroundColor DarkGray
    Write-Host ''
}
function Write-RescusbStep([int]$Number,[string]$Title,[string]$Description='') {
    Write-Host ''
    Write-Host ('  ['+$Number+'/5] '+$Title) -ForegroundColor Cyan
    if($Description){Write-Host ('  '+$Description) -ForegroundColor Gray}
    Write-Host ''
}
function Get-RescusbLanguageLabel([string]$Language) {
    switch($Language){'Spanish'{'Español'} 'Spanish (Mexico)'{'Español (Latinoamérica)'} 'English'{'Inglés'} default{throw 'Idioma no admitido.'}}
}
# Windows 10 ended support on 14/10/2025: it stays available but is not chosen by default.
function Get-RescusbDefaultImages($Catalog) {return @($Catalog.images.id|Where-Object {$_ -ne 'windows10'})}
function Get-RescusbSettings([string]$StateFolder,$Catalog) {
    $script:RescusbDefaultIds=Get-RescusbDefaultImages $Catalog
    $settings=[pscustomobject]@{schema=1;language='Spanish';images=@(Get-RescusbDefaultImages $Catalog)}
    $path=Join-Path $StateFolder 'configuracion.json'
    if(Test-Path -LiteralPath $path){
        $null=Assert-SafeDirectory $path
        $settings=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($settings.schema -ne 1 -or $settings.language -notin @('Spanish','Spanish (Mexico)','English') -or
            @($settings.images).Count -eq 0 -or @($settings.images|Where-Object {$_ -notin $Catalog.images.id}).Count -or
            @($settings.images|Select-Object -Unique).Count -ne @($settings.images).Count){throw 'La configuración guardada no es válida.'}
    }
    return $settings
}
function Show-RescusbContents($Catalog,$Selected) {
    $purposes=@{
        systemrescue='Recuperar archivos y reparar particiones.'
        memtest='Comprobar la memoria RAM.'
        hirens='Herramientas de reparación en un entorno Windows PE.'
        rescuezilla='Crear y restaurar copias de discos.'
        ubuntu='Usar Linux sin instalarlo y acceder a tus archivos.'
        windows11='Reparar o reinstalar Windows 11.'
        windows10='Reparar o reinstalar Windows 10.'
    }
    foreach($i in $Catalog.images){
        $mark=if($i.id -in $Selected){'[+]'}else{'[ ]'}
        $short=switch($i.id){'systemrescue'{'SystemRescue'} 'memtest'{'Memtest86+'} 'hirens'{"Hiren's BootCD PE"} 'rescuezilla'{'Rescuezilla'} 'ubuntu'{'Ubuntu Live'} 'windows11'{'Windows 11'} 'windows10'{'Windows 10'}}
        Write-Host ('  '+$mark+' '+$short.PadRight(20)+$purposes[$i.id]) -ForegroundColor $(if($i.id -in $Selected){'White'}else{'DarkGray'})
    }
}
function Get-RescusbPreparedPlan($Catalog,$Settings,[string]$StateFolder,[string]$ImageFolder='',[switch]$IncludeVentoy) {
    $items=@{};$errors=@()
    if($IncludeVentoy){
        try{Test-OfficialChecksum $Catalog.ventoy;Write-Host '  [OK] Ventoy | Arranque BIOS y UEFI' -ForegroundColor Green}
        catch{$errors+=[pscustomobject]@{id='ventoy';message=$_.Exception.Message};Write-Host ('  [!] Ventoy | '+$_.Exception.Message) -ForegroundColor Yellow}
    }
    foreach($item in @($Catalog.images|Where-Object {$_.id -in $Settings.images})){
        try {
            if($item.kind -eq 'windows'){
                Write-Host ('  [...] Buscando la ISO de '+(Get-RescusbShortName $item.id)+' en Descargas e ISO-OFICIALES') -ForegroundColor DarkGray
                $win=$null
                if($ImageFolder){$win=Get-SavedWindowsItem $item $StateFolder $ImageFolder}
                # Reuse an existing Windows file only in the language chosen by the user.
                $meta=Join-Path $StateFolder ($item.id+'.json')
                if($win -and (Test-Path -LiteralPath $meta)){
                    $m=Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json
                    if(-not $m.PSObject.Properties['language'] -or $m.language -cne $Settings.language){$win=$null}
                }
                if(-not $win){$win=Get-WindowsItem $item $StateFolder $Settings.language}
                if(-not $win){
                    # Not an error: Windows is always created with Microsoft's tool.
                    Write-Host ('  [ ] '+(Get-RescusbShortName $item.id)+' | Se crea con la herramienta oficial de Microsoft.') -ForegroundColor Cyan
                    continue
                }
                $items[$item.id]=$win
                Write-Host ('  [OK] '+$win.Item.name) -ForegroundColor Green
            } else {
                Test-OfficialChecksum $item
                $items[$item.id]=[pscustomobject]@{Item=$item;LocalPath=''}
                Write-Host ('  [OK] '+$item.name) -ForegroundColor Green
            }
        } catch {
            $errors+=[pscustomobject]@{id=$item.id;message=$_.Exception.Message}
            Write-Host ('  [!] '+$item.id+' | '+$_.Exception.Message) -ForegroundColor Yellow
        }
    }
    return [pscustomobject]@{Items=$items;Errors=@($errors)}
}
function Assert-RescusbPlanComplete($Plan,$Selected) {
    if($Plan.Errors.Count -gt 0 -or @($Selected|Where-Object {-not $Plan.Items.ContainsKey($_)}).Count -gt 0){
        throw 'Todavía falta una fuente oficial. No se ha borrado ni preparado el pendrive. Reintentá desde el menú cuando la fuente esté disponible.'
    }
}
function Get-RescusbShortName([string]$Id) {
    switch($Id){'systemrescue'{'SystemRescue'} 'memtest'{'Memtest86+'} 'hirens'{"Hiren's BootCD PE"} 'rescuezilla'{'Rescuezilla'} 'ubuntu'{'Ubuntu Live'} 'windows11'{'Windows 11'} 'windows10'{'Windows 10'} default{$Id}}
}
# Windows is created with Microsoft's tool while preparing, so it never blocks a source check.
function Get-RescusbCheckedImages($Plan,$Selected) {
    return @($Selected|Where-Object {$Plan.Items.ContainsKey($_) -or $_ -notin @('windows11','windows10')})
}
function Write-RescusbSourceHint($Plan,$Selected) {
    $windows=@($Selected|Where-Object {$_ -in @('windows11','windows10') -and -not $Plan.Items.ContainsKey($_)})
    $missing=@($Selected|Where-Object {-not $Plan.Items.ContainsKey($_) -and $_ -notin $windows})
    if($windows.Count){
        Write-Host ''
        Write-Host '  Windows se crea con la herramienta oficial de Microsoft al armar el' -ForegroundColor Gray
        Write-Host '  pendrive. Suma de 20 minutos a más de una hora según tu conexión.' -ForegroundColor Gray
    }
    if($missing.Count -eq 0 -or @($Plan.Errors|Where-Object id -eq 'ventoy').Count){return}
    Write-Host ''
    Write-Host ('  Falta: '+(@($missing|ForEach-Object {Get-RescusbShortName $_}) -join ', ')+'.') -ForegroundColor Yellow
    Write-Host '  Al armar el pendrive, RESCUSB te ofrece preparar ahora lo disponible' -ForegroundColor Gray
    Write-Host '  y agregar lo que falta después con «Continuar».' -ForegroundColor Gray
}
# Decide what to prepare when some selected sources are unavailable.
# Returns the image ids to prepare now, 'retry' to check again, or throws to leave the USB untouched.
function Get-RescusbMediaToolLanguage([string]$Language) {
    switch($Language){'Spanish'{'Español (España, internacional)'} 'Spanish (Mexico)'{'Español (México)'} 'English'{'Inglés (Estados Unidos)'} default{throw 'Idioma no admitido.'}}
}
# Downloads Microsoft's tool, explains the four choices and waits until it closes.
function Invoke-RescusbMediaTool([string]$Id,[string]$StateFolder,[string]$Language) {
    $name=Get-RescusbShortName $Id
    Write-Host ''
    Write-Host ('  [...] Descargando la herramienta oficial de Microsoft para '+$name) -ForegroundColor DarkGray
    $tool=Get-RescusbMediaTool $Id $StateFolder
    Write-Host '  [OK] Herramienta descargada y firmada por Microsoft.' -ForegroundColor Green
    Write-Host ''
    Write-Host ('  EN LA HERRAMIENTA DE MICROSOFT | '+$name) -ForegroundColor Cyan
    Write-Host '  1. Aceptá los términos de Microsoft.'
    if($Id -eq 'windows10'){Write-Host '     Si pregunta qué querés hacer: «Crear medios de instalación».'}
    Write-Host ('  2. Idioma: '+(Get-RescusbMediaToolLanguage $Language)+' | Arquitectura: 64 bits (x64).')
    Write-Host '  3. Elegí «Archivo ISO». NO elijas «Unidad flash USB»: borraría el pendrive.' -ForegroundColor Yellow
    Write-Host '  4. Guardala en Descargas y esperá a que termine. Después cerrá la herramienta.'
    Write-Host ''
    Write-Host '  Tarda de 20 minutos a más de una hora. RESCUSB espera acá y después' -ForegroundColor Gray
    Write-Host '  comprueba la ISO sola: no cierres esta ventana.' -ForegroundColor Gray
    $process=Start-Process -FilePath $tool -PassThru
    $process.WaitForExit()
}
function Resolve-RescusbPlanGaps($Plan,$Selected,[string]$StateFolder='',[string]$Language='Spanish') {
    $missing=@($Selected|Where-Object {-not $Plan.Items.ContainsKey($_)})
    $ventoyFailed=@($Plan.Errors|Where-Object id -eq 'ventoy').Count -gt 0
    if($missing.Count -eq 0 -and -not $ventoyFailed){return ,@($Selected)}
    $available=@($Selected|Where-Object {$Plan.Items.ContainsKey($_)})
    if($ventoyFailed -or $available.Count -eq 0){Assert-RescusbPlanComplete $Plan $Selected}
    $windows=@($missing|Where-Object {$_ -in @('windows11','windows10')})
    $others=@($missing|Where-Object {$_ -notin $windows})
    Write-Host ''
    if($windows.Count){
        $names=@($windows|ForEach-Object {Get-RescusbShortName $_}) -join ' y '
        Write-Host ('  '+$names.ToUpper()+' SE CREA CON LA HERRAMIENTA OFICIAL DE MICROSOFT') -ForegroundColor Cyan
        Write-Host '  Microsoft no ofrece la ISO de Windows por descarga directa. RESCUSB baja' -ForegroundColor Gray
        Write-Host '  su herramienta oficial, la abre y después verifica la ISO que genera.' -ForegroundColor Gray
        Write-Host '  Tarda de 20 minutos a más de una hora según tu conexión (unos 7 GB).' -ForegroundColor Yellow
        Write-Host '  Podés seguir usando la PC mientras tanto.' -ForegroundColor Gray
    }
    if($others.Count){
        Write-Host ('  [!] No respondió: '+(@($others|ForEach-Object {Get-RescusbShortName $_}) -join ', ')+'.') -ForegroundColor Yellow
    }
    Write-Host '  Todavía no se borró ni se modificó el pendrive.' -ForegroundColor Gray
    Write-Host ''
    if($windows.Count){
        Write-Host '  [1] Crear la ISO de Windows ahora (recomendado)' -ForegroundColor Cyan
        Write-Host '      Enter también elige esta opción.' -ForegroundColor Gray
    }
    Write-Host ('  [2] Preparar ahora las '+$available.Count+' herramientas listas') -ForegroundColor White
    Write-Host '      Lo que falta queda pendiente. Se agrega después con «Continuar».' -ForegroundColor Gray
    if($others.Count){Write-Host '  [3] Volver a comprobar las fuentes' -ForegroundColor White}
    Write-Host '  [0] Volver al menú sin tocar el pendrive' -ForegroundColor DarkGray
    while($true){
        $answer=([string](Read-Host '  ¿Cómo seguimos?')).Trim()
        if(-not $answer -and $windows.Count){$answer='1'}
        switch($answer){
            {$_ -eq '1' -and $windows.Count} {
                try {
                    foreach($id in $windows){Invoke-RescusbMediaTool $id $StateFolder $Language}
                    return 'retry'
                } catch {Write-Host ('  [!] '+$_.Exception.Message) -ForegroundColor Yellow}
            }
            '2' {return ,$available}
            {$_ -eq '3' -and $others.Count} {return 'retry'}
            '0' {throw [OperationCanceledException]::new('Todavía falta una fuente oficial. No se borró ni preparó el pendrive.')}
            default {Write-Host '  Elegí una de las opciones mostradas.' -ForegroundColor Yellow}
        }
    }
}
# Creating Windows can take an hour: if the pendrive vanished meanwhile, ask to plug it
# back in and recognise it by its identity instead of sending the user back to the menu.
function Wait-RescusbTarget($Target) {
    while($true){
        try {return (Assert-Target $Target)}
        catch {if($_.Exception.Message -notlike '*ya no esta conectado*'){throw}}
        Write-Host ''
        Write-Host '  [!] Windows dejó de ver el pendrive.' -ForegroundColor Yellow
        Write-Host '      Puede haberse desconectado o suspendido mientras se creaba Windows.' -ForegroundColor Gray
        Write-Host '      Desconectalo, volvé a conectarlo y esperá a que Windows lo muestre.' -ForegroundColor Gray
        Write-Host '      Todavía no se borró nada y lo ya verificado se conserva.' -ForegroundColor Gray
        $answer=([string](Read-Host '  Enter cuando esté conectado | 0 para volver al menú')).Trim()
        if($answer -eq '0'){throw [OperationCanceledException]::new('El pendrive no está conectado. No se borró nada.')}
        $found=Find-ReconnectedTarget $Target @(Get-DiskInventory)
        if($found){
            Write-Host '  [OK] Pendrive reconocido: es el mismo, por modelo, serie e identificador.' -ForegroundColor Green
            $Target=$found
        } else {
            Write-Host '  Todavía no aparece el mismo pendrive. Probá con otro puerto USB.' -ForegroundColor Yellow
        }
    }
}
function Start-RescusbJob($Catalog,$Settings,$Target,[string]$StateFolder,[switch]$Resume) {
    $root=''
    if($Resume){
        $root=Get-UsbRoot $Target
        $markerPath=Join-Path $root 'usb-rescate-identidad.json'
        $null=Assert-SafeDirectory $markerPath
        if(-not(Test-Path -LiteralPath $markerPath)){throw 'Este pendrive no fue preparado por RESCUSB. Para crearlo por primera vez, usá la opción 1.'}
        $marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json
        if($marker.schema -ne 1){throw 'La identificación guardada del USB no es válida.'}
        Assert-DiskIdentity $marker.identity $Target -Renumbered
    }
    Write-RescusbStep 2 'Revisando las herramientas' 'Se comprueban las fuentes antes de cambiar nada en el USB.'
    $folder=if($root){Join-Path $root 'ISO'}else{''}
    while($true){
        $plan=Get-RescusbPreparedPlan $Catalog $Settings $StateFolder $folder -IncludeVentoy:(-not $Resume)
        $now=Resolve-RescusbPlanGaps $plan @($Settings.images) $StateFolder $Settings.language
        if($now -is [string] -and $now -eq 'retry'){Write-Host '';continue}
        break
    }
    $now=@($now)
    $pendingIds=@($Settings.images|Where-Object {$_ -notin $now})
    $Target=Wait-RescusbTarget $Target
    Write-Host ''
    Show-RescusbContents $Catalog $now
    Write-Host ('  Windows: '+(Get-RescusbLanguageLabel $Settings.language)+' | x64 | Edición oficial de consumo.') -ForegroundColor Gray
    if(-not $Resume){
        Write-RescusbStep 3 'Confirmar el pendrive' 'Solo después de tu confirmación se borrará el dispositivo mostrado.'
        $installed=Install-Ventoy $Target $Catalog.ventoy $StateFolder
        $Target=$installed.Target;$root=$installed.Root
        $marker=[ordered]@{schema=1;product='RESCUSB';version='2.1.0';created=(Get-Date).ToString('o');identity=$Target;ventoy=$Catalog.ventoy.sha256}
        $null=Assert-Target $Target
        Save-JsonAtomic $marker (Join-Path $root 'usb-rescate-identidad.json')
        Save-JsonAtomic $marker (Join-Path $StateFolder 'ultimo-usb.json')
    } else {Write-RescusbStep 3 'Pendrive reconocido' 'Se conserva Ventoy y se completa el contenido elegido.'}
    Write-RescusbStep 4 'Preparando tu caja de herramientas' 'Descargas reanudables directamente al USB. Cada imagen se verifica antes de habilitarse.'
    $pending=[ordered]@{product='RESCUSB';version='2.1.0';date=(Get-Date).ToString('o');complete=$false;state='preparando';selected=@($Settings.images);pending=$pendingIds;author='Rodolfo Agustín García';authorUrl='https://ragustingarcia.com/';bootTested=$false}
    $null=Assert-Target $Target
    Save-JsonAtomic $pending (Join-Path $root 'RESCUSB-ESTADO.json')
    Save-JsonAtomic $pending (Join-Path $StateFolder 'ultimo-resultado.json')
    $failures=Invoke-ImagePlan $Catalog $Target $root $now $StateFolder $plan.Items
    Write-RescusbStep 5 'Resultado'
    # Skipped sources count as missing: a pendrive without them is never marked LISTO.
    $missing=$failures+$pendingIds.Count
    $complete=($missing -eq 0)
    $status=[ordered]@{product='RESCUSB';version='2.1.0';date=(Get-Date).ToString('o');complete=$complete;selected=@($Settings.images);pending=$pendingIds;failures=$missing;author='Rodolfo Agustín García';authorUrl='https://ragustingarcia.com/';bootTested=$false}
    $null=Assert-Target $Target
    Save-JsonAtomic $status (Join-Path $root 'RESCUSB-ESTADO.json')
    Save-JsonAtomic $status (Join-Path $StateFolder 'ultimo-resultado.json')
    $guide=Join-Path $root 'RESCUSB-LEEME.txt'
    $null=Assert-SafeDirectory $guide
    $text="RESCUSB | Rodolfo Agustín García | https://ragustingarcia.com/`r`n`r`nPreparación completa: $complete`r`nPendiente: $(if($pendingIds.Count){$pendingIds -join ', '}else{'nada'})`r`nExpulsá el USB y elegilo desde el menú de arranque del equipo.`r`nLas imágenes están en ISO. El resultado está en informe-rescate.json y RESCUSB-ESTADO.json.`r`nLas herramientas pertenecen a sus respectivos proyectos.`r`nSi falta contenido, abrí INICIAR.bat en el PC y elegí Continuar.`r`n"
    [IO.File]::WriteAllText($guide,$text,(New-Object Text.UTF8Encoding($true)))
    if($complete){
        Write-Host ('  [LISTO] '+$Settings.images.Count+' de '+$Settings.images.Count+' herramientas preparadas y verificadas.') -ForegroundColor Green
        Write-Host '  Expulsá el USB desde Windows y elegilo en el menú de arranque del equipo.'
        Write-Host '  Tu pendrive ya contiene el arranque y las imágenes seleccionadas.' -ForegroundColor Gray
    } else {
        Write-Host '  [PENDIENTE] La preparación quedó incompleta.' -ForegroundColor Yellow
        if($pendingIds.Count){
            Write-Host ('  Quedó para después: '+(@($pendingIds|ForEach-Object {Get-RescusbShortName $_}) -join ', ')+'.') -ForegroundColor Yellow
            Write-Host '  Lo preparado ya arranca. Cuando la fuente esté disponible, elegí «Continuar».' -ForegroundColor Gray
        }
        Write-Host '  Conservá el pendrive y usá «Continuar» para retomar lo que falta.'
    }
    return $missing
}
function Show-RescusbHelp($Catalog) {
    Write-RescusbHeader -Clear
    Write-Host '  UNA CAJA DE HERRAMIENTAS QUE ARRANCA DESDE TU USB' -ForegroundColor Cyan
    Write-Host ''
    Show-RescusbContents $Catalog @(Get-RescusbDefaultImages $Catalog)
    Write-Host ''
    Write-Host '  Cómo funciona'
    Write-Host '  1. Elegís tu pendrive. Los discos internos nunca aparecen.' -ForegroundColor Gray
    Write-Host '  2. RESCUSB consulta las fuentes y obtiene enlaces y hashes oficiales.' -ForegroundColor Gray
    Write-Host '  3. Confirmás el borrado de ESE pendrive escribiendo su serie.' -ForegroundColor Gray
    Write-Host '  4. Se instala Ventoy y se descargan/verifican las herramientas.' -ForegroundColor Gray
    Write-Host '  5. Expulsás el USB. Al reiniciar, lo elegís desde el menú de arranque.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Dejá el pendrive conectado durante todo el proceso.' -ForegroundColor Cyan
    Write-Host '  No se exige desconectarlo: su identidad se vuelve a comprobar automáticamente.' -ForegroundColor Gray
    Write-Host '  Windows se prepara en español y x64 por defecto. El idioma se cambia en Ajustes.' -ForegroundColor Gray
    Write-Host '  Windows 10 ya no tiene soporte de Microsoft: se agrega desde Ajustes.' -ForegroundColor Gray
    Write-Host '  Windows se crea con la herramienta oficial de Microsoft: suma 20-60 minutos.' -ForegroundColor Gray
    Write-Host '  Las ISO de Windows permiten reparar o instalar; no son un Windows portátil.' -ForegroundColor Gray
    Write-Host '  Secure Boot y el arranque de cada imagen dependen del firmware y del equipo.' -ForegroundColor Gray
    Write-Host '  No se cambian claves del firmware, licencias ni opciones del BIOS.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Autoría y documentación | ragustingarcia.com | LEEME.md' -ForegroundColor DarkGray
}
Export-ModuleMember -Function *
