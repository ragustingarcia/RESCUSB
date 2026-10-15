# RESCUSB | Rodolfo Agustin Garcia | https://ragustingarcia.com/
# Reads Microsoft's public download page and its normal anonymous session flow.
# Does not execute remote JavaScript, use third-party ISO hosts or bypass service refusals.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Invoke-MicrosoftRequest([string]$Url, $Session, [switch]$Json) {
    $u=Assert-Https $Url
    if($u.DnsSafeHost -notin @('www.microsoft.com','ov-df.microsoft.com')) {throw 'Servidor de metadatos Microsoft no autorizado.'}
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        $r=Invoke-WebRequest -Uri $Url -WebSession $Session -Headers @{Referer='https://www.microsoft.com/en-us/software-download/windows11'} -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30
        if([int]$r.StatusCode -ne 200){throw 'Respuesta HTTP inesperada.'}
        $text=[Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        if($text.Length -gt 4194304){throw 'Metadatos demasiado grandes.'}
    } catch {throw ('No se pudo consultar {0}. Comprueba Internet o reintenta mas tarde.' -f $u.DnsSafeHost)}
    if($Json){
        $data=$text|ConvertFrom-Json
        $errorProperty=$data.PSObject.Properties['Errors']
        if($errorProperty -and @($errorProperty.Value|Where-Object {$_}).Count -gt 0){
            throw 'Microsoft no autorizo esta descarga en esta sesion.'
        }
        return $data
    }
    return $text
}
function Get-MicrosoftEdition([string]$Html,[string]$Id) {
    $select=[regex]::Match($Html,'(?is)<select\b[^>]*\bid=["'']product-edition["''][^>]*>(.*?)</select>')
    $editions=@([regex]::Matches($select.Groups[1].Value,'(?is)<option\b[^>]*value=["''](\d+)["''][^>]*>(.*?)</option>'))
    $version=if($Id -eq 'windows10'){'10'}elseif($Id -eq 'windows11'){'11'}else{throw 'Windows no reconocido.'}
    $matches=@($editions|Where-Object {$_.Groups[2].Value -match ('Windows\s+'+$version+'\b') -and $_.Groups[2].Value -notmatch '(?i)ARM|Enterprise'})
    if($matches.Count -ne 1){throw 'Microsoft cambio el selector de ISO. No se elige una edicion por aproximacion.'}
    return $matches[0].Groups[1].Value
}
function Get-MicrosoftHash([string]$Html,[string]$Language) {
    $expected=$Language+' 64-bit';$hashes=@()
    foreach($row in [regex]::Matches($Html,'(?is)<tr\b[^>]*>(.*?)</tr>')){
        $cells=@([regex]::Matches($row.Groups[1].Value,'(?is)<td\b[^>]*>(.*?)</td>'))
        if($cells.Count -lt 2){continue}
        $label=[Net.WebUtility]::HtmlDecode(($cells[0].Groups[1].Value -replace '<[^>]+>',' ')) -replace '\s+',' '
        $value=[Net.WebUtility]::HtmlDecode(($cells[1].Groups[1].Value -replace '<[^>]+>','')).Trim()
        if($label.Trim() -ieq $expected -and $value -match '^[a-fA-F0-9]{64}$'){$hashes+=$value.ToLowerInvariant()}
    }
    $unique=@($hashes|Select-Object -Unique)
    if($unique.Count -ne 1){throw 'No se encontro un SHA-256 oficial unico para el idioma y la arquitectura elegidos.'}
    return $unique[0]
}
function Get-MicrosoftClientSettings([string]$Html,$Session) {
    $scripts=@([regex]::Matches($Html,'(?is)<script\b[^>]*\bsrc=["'']([^"'']+)["'']'))
    $urls=@($scripts|ForEach-Object {$_.Groups[1].Value}|Where-Object {$_ -match '^/foxtrot/.*?/sds/components/content/sdsbase/.*?/site\.[a-zA-Z0-9.]+\.js$'}|Select-Object -Unique)
    if($urls.Count -ne 1){throw 'No se pudo identificar el cliente oficial de Microsoft.'}
    $js=Invoke-MicrosoftRequest ('https://www.microsoft.com'+$urls[0]) $Session
    $profile=[regex]::Match($js,'profile(?:\\x3d|=)([a-fA-F0-9]{12})').Groups[1].Value
    $instance=[regex]::Match($js,'instanceId(?:\\x3d|=)([a-fA-F0-9-]{36})').Groups[1].Value
    if(-not $profile -or -not $instance){throw 'Microsoft cambio los metadatos de su cliente de descarga.'}
    return [pscustomobject]@{Profile=$profile;Instance=$instance}
}
function Initialize-MicrosoftSession($Settings,[string]$SessionId,$Session) {
    $text=Invoke-MicrosoftRequest ('https://ov-df.microsoft.com/mdt.js?instanceId='+$Settings.Instance+'&pageId=si&session_id='+$SessionId) $Session
    $w=[regex]::Match($text,'[?&]w=([A-Fa-f0-9]+)').Groups[1].Value
    $ticks=[regex]::Match($text,'rticks\s*=\s*"?\+?(\d+)').Groups[1].Value
    if(-not $w -or -not $ticks){throw 'No se pudo inicializar la sesion normal de Microsoft.'}
    $reply='https://ov-df.microsoft.com/?session_id='+$SessionId+'&CustomerId='+$Settings.Instance+'&PageId=si&w='+$w+'&mdt='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+'&rticks='+$ticks
    $null=Invoke-MicrosoftRequest $reply $Session
}
function Select-MicrosoftX64Link($Data,[string]$Language,[string]$Id) {
    $property=$Data.PSObject.Properties['ProductDownloadOptions']
    if(-not $property){throw 'Microsoft no devolvio enlaces de descarga.'}
    $options=@($property.Value|Where-Object { $_.DownloadType -eq 1 -and $_.Language -ceq $Language })
    if($options.Count -ne 1){throw 'No hay un enlace x64 unico para el idioma seleccionado.'}
    $u=Assert-MicrosoftUrl $options[0].Uri
    $file=[IO.Path]::GetFileName($u.AbsolutePath)
    $version=if($Id -eq 'windows10'){'10'}else{'11'}
    if($file -notmatch ('(?i)^(?:Win|Windows)'+$version+'_.*\.iso$') -or $file -notmatch '(?i)_x64(?=[_.v])' -or $file -notmatch '^[A-Za-z0-9_.-]+$'){
        throw ('La imagen devuelta no corresponde a Windows x64: '+$Id+' | '+$file)
    }
    return $options[0]
}
$script:RescusbHashCache=@{}
function Get-RescusbCachedHash($File) {
    # A 6 GB ISO takes a while to hash; Windows 10 and 11 may inspect the same file.
    $key=$File.FullName+'|'+$File.Length+'|'+$File.LastWriteTimeUtc.Ticks
    if(-not $script:RescusbHashCache.ContainsKey($key)){
        $script:RescusbHashCache[$key]=(Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $script:RescusbHashCache[$key]
}
function Get-RescusbIsoFolders([string]$StateFolder) {
    $folders=@((Join-Path (Split-Path $StateFolder -Parent) 'ISO-OFICIALES'),(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))
    # The browser saves to the Downloads known folder, which can be moved to another drive.
    try {
        $known=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if($known){$folders=@($folders+[Environment]::ExpandEnvironmentVariables($known)|Select-Object -Unique)}
    } catch {}
    return $folders
}
function Get-RescusbIsoCandidates($Folders,[string]$Pattern,[long]$Maximum) {
    foreach($folder in $Folders){
        if(-not(Test-Path -LiteralPath $folder -PathType Container)){continue}
        $null=Assert-SafeDirectory $folder
        Get-ChildItem -LiteralPath $folder -Filter '*.iso' -File|Where-Object {
            $_.Name -match $Pattern -and $_.Length -gt 0 -and $_.Length -le $Maximum
        }|Sort-Object LastWriteTime -Descending|Select-Object -First 4
    }
}
function Find-RescusbLocalWindows([string]$Id,[string]$Hash,[long]$Maximum,[string]$StateFolder,$Folders=$null) {
    if($null -eq $Folders){$Folders=Get-RescusbIsoFolders $StateFolder}
    $version=if($Id -eq 'windows10'){'10'}else{'11'}
    foreach($file in @(Get-RescusbIsoCandidates $Folders ('(?i)^(?:Win|Windows)'+$version+'[_-]') $Maximum)){
        $null=Assert-SafeDirectory $file.FullName
        Write-Host ('  [...] Verificando una ISO local | '+$file.Name) -ForegroundColor DarkGray
        if((Get-RescusbCachedHash $file) -ieq $Hash){Assert-Iso $file.FullName;return $file.FullName}
    }
    return ''
}
function Get-RescusbLanguageTag([string]$Language) {
    switch($Language){'Spanish'{'es-ES'} 'Spanish (Mexico)'{'es-MX'} 'English'{'en-US'} default{throw 'Idioma no admitido.'}}
}
function Assert-MicrosoftSignature([string]$Path) {
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    $subject=if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{''}
    if($signature.Status -ne 'Valid' -or $subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)'){
        throw ('Sin firma válida de Microsoft: '+[IO.Path]::GetFileName($Path))
    }
}
# Checks what DISM reports for the first image of install.esd / install.wim.
function Assert-RescusbWindowsImageInfo($Info,[string]$Id,[string]$Language) {
    if([int]$Info.Architecture -ne 9){throw 'La imagen no es x64.'}
    $tag=Get-RescusbLanguageTag $Language
    if(@($Info.Languages|Where-Object {$_ -ieq $tag}).Count -eq 0){throw ('La imagen no está en el idioma elegido ('+$tag+').')}
    $build=([version]$Info.Version).Build
    $isEleven=$build -ge 22000
    if(([version]$Info.Version).Major -ne 10 -or ($Id -eq 'windows11') -ne $isEleven){throw 'La ISO corresponde a otra versión de Windows.'}
}
# ISO generated by Microsoft's Media Creation Tool: it has no published hash, so its
# authenticity rests on Microsoft's signature on the installer and on DISM's image data.
function Test-RescusbMediaToolIso([string]$Path,[string]$Id,[string]$Language) {
    Assert-Iso $Path
    # Respect a mount the user already made in Explorer: reuse it and leave it mounted.
    $image=Get-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue
    $mountedHere=-not($image -and $image.Attached)
    if($mountedHere){$image=Mount-DiskImage -ImagePath $Path -Access ReadOnly -StorageType ISO -PassThru}
    try {
        $letter=$null
        for($i=0;$i -lt 20 -and -not $letter;$i++){
            $letter=($image|Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if(-not $letter){Start-Sleep -Milliseconds 500}
        }
        if(-not $letter){throw 'Windows no asignó una letra a la ISO montada.'}
        $root=[string]$letter+':\'
        foreach($file in @('setup.exe','sources\setup.exe')){
            $p=Join-Path $root $file
            if(-not(Test-Path -LiteralPath $p)){throw ('Falta '+$file+' en la ISO.')}
            Assert-MicrosoftSignature $p
        }
        $wim=@('sources\install.esd','sources\install.wim'|ForEach-Object {Join-Path $root $_}|Where-Object {Test-Path -LiteralPath $_})
        if($wim.Count -ne 1){throw 'La ISO no tiene una imagen de instalación reconocible.'}
        $first=@(Get-WindowsImage -ImagePath $wim[0])[0]
        $info=Get-WindowsImage -ImagePath $wim[0] -Index $first.ImageIndex
        Assert-RescusbWindowsImageInfo $info $Id $Language
    } finally {
        if($mountedHere){$null=Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue}
    }
}
function Find-RescusbMediaToolWindows($Item,[string]$Language,[string]$StateFolder,$Folders=$null) {
    if($null -eq $Folders){$Folders=Get-RescusbIsoFolders $StateFolder}
    foreach($file in @(Get-RescusbIsoCandidates $Folders '(?i)^Win' $Item.budgetBytes)){
        $null=Assert-SafeDirectory $file.FullName
        Write-Host ('  [...] Comprobando la firma de Microsoft | '+$file.Name) -ForegroundColor DarkGray
        try {Test-RescusbMediaToolIso $file.FullName $Item.id $Language}
        catch {Write-Host ('        No sirve: '+$_.Exception.Message) -ForegroundColor DarkGray;continue}
        $hash=Get-RescusbCachedHash $file
        $tag=Get-RescusbLanguageTag $Language
        $copy=$Item|ConvertTo-Json|ConvertFrom-Json
        $copy.sha256=$hash
        $copy.source='https://www.microsoft.com/software-download/'
        $copy.hashSource='Firma digital de Microsoft en setup.exe'
        $copy.file=$Item.id+'-herramienta-'+$tag+'-'+$hash.Substring(0,8)+'.iso'
        $copy.name=$(if($Item.id -eq 'windows10'){'Windows 10'}else{'Windows 11'})+' | '+$Language+' x64 | ISO de la herramienta de Microsoft'
        $copy|Add-Member -NotePropertyName verification -NotePropertyValue 'firma'
        $null=Assert-SafeDirectory $StateFolder
        if(-not(Test-Path -LiteralPath $StateFolder)){$null=New-Item -ItemType Directory -Path $StateFolder}
        Save-JsonAtomic ([ordered]@{sha256=$hash;source=$copy.source;file=$copy.file;name=$copy.name;language=$Language;verification='firma'}) (Join-Path $StateFolder ($Item.id+'.json'))
        return [pscustomobject]@{Item=$copy;LocalPath=$file.FullName}
    }
    return $null
}
function Get-RescusbMediaToolUrl([string]$Id) {
    if($Id -eq 'windows10'){return 'https://go.microsoft.com/fwlink/?LinkId=691209'}
    return 'https://go.microsoft.com/fwlink/?linkid=2156295'
}
# Downloads Microsoft's Media Creation Tool and runs it only if Microsoft signed it.
function Get-RescusbMediaTool([string]$Id,[string]$StateFolder) {
    $folder=Join-Path $StateFolder 'herramienta-microsoft'
    $null=Assert-SafeDirectory $folder
    if(-not(Test-Path -LiteralPath $folder)){$null=New-Item -ItemType Directory -Path $folder}
    $path=Join-Path $folder ('MediaCreationTool-'+$Id+'.exe')
    $null=Assert-SafeDirectory $path
    if(Test-Path -LiteralPath $path){
        try {Assert-MicrosoftSignature $path;return $path} catch {Remove-Item -LiteralPath $path}
    }
    Invoke-Transfer (Get-RescusbMediaToolUrl $Id) $path 104857600 -Quiet
    try {Assert-MicrosoftSignature $path} catch {Remove-Item -LiteralPath $path;throw}
    return $path
}
function Resolve-MicrosoftIso($Item,[string]$StateFolder,[ValidateSet('Spanish','Spanish (Mexico)','English')][string]$Language='Spanish') {
    # Published hash first (download or local copy). When Microsoft refuses the session,
    # an ISO built with its Media Creation Tool is accepted by signature instead.
    try {return (Resolve-MicrosoftOfficialIso $Item $StateFolder $Language)}
    catch {
        $official=$_
        $local=Find-RescusbMediaToolWindows $Item $Language $StateFolder
        if($local){return $local}
        throw $official
    }
}
function Resolve-MicrosoftOfficialIso($Item,[string]$StateFolder,[string]$Language) {
    $session=New-Object Microsoft.PowerShell.Commands.WebRequestSession
    # Microsoft serves the ISO page to non-Windows clients, as documented on that page.
    $session.UserAgent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36'
    $page='https://www.microsoft.com/en-us/software-download/'+$(if($Item.id -eq 'windows10'){'windows10ISO'}else{'windows11'})
    $html=Invoke-MicrosoftRequest $page $session
    $edition=Get-MicrosoftEdition $html $Item.id
    $hash=Get-MicrosoftHash $html $Language
    $local=Find-RescusbLocalWindows $Item.id $hash $Item.budgetBytes $StateFolder
    if($local){
        $copy=$Item|ConvertTo-Json|ConvertFrom-Json
        $copy.sha256=$hash;$copy.source=$page;$copy.hashSource=$page
        $copy.file=([IO.Path]::GetFileNameWithoutExtension($local))+'-'+$hash.Substring(0,8)+'.iso'
        $copy.name=$(if($Item.id -eq 'windows10'){'Windows 10'}else{'Windows 11'})+' | '+$Language+' x64 | ISO local verificada'
        $null=Assert-SafeDirectory $StateFolder
        if(-not(Test-Path -LiteralPath $StateFolder)){$null=New-Item -ItemType Directory -Path $StateFolder}
        Save-JsonAtomic ([ordered]@{sha256=$hash;source=$page;file=$copy.file;name=$copy.name;language=$Language}) (Join-Path $StateFolder ($Item.id+'.json'))
        return [pscustomobject]@{Item=$copy;LocalPath=$local}
    }
    $settings=Get-MicrosoftClientSettings $html $session
    $sessionId=[guid]::NewGuid().ToString()
    Initialize-MicrosoftSession $settings $sessionId $session
    $api='https://www.microsoft.com/software-download-connector/api/'
    $query='?profile='+$settings.Profile+'&productEditionId='+$edition+'&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID='+$sessionId
    $languages=Invoke-MicrosoftRequest ($api+'getskuinformationbyproductedition'+$query) $session -Json
    $property=$languages.PSObject.Properties['Skus']
    if(-not $property){throw 'Microsoft no devolvio idiomas.'}
    $skus=@($property.Value|Where-Object Language -CEQ $Language)
    if($skus.Count -ne 1 -or [string]$skus[0].Id -notmatch '^\d+$'){throw 'Idioma oficial no disponible o ambiguo.'}
    $query='?profile='+$settings.Profile+'&productEditionId=undefined&SKU='+$skus[0].Id+'&friendlyFileName=undefined&Locale=en-US&sessionID='+$sessionId
    $links=Invoke-MicrosoftRequest ($api+'GetProductDownloadLinksBySku'+$query) $session -Json
    $link=Select-MicrosoftX64Link $links $Language $Item.id
    $copy=$Item|ConvertTo-Json|ConvertFrom-Json
    $copy.url=$link.Uri;$copy.sha256=$hash
    # Version/content-specific filename keeps old completed and partial images intact.
    $name=[IO.Path]::GetFileNameWithoutExtension(([uri]$link.Uri).AbsolutePath)
    $copy.file=$name+'-'+$hash.Substring(0,8)+'.iso'
    $copy.name=$link.ProductDisplayName+' | '+$Language+' x64'
    $copy.source=$page;$copy.hashSource=$page
    $null=Assert-SafeDirectory $StateFolder
    if(-not(Test-Path -LiteralPath $StateFolder)){$null=New-Item -ItemType Directory -Path $StateFolder}
    # Persist the identity and expected hash only. Fresh signed URLs stay in memory.
    Save-JsonAtomic ([ordered]@{sha256=$hash;source=$page;file=$copy.file;name=$copy.name;language=$Language}) (Join-Path $StateFolder ($Item.id+'.json'))
    return [pscustomobject]@{Item=$copy;LocalPath=''}
}
Export-ModuleMember -Function *
