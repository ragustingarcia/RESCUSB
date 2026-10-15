# RESCUSB | Rodolfo Agustin Garcia | https://ragustingarcia.com/
# Requires Windows PowerShell 5.1. No action on import. Disk writes require explicit user confirmation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Https([string]$Url) {
    $u = $null
    if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'https' -or
        $u.UserInfo -or $u.Port -ne 443 -or $Url -match '[\r\n]') { throw 'URL HTTPS invalida.' }
    return $u
}
function Assert-MicrosoftUrl([string]$Url) {
    $u = Assert-Https $Url
    # Exact names, never substring/suffix matching and never arbitrary aka.ms links.
    if ($u.DnsSafeHost -notin @('software.download.prss.microsoft.com','software-static.download.prss.microsoft.com','software-download.microsoft.com','download.microsoft.com')) {
        throw 'El enlace no pertenece a un servidor de descarga Microsoft autorizado.'
    }
    if ($u.AbsolutePath -notmatch '(?i)\.iso$') { throw 'El enlace Microsoft debe apuntar a una ISO.' }
    return $u
}
function Get-CurlPath {
    # Fixed Windows binary: do not execute a curl.exe planted next to this program.
    $path = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Falta curl.exe de Windows. Se requiere Windows 10/11 actualizado.' }
    $header = @(& $path '-q' '--version')[0]
    Assert-CurlVersion $header
    return $path
}
function Assert-CurlVersion([string]$Header) {
    if ($Header -notmatch '^curl (\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'8.4.0') {
        throw 'Se requiere curl 8.4.0 o posterior para limitar descargas sin Content-Length. Actualice Windows; no se instalara nada automaticamente.'
    }
}
function Assert-NoVentoyProcess {
    if (@(Get-Process -Name 'Ventoy2Disk*' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Ya hay un proceso Ventoy2Disk activo. Espere su finalizacion antes de preparar otro USB.'
    }
}
function Invoke-Transfer([string]$Url, [string]$Destination, [long]$Maximum, [switch]$Resume, [switch]$Microsoft, [switch]$Quiet) {
    $null = Assert-Https $Url
    if ($Microsoft) { $null = Assert-MicrosoftUrl $Url }
    # Small metadata reads stay silent; only real image downloads draw a progress bar.
    $progress = if ($Quiet) { '--silent' } else { '--progress-bar' }
    $argsList = @('-q','--globoff','--fail','--show-error',$progress,'--proto','=https','--proto-redir','=https',
        '--connect-timeout','30','--speed-time','120','--speed-limit','1024','--retry','3','--retry-delay','3',
        '--max-filesize', [string]$Maximum, '--output', $Destination)
    # Microsoft: no redirects at all. A changed host must be reviewed via a fresh official link.
    if ($Microsoft) { $argsList += @('--max-redirs','0') } else { $argsList += @('--location','--max-redirs','8') }
    if ($Resume) { $argsList += @('--continue-at','-') }
    $argsList += @('--write-out','%{http_code}','--url',$Url)
    $httpStatus = & (Get-CurlPath) @argsList
    $code = $LASTEXITCODE
    if ($code -ne 0 -or [string]$httpStatus -notin @('200','206')) {
        throw "Descarga incompleta (curl $code). Se conserva .part. Si 33/416: el servidor no permite reanudar; revise LEEME. Si 22: enlace vencido/no disponible."
    }
    # Reject 3xx even when curl considers them successful; Microsoft URLs cannot redirect.
}
function Get-OfficialText([string]$Url) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('usb-source-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        Invoke-Transfer $Url $tmp 4194304 -Quiet
        return [IO.File]::ReadAllText($tmp)
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp } }
}
function Get-ChecksumFromText([string]$Text, [string]$File) {
    $found = @()
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*([a-fA-F0-9]{64})\s+\*?(.+?)\s*$') {
            $hash = $Matches[1]; $name = ($Matches[2] -replace '\\','/').Split('/')[-1]
            if ($name -ceq $File) { $found += $hash.ToLowerInvariant() }
        }
    }
    $unique = @($found | Select-Object -Unique)
    if ($unique.Count -ne 1) { throw "Checksum oficial ausente o ambiguo para $File." }
    return $unique[0]
}
function Assert-Catalog($Catalog) {
    if ($Catalog.schema -ne 1 -or $Catalog.reserveBytes -lt 1GB) { throw 'Catalogo no valido.' }
    $ids = @(); $files = @()
    foreach ($i in @($Catalog.ventoy) + @($Catalog.images)) {
        if ($i.id -notmatch '^[a-z0-9]+$' -or $i.id -in $ids -or $i.file -in $files -or
            $i.file -notmatch '^[a-zA-Z0-9_.-]+$' -or $i.file -match '\.\.' -or
            $i.budgetBytes -le 0 -or $i.exactBytes -lt 0 -or $i.exactBytes -gt $i.budgetBytes) { throw 'Entrada de catalogo invalida.' }
        $ids += $i.id; $files += $i.file
        $null = Assert-Https $i.source; $null = Assert-Https $i.hashSource
        if ($i.kind -eq 'windows') {
            if ($i.id -notin @('windows10','windows11') -or $i.url -or $i.sha256) { throw 'Windows no debe incluir enlaces temporales ni hashes genericos.' }
        } else {
            $null = Assert-Https $i.url
            if ($i.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Falta SHA-256 fijado.' }
        }
    }
}
function Test-OfficialChecksum($Item) {
    $text = Get-OfficialText $Item.hashSource
    if ($Item.id -eq 'hirens') {
        $plain = [Net.WebUtility]::HtmlDecode(($text -replace '<[^>]+>',' '))
        $m = [regex]::Match($plain, '(?is)ISO SHA-256\s+([a-f0-9]{64})(?:\s|$)')
        if (-not $m.Success) { throw 'No se pudo leer el SHA-256 oficial de Hiren.' }
        $actual = $m.Groups[1].Value
    } else { $actual = Get-ChecksumFromText $text $Item.file }
    if ($actual -ine $Item.sha256) { throw "El checksum publicado cambio: $($Item.name). Actualice el catalogo revisando la fuente oficial." }
}
function Assert-FileHash([string]$Path, [string]$Expected) {
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'SHA-256 esperado invalido.' }
    Write-Host ('  [...] Comprobando integridad | '+[IO.Path]::GetFileName($Path)) -ForegroundColor DarkGray
    $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($h -ine $Expected) { throw "SHA-256 incorrecto: $([IO.Path]::GetFileName($Path)). No se habilita para arranque." }
    return $h
}
function Move-InvalidImage([string]$Path, [scriptblock]$Guard) {
    & $Guard
    Move-Item -LiteralPath $Path -Destination ($Path+'.invalid-'+[guid]::NewGuid().ToString('N')+'.part')
}
function Assert-Iso([string]$Path) {
    # ISO9660 or complete ECMA-167 UDF volume recognition sequence.
    $stream = [IO.File]::OpenRead($Path)
    try {
        $ok = $false; $buf = New-Object byte[] 5;$udfBegin=$false;$udfNsr=$false
        for ($s=16; $s -lt 64; $s++) {
            $null = $stream.Seek(($s * 2048 + 1), [IO.SeekOrigin]::Begin)
            if($stream.Read($buf,0,5) -ne 5){continue}
            $tag=[Text.Encoding]::ASCII.GetString($buf)
            if($tag -ceq 'CD001'){$ok=$true;break}
            if($tag -ceq 'BEA01'){$udfBegin=$true;$udfNsr=$false}
            elseif($udfBegin -and $tag -cin @('NSR02','NSR03')){$udfNsr=$true}
            elseif($tag -ceq 'TEA01' -and $udfBegin -and $udfNsr){$ok=$true;break}
        }
        if (-not $ok) { throw 'El archivo no tiene una estructura ISO9660/UDF reconocible.' }
    } finally { $stream.Dispose() }
}
function Test-DiskEligible($D) {
    if ($D.BusType -ne 'USB' -or -not $D.UsbEvidence) { return 'No hay doble evidencia USB.' }
    if (-not $D.RemovableMedia) { return 'Windows no lo identifica como medio extraible; se excluyen discos USB fijos.' }
    if ($D.Number -eq 0 -or $D.IsBoot -or $D.IsSystem -or $D.Protected) { return 'Disco 0, sistema, arranque, paginacion o ubicacion del programa.' }
    if ($D.IsOffline -or $D.IsReadOnly -or $D.HealthStatus -ne 'Healthy') { return 'Disco desconectado, solo lectura o estado no saludable.' }
    if ($D.Size -lt 48000000000 -or $D.Size -gt 72000000000) { return 'Fuera del rango conservador de un USB de 64 GB (48-72 GB decimales).' }
    foreach ($v in @($D.Serial,$D.WmiSerial,$D.UniqueId,$D.PnpId,$D.Path)) {
        if ([string]::IsNullOrWhiteSpace([string]$v)) { return 'Identidad incompleta; se rechaza por seguridad.' }
    }
    $visibleSerial=ConvertTo-DisplaySerial $D.Serial; $visibleWmiSerial=ConvertTo-DisplaySerial $D.WmiSerial
    if (-not $visibleSerial -or -not $visibleWmiSerial -or $visibleSerial -match '^(0+|unknown|none|n/a)$' -or $visibleWmiSerial -match '^(0+|unknown|none|n/a)$') { return 'Numero de serie no fiable.' }
    return ''
}
function Get-DiskInventory {
    $wmis = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)
    $partitions = @(Get-Partition -ErrorAction Stop)
    $protectedLetters = @($env:SystemDrive.TrimEnd(':'))
    $protectedLetters += @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | ForEach-Object { $_.Name.Substring(0,1) })
    $protectedLetters += @([IO.Path]::GetPathRoot($PSScriptRoot).TrimEnd('\',':'))
    $protectedLetters += @([IO.Path]::GetPathRoot((Get-Location).Path).TrimEnd('\',':'))
    foreach ($d in @(Get-Disk -ErrorAction Stop)) {
        $w = @($wmis | Where-Object { $_.Index -eq $d.Number })
        if ($w.Count -ne 1) { throw 'Inventario de almacenamiento ambiguo.' }
        $parts = @($partitions | Where-Object DiskNumber -eq $d.Number)
        $prot = @($parts | Where-Object { $_.IsBoot -or $_.IsSystem -or ($_.DriveLetter -and [string]$_.DriveLetter -in $protectedLetters) }).Count -gt 0
        [pscustomobject]@{
            Number=[int]$d.Number; Model=[string]$w[0].Model; Size=[long]$d.Size; BusType=[string]$d.BusType
            Serial=([string]$d.SerialNumber).Trim(); WmiSerial=([string]$w[0].SerialNumber).Trim()
            UniqueId=([string]$d.UniqueId).Trim(); PnpId=[string]$w[0].PNPDeviceID; Path=[string]$d.Path
            UsbEvidence=($w[0].InterfaceType -eq 'USB' -or $w[0].PNPDeviceID -match '^USB(STOR)?\\')
            RemovableMedia=([string]$w[0].MediaType -eq 'Removable Media' -and @( $w[0].Capabilities ) -contains 7)
            IsBoot=[bool]$d.IsBoot; IsSystem=[bool]$d.IsSystem; Protected=$prot
            IsOffline=[bool]$d.IsOffline; IsReadOnly=[bool]$d.IsReadOnly; HealthStatus=[string]$d.HealthStatus
            Letters=(@($parts | Where-Object DriveLetter | ForEach-Object { [string]$_.DriveLetter }) -join ',')
        }
    }
}
function Assert-DiskIdentity($Expected, $Actual, [switch]$PartitionChanged, [switch]$Renumbered) {
    $reason = Test-DiskEligible $Actual
    if ($reason) { throw "USB rechazado: $reason" }
    $keys = @('Model','Size','Serial','WmiSerial','PnpId','Path')
    if (-not $Renumbered) { $keys += 'Number' }
    if (-not $PartitionChanged) { $keys += 'UniqueId' }
    foreach ($key in $keys) { if ([string]$Actual.$key -cne [string]$Expected.$key) { throw "Cambio la identidad del dispositivo ($key). Operacion detenida." } }
}
function Assert-UniqueIdentity($Target, $Inventory) {
    foreach ($key in @('Serial','WmiSerial','UniqueId','PnpId','Path')) {
        if (@($Inventory | Where-Object { $_.$key -eq $Target.$key }).Count -ne 1) { throw "Identidad duplicada ($key). No se utiliza este USB." }
    }
}
function Assert-Target($Expected, [switch]$PartitionChanged) {
    $all = @(Get-DiskInventory)
    $current = @($all | Where-Object Number -eq $Expected.Number)
    if ($current.Count -ne 1) { throw 'El USB elegido ya no esta conectado.' }
    Assert-DiskIdentity $Expected $current[0] -PartitionChanged:$PartitionChanged
    Assert-UniqueIdentity $current[0] $all
    return $current[0]
}
function Get-UsbCandidates($Inventory) {
    foreach ($d in $Inventory) {
        if (Test-DiskEligible $d) { continue }
        try { Assert-UniqueIdentity $d $Inventory }
        catch { continue }
        $d
    }
}
function Show-UsbCandidates($Candidates) {
    if (-not $Candidates) {
        Write-Host 'No hay pendrives extraibles de 64 GB compatibles. Conecte el pendrive y vuelva a intentar.' -ForegroundColor Yellow
        return
    }
    Write-Host 'PENDRIVES DISPONIBLES:' -ForegroundColor Cyan
    $position=0
    foreach ($d in $Candidates) {
        $position++
        Write-Host ("  [{0}] {1}" -f $position,$d.Model) -ForegroundColor White
        Write-Host ("      {0:N2} GB | Unidad {1}: | Serie {2}" -f
            ($d.Size/1e9),$d.Letters,(ConvertTo-DisplaySerial $d.Serial)) -ForegroundColor Gray
    }
}
function Select-Usb {
    $all = @(Get-DiskInventory)
    $candidates = @(Get-UsbCandidates $all)
    Show-UsbCandidates $candidates
    if ($candidates.Count -eq 0) { throw 'No hay pendrives compatibles para seleccionar.' }
    Write-Host '  Dejalo conectado. RESCUSB comprueba su identidad automaticamente.' -ForegroundColor DarkGray
    $number = Read-Host 'Elegir pendrive | 0 para volver'
    if ($number -eq '0' -or -not $number) { throw [OperationCanceledException]::new('Seleccion cancelada.') }
    if ($number -notmatch '^\d{1,3}$' -or [int]$number -lt 1 -or [int]$number -gt $candidates.Count) {
        throw 'El numero no corresponde a un pendrive disponible.'
    }
    # The user selects a position in the filtered list, never a physical disk number.
    $target=$candidates[([int]$number-1)]
    return (Assert-Target $target)
}
function ConvertTo-DisplaySerial([string]$Serial) { return ($Serial -replace '[\x00-\x1F\x7F]','').Trim() }
function Get-ConfirmationText($Target) { return "BORRAR $(ConvertTo-DisplaySerial $Target.Serial)" }
function Assert-Confirmation($Target, [string]$Text) {
    if ($Text -cne (Get-ConfirmationText $Target)) { throw 'La confirmacion no coincide. No se borro nada.' }
}
function Get-ReparseTag([string]$Path) {
    # FindFirstFile reads the tag of the entry itself, without following a symlink.
    # OneDrive Cloud Files entries are reparse points too; they do not redirect paths.
    if (-not ('USBRescate.NativeFileTags' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace USBRescate {
    public static class NativeFileTags {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FindData {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint SizeHigh, SizeLow, ReparseTag, Reserved;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AlternateName;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFileW(string path, out FindData data);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FindClose(IntPtr handle);
        public static uint Read(string path) {
            FindData data;
            IntPtr handle = FindFirstFileW(path, out data);
            if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try { return data.ReparseTag; }
            finally { FindClose(handle); }
        }
    }
}
'@
    }
    return [USBRescate.NativeFileTags]::Read([IO.Path]::GetFullPath($Path))
}
function Test-SafeReparseTag([uint32]$Tag) {
    # Only IO_REPARSE_TAG_CLOUD and CLOUD_1..F. Unknown tags fail closed.
    $mask = [Convert]::ToUInt32('FFFF0FFF',16)
    $cloud = [Convert]::ToUInt32('9000001A',16)
    return (($Tag -band $mask) -eq $cloud)
}
function Assert-SafeDirectory([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -Force -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $tag=Get-ReparseTag $cursor
                if (-not (Test-SafeReparseTag $tag)) {
                    throw ('Se rechaza un enlace/junction o etiqueta no admitida (0x{0:X8}) en: {1}' -f $tag,$cursor)
                }
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }; $cursor = $parent.FullName
    }
    return $full
}
function Get-UsbRoot($Target) {
    $null = Assert-Target $Target
    $parts = @(Get-Partition -DiskNumber $Target.Number -ErrorAction Stop)
    if ($parts.Count -ne 2) { throw 'Ventoy no tiene exactamente sus dos particiones esperadas.' }
    $large = @($parts | Where-Object { $_.PartitionNumber -eq 1 -and $_.Size -gt 40GB -and $_.DriveLetter })
    $efi = @($parts | Where-Object { $_.PartitionNumber -eq 2 -and $_.Size -ge 30MB -and $_.Size -le 64MB })
    if ($large.Count -ne 1 -or $efi.Count -ne 1) { throw 'Estructura Ventoy inesperada o falta una letra. No se escribira.' }
    $v = Get-Volume -Partition $large[0] -ErrorAction Stop
    $ev = Get-Volume -Partition $efi[0] -ErrorAction Stop
    if ($v.FileSystem -ne 'exFAT' -or $ev.FileSystemLabel -ne 'VTOYEFI' -or $ev.FileSystem -notmatch '^FAT') { throw 'Los volumenes no corresponden a Ventoy exFAT + VTOYEFI.' }
    $root = "$($large[0].DriveLetter):\"
    $null = Assert-SafeDirectory $root
    $mapped = Get-Partition -DriveLetter $large[0].DriveLetter -ErrorAction Stop
    if ($mapped.DiskNumber -ne $Target.Number) { throw 'Cambio la asignacion de letra.' }
    return $root
}
function Assert-Space([string]$Root, [long]$Required) {
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Root))
    if ($drive.AvailableFreeSpace -lt $Required) { throw ("Espacio insuficiente: requiere {0:N2} GiB libres; hay {1:N2}." -f ($Required/1GB),($drive.AvailableFreeSpace/1GB)) }
}
function Get-RemainingBudget($Item, [long]$PartialBytes, [long]$Reserve) {
    if ($PartialBytes -lt 0 -or $PartialBytes -gt $Item.budgetBytes) { throw 'Parcial fuera del limite permitido.' }
    $extra = 0L
    if ($Item.kind -eq 'zipiso') { $extra = [long]$Item.budgetBytes }
    return ([long]$Item.budgetBytes - $PartialBytes + $Reserve + $extra)
}
function Receive-VerifiedFile($Item, [string]$Folder, [scriptblock]$Guard, [long]$Reserve=0, [switch]$Microsoft) {
    $null = Assert-SafeDirectory $Folder
    & $Guard
    if (-not (Test-Path -LiteralPath $Folder)) { $null=New-Item -ItemType Directory -Path $Folder }
    $dest = Join-Path $Folder $Item.file
    foreach ($p in @($dest,($dest+'.part'))) { $null = Assert-SafeDirectory $p }
    if (Test-Path -LiteralPath $dest) {
        try {
            $null = Assert-FileHash $dest $Item.sha256
            if ($Item.kind -in @('iso','windows')) { Assert-Iso $dest }
        } catch { Move-InvalidImage $dest $Guard; throw }
        return $dest
    }
    $part = $dest + '.part'
    $partial = 0L
    if (Test-Path -LiteralPath $part) { $partial = (Get-Item -LiteralPath $part).Length }
    $required=Get-RemainingBudget $Item $partial $Reserve
    # A completed .part from a prior interruption can be promoted without a 416 request.
    $alreadyComplete = $false
    if ($partial -gt 0) {
        Write-Host '  [...] Revisando la descarga anterior antes de continuar.' -ForegroundColor DarkGray
        $alreadyComplete = ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ieq $Item.sha256)
    }
    if (-not $alreadyComplete) {
        Assert-Space $Folder $required
        & $Guard; Invoke-Transfer $Item.url $part $Item.budgetBytes -Resume -Microsoft:$Microsoft
    }
    & $Guard
    $len = (Get-Item -LiteralPath $part).Length
    try {
        if ($len -gt $Item.budgetBytes -or ($Item.exactBytes -gt 0 -and $len -ne $Item.exactBytes)) { throw 'Tamano descargado inesperado.' }
        $null = Assert-FileHash $part $Item.sha256
        if ($Item.kind -in @('iso','windows')) { Assert-Iso $part }
    } catch {
        # A completed but invalid response cannot be resumed safely. Keep evidence under
        # a different name, so the next attempt can start a clean transfer automatically.
        Move-InvalidImage $part $Guard
        throw
    }
    & $Guard
    Move-Item -LiteralPath $part -Destination $dest
    return $dest
}
function Expand-VerifiedIso([string]$Zip, [string]$Destination, [long]$Maximum, [scriptblock]$Guard, [ref]$ExpectedHash) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $isos = @($z.Entries | Where-Object { $_.FullName -match '(?i)\.iso$' })
        if ($isos.Count -ne 1 -or $isos[0].Length -gt $Maximum -or $isos[0].Length -le 0) { throw 'ZIP ISO ambiguo o demasiado grande.' }
        $out = Join-Path $Destination 'Memtest86plus-8.10-x64.iso'
        $null = Assert-SafeDirectory $out; $null = Assert-SafeDirectory ($out+'.part')
        & $Guard
        [IO.Compression.ZipFileExtensions]::ExtractToFile($isos[0],($out+'.part'),$true)
        Assert-Iso ($out+'.part')
        # Re-hash independently from the ZIP stream; no arbitrary path extraction or zip-slip.
        $s = $isos[0].Open(); $sha = [Security.Cryptography.SHA256]::Create()
        try { $expected = ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant() }
        finally { $s.Dispose(); $sha.Dispose() }
        if($null -ne $ExpectedHash){$ExpectedHash.Value=$expected}
        $null = Assert-FileHash ($out+'.part') $expected
        & $Guard
        if (Test-Path -LiteralPath $out) {
            try { $null = Assert-FileHash $out $expected }
            catch { Move-InvalidImage $out $Guard; throw }
            Remove-Item -LiteralPath ($out+'.part')
        } else { Move-Item -LiteralPath ($out+'.part') -Destination $out }
        return $out
    } finally { $z.Dispose() }
}
function Install-Ventoy($Target, $Item, [string]$StateFolder) {
    Assert-NoVentoyProcess
    # Download/verify BEFORE asking for the final destructive confirmation.
    $local = { $null=Assert-Target $Target }.GetNewClosure()
    $zip = Receive-VerifiedFile $Item (Join-Path $StateFolder 'ventoy') $local 134217728
    $tools = Join-Path $StateFolder ('tools-' + [guid]::NewGuid().ToString('N'))
    $null = Assert-SafeDirectory $tools
    # ZIP is pinned by official SHA-256. Extract a fresh copy, never trust a pre-existing exe.
    Expand-Archive -LiteralPath $zip -DestinationPath $tools
    $exes = @(Get-ChildItem -LiteralPath $tools -Recurse -File -Filter Ventoy2Disk.exe)
    if ($exes.Count -ne 1) { throw 'Paquete Ventoy inesperado.' }
    $exe = $exes[0].FullName; $working = $exes[0].DirectoryName
    Write-Host 'ATENCION: SE BORRARAN TODAS LAS PARTICIONES Y ARCHIVOS DEL USB ELEGIDO.' -ForegroundColor Yellow
    Write-Host ('Pendrive: {0} | {1:N2} GB | Unidad {2}: | Serie {3}' -f $Target.Model,($Target.Size/1e9),$Target.Letters,(ConvertTo-DisplaySerial $Target.Serial)) -ForegroundColor White
    $phrase = Get-ConfirmationText $Target
    Write-Host "Escriba exactamente: $phrase"
    Assert-Confirmation $Target (Read-Host 'Confirmacion destructiva')
    Assert-NoVentoyProcess
    $null=Assert-Target $Target
    $argsList = @('VTOYCLI','/I',('/PhyDrive:'+$Target.Number),'/FS:EXFAT')
    # Default MBR + Secure Boot support. Never /NOUSBCheck, /NOSB, forced diskpart or cleanup.
    $p = Start-Process -FilePath $exe -ArgumentList $argsList -WorkingDirectory $working -WindowStyle Hidden -PassThru
    $done = Join-Path $working 'cli_done.txt'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $done)) {
        Start-Sleep -Seconds 2
        $percentPath=Join-Path $working 'cli_percent.txt'
        $percent=0
        if(Test-Path -LiteralPath $percentPath){$n=0;if([int]::TryParse((Get-Content -LiteralPath $percentPath -Raw).Trim(),[ref]$n)){$percent=[math]::Max(0,[math]::Min(100,$n))}}
        Write-Progress -Activity 'RESCUSB | Preparando el arranque' -Status 'Ventoy está trabajando en el pendrive elegido.' -PercentComplete $percent
        $null=Assert-Target $Target -PartitionChanged
        if ($clock.Elapsed.TotalMinutes -gt 10) { throw "Ventoy no confirmo finalizacion. NO vuelva a instalar mientras siga activo. Revise $working" }
    }
    Write-Progress -Activity 'RESCUSB | Preparando el arranque' -Completed
    if ((Get-Content -LiteralPath $done -Raw).Trim() -cne '0') { throw "Ventoy informo un fallo. Revise $working\cli_log.txt" }
    if (-not $p.WaitForExit(30000)) { throw 'Ventoy sigue activo tras cli_done; se detiene el programa sin matarlo.' }
    $newTarget=Assert-Target $Target -PartitionChanged
    # Partition enumeration can lag; retry reads only, never retry installation automatically.
    $root=$null
    for($k=0;$k -lt 15;$k++) {
        try { $root=Get-UsbRoot $newTarget; break } catch { if($k -eq 14){throw}; Start-Sleep -Seconds 2 }
    }
    return [pscustomobject]@{ Target=$newTarget; Root=$root }
}
function Save-JsonAtomic($Object, [string]$Path) {
    $null=Assert-SafeDirectory $Path; $null=Assert-SafeDirectory ($Path+'.tmp')
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath ($Path+'.tmp') -Encoding UTF8
    Move-Item -LiteralPath ($Path+'.tmp') -Destination $Path -Force
}
function Get-WindowsItem($Item, [string]$StateFolder, [string]$Language='Spanish') {
    return (Resolve-MicrosoftIso $Item $StateFolder $Language)
}
function Get-SavedWindowsItem($Item, [string]$StateFolder, [string]$Folder) {
    $metaPath=Join-Path $StateFolder ($Item.id+'.json')
    if (-not (Test-Path -LiteralPath $metaPath)) { return $null }
    $m=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    if ($m.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Metadatos Windows invalidos.' }
    $copy=$Item | ConvertTo-Json | ConvertFrom-Json; $copy.sha256=$m.sha256
    if($m.file -notmatch '^[A-Za-z0-9_.-]+\.iso$' -or $m.file -match '\.\.'){throw 'Nombre Windows guardado invalido.'}
    $copy.file=$m.file
    if($m.PSObject.Properties['name']){$copy.name=$m.name}
    foreach($suffix in @('','.part')) {
        $p=Join-Path $Folder ($copy.file+$suffix)
        if ((Test-Path -LiteralPath $p) -and (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ieq $m.sha256) {
            return [pscustomobject]@{Item=$copy;LocalPath=''}
        }
    }
    return $null
}
function Copy-LocalWindows($Item, [string]$Source, [string]$Folder, [scriptblock]$Guard, [long]$Reserve) {
    $null=Assert-FileHash $Source $Item.sha256; Assert-Iso $Source
    $length=(Get-Item -LiteralPath $Source).Length
    if ($length -gt $Item.budgetBytes) { throw 'ISO Windows mayor que el limite del plan.' }
    & $Guard
    $dest=Join-Path $Folder $Item.file; $part=$dest+'.part'
    $null=Assert-SafeDirectory $dest; $null=Assert-SafeDirectory $part
    if(Test-Path -LiteralPath $dest){
        try {$null=Assert-FileHash $dest $Item.sha256; Assert-Iso $dest; return $dest}
        catch {Move-InvalidImage $dest $Guard; throw}
    }
    Assert-Space $Folder ($length+$Reserve)
    # Robocopy /Z resumes local copies as well; copy into isolated staging directory.
    $stage=Join-Path $Folder ('.local-'+$Item.id)
    $null=Assert-SafeDirectory $stage
    if(-not(Test-Path -LiteralPath $stage)){$null=New-Item -ItemType Directory -Path $stage}
    # Ventoy ignores this directory while an ISO copy is incomplete.
    $ignore=Join-Path $stage '.ventoyignore'; $null=Assert-SafeDirectory $ignore
    & $Guard; [IO.File]::WriteAllText($ignore,'')
    $sourceName=[IO.Path]::GetFileName($Source)
    $null=Assert-SafeDirectory (Join-Path $stage $sourceName)
    & $Guard
    & "$env:SystemRoot\System32\robocopy.exe" ([IO.Path]::GetDirectoryName($Source)) $stage $sourceName /Z /J /R:2 /W:3 /NFL /NDL /NJH /NJS /NP | Out-Host
    if($LASTEXITCODE -ge 8){throw 'Copia Windows interrumpida; /Z conserva progreso en .local-windows*.'}
    $staged=Join-Path $stage $sourceName
    & $Guard; $null=Assert-FileHash $staged $Item.sha256; Assert-Iso $staged
    Move-Item -LiteralPath $staged -Destination $dest
    return $dest
}
function Invoke-ImagePlan($Catalog, $Target, [string]$Root, $Selected, [string]$StateFolder, $Prepared=$null) {
    $folder=Join-Path $Root 'ISO'
    $getRoot = ${function:Get-UsbRoot}
    $guard={
        $currentRoot=& $getRoot $Target
        if($currentRoot -cne $Root){throw 'Cambio la letra USB. Reinicie y seleccione de nuevo.'}
        $null=Assert-SafeDirectory $folder
    }.GetNewClosure()
    & $guard
    if(-not(Test-Path -LiteralPath $folder)){$null=New-Item -ItemType Directory -Path $folder}
    $results=@(); $failed=0
    foreach($base in @($Catalog.images | Where-Object { $_.id -in $Selected })) {
        $status='FALLO'; $detail=''; $path=''; $hash=''
        try {
            Write-Host "`n  > $($base.name)" -ForegroundColor Cyan
            & $guard
            $item=$base; $win=$null
            if($item.kind -eq 'windows') {
                if($Prepared -and $Prepared.ContainsKey($item.id)){$win=$Prepared[$item.id]}
                else {$win=Get-SavedWindowsItem $item $StateFolder $folder}
                if($null -eq $win){$win=Get-WindowsItem $item $StateFolder}
                if($null -eq $win){$status='OMITIDO';$detail='Omitido por el usuario.'; continue}
                $item=$win.Item
            } elseif(-not $Prepared -or -not $Prepared.ContainsKey($item.id)) { Test-OfficialChecksum $item }
            if($win -and $win.LocalPath) { $path=Copy-LocalWindows $item $win.LocalPath $folder $guard $Catalog.reserveBytes }
            else { $path=Receive-VerifiedFile $item $folder $guard $Catalog.reserveBytes -Microsoft:($item.kind -eq 'windows') }
            $expectedHash=$item.sha256
            if($item.kind -eq 'zipiso'){ $path=Expand-VerifiedIso $path $folder $item.budgetBytes $guard ([ref]$expectedHash) }
            & $guard
            Write-Host '  [...] Última lectura de verificación del archivo guardado.' -ForegroundColor DarkGray
            try { $hash=Assert-FileHash $path $expectedHash }
            catch { Move-InvalidImage $path $guard; throw }
            $status='VERIFICADO'; $detail='Descargado y verificado.'
            Write-Host ('  [OK] '+$item.name) -ForegroundColor Green
        } catch { $failed++; $detail=$_.Exception.Message; Write-Warning $detail }
        finally {
            if($status -eq 'OMITIDO'){$failed++}
            $results += [pscustomobject]@{id=$base.id;name=$base.name;status=$status;detail=$detail;file=[IO.Path]::GetFileName($path);sha256=$hash;source=$base.source}
            # PC report survives removal/full USB. Do not log temporary Windows links.
            Save-JsonAtomic $results (Join-Path $StateFolder 'informe.json')
        }
    }
    & $guard
    Save-JsonAtomic $results (Join-Path $Root 'informe-rescate.json')
    $results | Format-Table name,status,detail -AutoSize | Out-Host
    return $failed
}
Export-ModuleMember -Function *
