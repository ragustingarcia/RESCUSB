# RESCUSB | Rodolfo Agustin Garcia | https://ragustingarcia.com/
# Windows always comes from Microsoft's Media Creation Tool, verified by Microsoft's signature.
# An ISO that matches the SHA-256 published on Microsoft's page is reused first.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Invoke-MicrosoftRequest([string]$Url) {
    $u=Assert-Https $Url
    if($u.DnsSafeHost -ne 'www.microsoft.com') {throw 'Servidor de metadatos Microsoft no autorizado.'}
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        # Microsoft shows the hash table to any client; a non-Windows agent avoids the redirect to the tool.
        $r=Invoke-WebRequest -Uri $Url -UserAgent 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36' -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30
        if([int]$r.StatusCode -ne 200){throw 'Respuesta HTTP inesperada.'}
        $text=[Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        if($text.Length -gt 4194304){throw 'Metadatos demasiado grandes.'}
    } catch {throw ('No se pudo consultar {0}. Comprueba Internet o reintenta mas tarde.' -f $u.DnsSafeHost)}
    return $text
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
# Local ISO only: published hash first, then an ISO built by the Media Creation Tool.
# Returns $null when the ISO still has to be created with the tool.
function Resolve-MicrosoftIso($Item,[string]$StateFolder,[ValidateSet('Spanish','Spanish (Mexico)','English')][string]$Language='Spanish') {
    $page='https://www.microsoft.com/en-us/software-download/'+$(if($Item.id -eq 'windows10'){'windows10ISO'}else{'windows11'})
    $hash=''
    try {$hash=Get-MicrosoftHash (Invoke-MicrosoftRequest $page) $Language} catch {}
    if($hash){
        $local=Find-RescusbLocalWindows $Item.id $hash $Item.budgetBytes $StateFolder
        if($local){
            $copy=$Item|ConvertTo-Json|ConvertFrom-Json
            $copy.sha256=$hash;$copy.source=$page;$copy.hashSource=$page
            $copy.file=([IO.Path]::GetFileNameWithoutExtension($local))+'-'+$hash.Substring(0,8)+'.iso'
            $copy.name=$(if($Item.id -eq 'windows10'){'Windows 10'}else{'Windows 11'})+' | '+$Language+' x64 | ISO oficial verificada por hash'
            $null=Assert-SafeDirectory $StateFolder
            if(-not(Test-Path -LiteralPath $StateFolder)){$null=New-Item -ItemType Directory -Path $StateFolder}
            Save-JsonAtomic ([ordered]@{sha256=$hash;source=$page;file=$copy.file;name=$copy.name;language=$Language}) (Join-Path $StateFolder ($Item.id+'.json'))
            return [pscustomobject]@{Item=$copy;LocalPath=$local}
        }
    }
    return (Find-RescusbMediaToolWindows $Item $Language $StateFolder)
}
Export-ModuleMember -Function *