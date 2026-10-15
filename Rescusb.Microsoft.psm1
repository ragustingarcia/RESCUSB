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
function Find-RescusbLocalWindows([string]$Id,[string]$Hash,[long]$Maximum,[string]$StateFolder,$Folders=$null) {
    if($null -eq $Folders){
        $Folders=@((Join-Path (Split-Path $StateFolder -Parent) 'ISO-OFICIALES'),(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))
        # The browser saves to the Downloads known folder, which can be moved to another drive.
        try {
            $known=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
            if($known){$Folders=@($Folders+[Environment]::ExpandEnvironmentVariables($known)|Select-Object -Unique)}
        } catch {}
    }
    $version=if($Id -eq 'windows10'){'10'}else{'11'}
    foreach($folder in $Folders){
        if(-not(Test-Path -LiteralPath $folder -PathType Container)){continue}
        $null=Assert-SafeDirectory $folder
        $candidates=@(Get-ChildItem -LiteralPath $folder -Filter '*.iso' -File|Where-Object {
            $_.Name -match ('(?i)^(?:Win|Windows)'+$version+'[_-]') -and $_.Length -gt 0 -and $_.Length -le $Maximum
        }|Sort-Object LastWriteTime -Descending|Select-Object -First 4)
        foreach($file in $candidates){
            $null=Assert-SafeDirectory $file.FullName
            Write-Host ('  [...] Verificando una ISO local | '+$file.Name) -ForegroundColor DarkGray
            if((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ieq $Hash){Assert-Iso $file.FullName;return $file.FullName}
        }
    }
    return ''
}
function Resolve-MicrosoftIso($Item,[string]$StateFolder,[ValidateSet('Spanish','Spanish (Mexico)','English')][string]$Language='Spanish') {
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
