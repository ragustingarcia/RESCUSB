#requires -Version 5.1
# Offline safety/integration tests. No storage cmdlets, disk installers or network access.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $base 'Rescate.Core.psm1') -Force -DisableNameChecking
$script:passed=0; $script:failed=0
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $script:passed++; Write-Host "PASS $Name" }
    catch { $script:failed++; Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red }
}
function Equal($Actual,$Expected) {if($Actual -cne $Expected){throw "Esperado [$Expected], recibido [$Actual]"}}
function Reject([scriptblock]$Body,[string]$Contains='') {
    $caught=$false
    try {& $Body | Out-Null} catch {$caught=$true;if($Contains -and $_.Exception.Message -notlike "*$Contains*"){throw}}
    if(-not $caught){throw 'La operacion insegura fue aceptada.'}
}
function New-FakeDisk {
    [pscustomobject]@{Number=3;Model='Kingston DataTraveler';Size=64000000000L;BusType='USB';Serial='TEST64';WmiSerial='TEST64';
        UniqueId='DISK-SIGNATURE';PnpId='USBSTOR\DISK\TEST64';Path='\\?\USB#TEST64';UsbEvidence=$true;RemovableMedia=$true;IsBoot=$false;IsSystem=$false;
        Protected=$false;IsOffline=$false;IsReadOnly=$false;HealthStatus='Healthy';Letters='Z'}
}
$temp=Join-Path $PSScriptRoot ('usb-rescate-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$mod=Get-Module Rescate.Core
try {
    Check 'PowerShell parser: all shipped scripts' {
        foreach($f in Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}) {
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
            if($errors){throw ($errors.Message -join '; ')}
        }
    }
    $catalog=Get-Content -LiteralPath (Join-Path $base 'catalogo.json') -Raw | ConvertFrom-Json
    Check 'catalog valid; exactly seven requested tools' {Assert-Catalog $catalog; Equal $catalog.images.Count 7}
    Check 'Windows links and hashes not embedded' {foreach($w in $catalog.images|Where-Object kind -eq 'windows'){Equal $w.url '';Equal $w.sha256 ''}}
    Check 'malicious path in catalog rejected' {$c=$catalog|ConvertTo-Json -Depth 9|ConvertFrom-Json;$c.images[0].file='../evil.iso';Reject {Assert-Catalog $c}}
    Check 'OneDrive Cloud Files tags accepted; links and unknown tags rejected' {
        for($i=0;$i -lt 16;$i++) {
            $tag=[Convert]::ToUInt32(('9000{0:X1}01A' -f $i),16)
            Equal (Test-SafeReparseTag $tag) $true
        }
        foreach($hex in @('A0000003','A000000C','A000001D','9000001C','80000021','00000000','FFFFFFFF')) {
            Equal (Test-SafeReparseTag ([Convert]::ToUInt32($hex,16))) $false
        }
    }
    Check 'actual ordinary directory and nonexistent child are accepted' {
        Equal (Assert-SafeDirectory $temp) $temp
        $missing=Join-Path $temp 'new\state.json';Equal (Assert-SafeDirectory $missing) $missing
    }
    Check 'actual junction rejected, target untouched' {
        $targetPath=Join-Path $temp 'real-target';$link=Join-Path $temp 'junction'
        $null=New-Item -ItemType Directory -Path $targetPath
        $sentinel=Join-Path $targetPath 'conservar.txt';[IO.File]::WriteAllText($sentinel,'intacto')
        try {
            $null=New-Item -ItemType Junction -Path $link -Target $targetPath
            Equal ((Get-ReparseTag $link).ToString('X8')) 'A0000003'
            Reject {Assert-SafeDirectory (Join-Path $link 'state.json')} 'enlace/junction'
            Equal ([IO.File]::ReadAllText($sentinel)) 'intacto'
        } finally {if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}}
    }
    Check 'single work window: launcher dispatches without waiting, main never elevates again' {
        $launcher=Get-Content -LiteralPath (Join-Path $base 'Lanzar-RESCUSB.ps1') -Raw
        $main=Get-Content -LiteralPath (Join-Path $base 'RESCUSB.ps1') -Raw
        $bat=Get-Content -LiteralPath (Join-Path $base 'INICIAR.bat') -Raw
        if($launcher -notmatch '-Verb RunAs' -or $launcher -match '\s-Wait\b'){throw 'La ventana inicial queda esperando'}
        if($main -match '-Verb RunAs' -or $bat -match '(?im)^pause\s*$'){throw 'Se conserva otra ventana de trabajo'}
    }
    Check 'BAT exposes a fixed non-destructive diagnostic mode' {
        $bat=Get-Content -LiteralPath (Join-Path $base 'INICIAR.bat') -Raw
        if($bat -notmatch '/diagnostico' -or $bat -notmatch '-Modo "%MODO%"'){throw 'Falta diagnostico desde BAT'}
    }
    Check 'healthy 64 GB USB accepted' {Equal (Test-DiskEligible (New-FakeDisk)) ''}
    foreach($case in @(
        @('SATA internal','BusType','SATA'),@('NVMe internal','BusType','NVMe'),@('no WMI USB proof','UsbEvidence',$false),
        @('fixed USB disk','RemovableMedia',$false),
        @('disk zero','Number',0),@('system disk','IsSystem',$true),@('boot disk','IsBoot',$true),@('pagefile/program disk','Protected',$true),
        @('read only','IsReadOnly',$true),@('offline','IsOffline',$true),@('unhealthy','HealthStatus','Warning'),
        @('32 GB actual device','Size',32000000000L),@('128 GB unexpected device','Size',128000000000L),
        @('empty serial','Serial',''),@('zero serial','Serial','0000000'),@('empty unique ID','UniqueId',''),
        @('empty PNP ID','PnpId',''),@('empty WMI serial','WmiSerial',''),@('empty device path','Path','')
    )) {
        $label=$case[0];$key=$case[1];$value=$case[2]
        Check "blocked: $label" {$d=New-FakeDisk;$d.$key=$value;if(-not(Test-DiskEligible $d)){throw 'Accepted unsafe disk'}}
    }
    foreach($key in @('Number','Model','Size','Serial','WmiSerial','UniqueId','PnpId','Path')) {
        Check "identity changed: $key" {
            $a=New-FakeDisk;$b=New-FakeDisk
            if($key -eq 'Number'){$b.Number=4}elseif($key -eq 'Size'){$b.Size=63000000000L}else{$b.$key='CHANGED'}
            Reject {Assert-DiskIdentity $a $b}
        }
    }
    Check 'partition signature change allowed only during install' {
        $a=New-FakeDisk;$b=New-FakeDisk;$b.UniqueId='NEW'
        Reject {Assert-DiskIdentity $a $b};Assert-DiskIdentity $a $b -PartitionChanged
        $b.Serial='SWAPPED';Reject {Assert-DiskIdentity $a $b -PartitionChanged}
    }
    Check 'resume permits changed disk number but same physical identity' {$a=New-FakeDisk;$b=New-FakeDisk;$b.Number=4;Assert-DiskIdentity $a $b -Renumbered}
    Check 'duplicate identity rejected' {$a=New-FakeDisk;$b=New-FakeDisk;$b.Number=4;Reject {Assert-UniqueIdentity $a @($a,$b)}}
    Check 'destructive confirmation exact, no generic yes' {
        $d=New-FakeDisk;Assert-Confirmation $d (Get-ConfirmationText $d)
        foreach($s in @('SI','yes','','BORRAR OTHER','borrar TEST64')){Reject {Assert-Confirmation $d $s}}
    }
    Check 'hardware serial control bytes excluded from typed text, retained in identity' {
        $a=New-FakeDisk;$b=New-FakeDisk;$a.Serial+=''+[char]6+[char]24
        Equal (Get-ConfirmationText $a) 'BORRAR TEST64'
        Assert-Confirmation $a 'BORRAR TEST64'
        Reject {Assert-DiskIdentity $a $b} 'identidad'
        $a.Serial='0000'+[char]6
        if(-not(Test-DiskEligible $a)){throw 'Se acepta una serie de ceros con bytes invisibles'}
    }
    Check 'Microsoft URL exact allowlist' {
        $null=Assert-MicrosoftUrl 'https://software.download.prss.microsoft.com/dbazure/Test_x64.iso?t=fresh'
        foreach($url in @('http://download.microsoft.com/a.iso','https://download.microsoft.com.evil.org/a.iso',
            'https://download.microsoft.com@evil.org/a.iso','https://evil.org/download.microsoft.com/a.iso',
            'https://download.microsoft.com/a.exe','https://download.microsoft.com:444/a.iso','file:///C:/a.iso')){Reject {Assert-MicrosoftUrl $url}}
    }
    Check 'curl must enforce size limits even without Content-Length' {
        Assert-CurlVersion 'curl 8.4.0 (Windows)';Assert-CurlVersion 'curl 8.21.0 (Windows)'
        Reject {Assert-CurlVersion 'curl 7.88.1 (Windows)'};Reject {Assert-CurlVersion 'curl 8.3.0 (Windows)'}
        Reject {Assert-CurlVersion 'unknown'}
    }
    Check 'checksums bound to exact basename including version' {
        $h='a'*64;Equal (Get-ChecksumFromText "$h *v1/test.iso" 'test.iso') $h
        Reject {Get-ChecksumFromText "$h test2.iso" 'test.iso'}
        Reject {Get-ChecksumFromText (("$h test.iso`n")+('b'*64)+' test.iso') 'test.iso'}
    }
    Check 'space reservation accounts for partial and extraction' {
        $i=[pscustomobject]@{budgetBytes=100L;kind='iso'};Equal (Get-RemainingBudget $i 30 20) 90L
        $i.kind='zipiso';Equal (Get-RemainingBudget $i 30 20) 190L
        Reject {Get-RemainingBudget $i 101 20}
    }
    Check 'disk identity rechecked by live inventory guard (mock)' {
        & $mod {
            param($disk)
            $script:FakeInventory=@($disk)
            function script:Get-DiskInventory {$script:FakeInventory}
        } (New-FakeDisk)
        $d=New-FakeDisk;$null=Assert-Target $d
        & $mod {$script:FakeInventory[0].Serial='NEW-DEVICE'}
        Reject {Assert-Target $d}
    }
    # Small synthetic ISO for transport and hash tests. No real disk media involved.
    $bytes=New-Object byte[] 40960
    [Text.Encoding]::ASCII.GetBytes('CD001').CopyTo($bytes,32769)
    $fixture=Join-Path $temp 'fixture.iso';[IO.File]::WriteAllBytes($fixture,$bytes)
    $hash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $item=[pscustomobject]@{id='test';kind='iso';file='test.iso';sha256=$hash;url='https://example.org/test.iso';exactBytes=40960L;budgetBytes=100000L}
    & $mod {
        param($fixture)
        $script:Fixture=$fixture;$script:Calls=0;$script:BreakTransfer=$false;$script:Corrupt=$false;$script:NoSpace=$false
        function script:Assert-Space([string]$Root,[long]$Required){if($script:NoSpace){throw 'Espacio insuficiente'}}
        function script:Invoke-Transfer {
            param($Url,$Destination,$Maximum,[switch]$Resume,[switch]$Microsoft,[switch]$Quiet)
            $script:Calls++
            if($script:BreakTransfer){[IO.File]::WriteAllBytes($Destination,[IO.File]::ReadAllBytes($script:Fixture)[0..1023]);throw 'Interrupted'}
            [IO.File]::Copy($script:Fixture,$Destination,$true)
            if($script:Corrupt){[IO.File]::AppendAllText($Destination,'BAD')}
        }
    } $fixture
    $guard={};$folder=Join-Path $temp 'images'
    Check 'partial interrupted transfer retained and no bootable ISO' {
        & $mod {$script:BreakTransfer=$true}
        Reject {Receive-VerifiedFile $item $folder $guard}
        Equal (Test-Path -LiteralPath (Join-Path $folder 'test.iso')) $false
        Equal (Get-Item -LiteralPath (Join-Path $folder 'test.iso.part')).Length 1024L
    }
    Check 'resume validates then promotes ISO' {
        & $mod {$script:BreakTransfer=$false}
        $p=Receive-VerifiedFile $item $folder $guard
        Equal (Assert-FileHash $p $hash) $hash;Assert-Iso $p
        Equal (Test-Path -LiteralPath ($p+'.part')) $false
    }
    Check 'verified final reused with no download' {
        $before=& $mod {$script:Calls};$null=Receive-VerifiedFile $item $folder $guard
        Equal (& $mod {$script:Calls}) $before
    }
    Check 'corrupt final quarantined and never trusted' {
        [IO.File]::AppendAllText((Join-Path $folder 'test.iso'),'bad')
        Reject {Receive-VerifiedFile $item $folder $guard}
        Equal (Test-Path -LiteralPath (Join-Path $folder 'test.iso')) $false
        Equal @(Get-ChildItem -LiteralPath $folder -Filter '*.invalid-*.part').Count 1
    }
    Check 'hash mismatch never promoted' {
        & $mod {$script:Corrupt=$true}
        Reject {Receive-VerifiedFile $item $folder $guard}
        Equal (Test-Path -LiteralPath (Join-Path $folder 'test.iso')) $false
        & $mod {$script:Corrupt=$false}
    }
    Check 'complete .part reused without a failing Range 416 request' {
        [IO.File]::Copy($fixture,(Join-Path $folder 'test.iso.part'),$true)
        $before=& $mod {$script:Calls};$null=Receive-VerifiedFile $item $folder $guard
        Equal (& $mod {$script:Calls}) $before
    }
    Check 'identity change before write aborts transport' {
        $f=Join-Path $temp 'guarded';$before=& $mod {$script:Calls}
        Reject {Receive-VerifiedFile $item $f {throw 'Device changed'}}
        Equal (& $mod {$script:Calls}) $before; Equal (Test-Path -LiteralPath $f) $false
    }
    Check 'no space aborts before transfer' {
        & $mod {$script:NoSpace=$true};$before=& $mod {$script:Calls}
        Reject {Receive-VerifiedFile $item (Join-Path $temp 'full') $guard} 'Espacio insuficiente'
        Equal (& $mod {$script:Calls}) $before; & $mod {$script:NoSpace=$false}
    }
    Check 'HTML response rejected as ISO despite matching supplied hash' {
        $html=Join-Path $temp 'response.iso';[IO.File]::WriteAllText($html,'<html>expired</html>');Reject {Assert-Iso $html}
    }
    Check 'UDF-only Windows ISO recognition supported; incomplete sequence rejected' {
        $p=Join-Path $temp 'windows-udf.iso';$b=New-Object byte[] 131072
        foreach($pair in @(@(16,'BEA01'),@(17,'NSR02'),@(18,'TEA01'))){[Text.Encoding]::ASCII.GetBytes($pair[1]).CopyTo($b,([int]$pair[0]*2048+1))}
        [IO.File]::WriteAllBytes($p,$b);Assert-Iso $p
        $b[18*2048+1]=0;[IO.File]::WriteAllBytes($p,$b);Reject {Assert-Iso $p}
    }
    Check 'ZIP safe extraction and independent output verification' {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=Join-Path $temp 'fixture.zip';$z=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
        $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$fixture,'../../evil.iso');$z.Dispose()
        $extractedHash='';$out=Expand-VerifiedIso $zip $folder 100000 $guard ([ref]$extractedHash)
        Equal $extractedHash $hash
        Equal (Split-Path $out -Leaf) 'Memtest86plus-8.10-x64.iso';Equal (Assert-FileHash $out $hash) $hash
        Reject {Expand-VerifiedIso $zip $folder 100 $guard}
    }
    Check 'atomic JSON roundtrip' {$p=Join-Path $temp 'report.json';Save-JsonAtomic @{ok=$true} $p;Equal (Get-Content $p -Raw|ConvertFrom-Json).ok $true}
    Check 'local Windows ISO copy: verified, restartable, staging removed when done' {
        $localItem=$item|ConvertTo-Json|ConvertFrom-Json;$localItem.kind='windows';$localItem.id='windows11';$localItem.file='Windows11-x64.iso'
        $f=Join-Path $temp 'local';$null=New-Item -ItemType Directory -Path $f
        $out=Copy-LocalWindows $localItem $fixture $f {} 0
        Equal ($out -is [string]) $true;Equal (Assert-FileHash $out $hash) $hash
        # The staging folder (hidden from Ventoy while copying) is removed once the ISO is in place.
        Equal (Test-Path -LiteralPath (Join-Path $f '.local-windows11')) $false
    }
    Check 'display shows only eligible removable USB, never internal or fixed USB disks' {
        $usb=New-FakeDisk
        $internal=New-FakeDisk;$internal.Number=0;$internal.BusType='NVMe';$internal.Model='INTERNAL_NEVER_SHOW'
        $fixed=New-FakeDisk;$fixed.Number=4;$fixed.RemovableMedia=$false;$fixed.Model='USB_SSD_NEVER_SHOW'
        foreach($d in @($internal,$fixed)){
            foreach($key in @('Serial','WmiSerial','UniqueId','PnpId','Path')){$d.$key=$d.Model}
        }
        $candidates=@(Get-UsbCandidates @($internal,$fixed,$usb))
        Equal $candidates.Count 1;Equal $candidates[0].Number 3
        $visible=Show-UsbCandidates $candidates 6>&1 | Out-String
        if($visible -match 'INTERNAL_NEVER_SHOW|USB_SSD_NEVER_SHOW|BLOQUEADO'){throw 'La lista filtra datos de discos excluidos'}
        if($visible -notmatch 'Kingston DataTraveler'){throw 'No muestra el pendrive correcto'}
    }
    Check 'duplicate-identity USBs not offered' {
        $a=New-FakeDisk;$b=New-FakeDisk;$b.Number=4
        Equal @(Get-UsbCandidates @($a,$b)).Count 0
    }
    Check 'typing a hidden internal disk number cannot select it' {
        $usb=New-FakeDisk;$internal=New-FakeDisk;$internal.Number=4;$internal.BusType='NVMe'
        foreach($key in @('Serial','WmiSerial','UniqueId','PnpId','Path')){$internal.$key='INTERNAL'}
        & $mod {
            param($inventory)
            $script:CandidateInventory=$inventory;$script:ReadCount=0
            function script:Get-DiskInventory {$script:CandidateInventory}
            function script:Read-Host {param($Prompt);$script:ReadCount++;return '4'}
        } @($usb,$internal)
        Reject {Select-Usb} 'no corresponde a un pendrive'
        Equal (& $mod {$script:ReadCount}) 1
    }
    Check 'no removable USB stops without asking for a disk number' {
        $internal=New-FakeDisk;$internal.BusType='NVMe'
        & $mod {param($d);$script:CandidateInventory=@($d);$script:ReadCount=0} $internal
        Reject {Select-Usb} 'No hay pendrives compatibles'
        Equal (& $mod {$script:ReadCount}) 0
    }
    Check 'filtered position maps to physical USB; no unplug or reconnect prompts' {
        & $mod {
            param($disk)
            $script:SelectDisk=$disk;$script:InventoryCalls=0;$script:PromptCalls=0;$script:SwapSerial=$false;$script:Prompts=@()
            function script:Get-DiskInventory {
                $script:InventoryCalls++
                if($script:InventoryCalls -ge 2 -and $script:SwapSerial){$script:SelectDisk.Serial='OTHER'}
                # Return copies, as real inventories do, to avoid mutating the saved snapshot.
                return ($script:SelectDisk|ConvertTo-Json|ConvertFrom-Json)
            }
            function script:Read-Host {param($Prompt);$script:PromptCalls++;$script:Prompts+=$Prompt;return '1'}
        } (New-FakeDisk)
        $selected=Select-Usb;Equal $selected.Number 3;Equal $selected.Serial 'TEST64'
        Equal (& $mod {$script:PromptCalls}) 1
        if(((& $mod {$script:Prompts}) -join ' ') -match 'Desconect|Vuelva a conectar'){throw 'Persiste la reconexion obligatoria'}
        & $mod {
            param($d)
            $script:SelectDisk=$d;$script:InventoryCalls=0;$script:PromptCalls=0;$script:SwapSerial=$true
        } (New-FakeDisk)
        Reject {Select-Usb} 'identidad'
    }
    Check 'Ventoy volume validation accepts only disk-mapped exFAT + VTOYEFI' {
        & $mod {
            param($d)
            $script:FakeInventory=@($d);$script:BadMapping=$false;$script:BadLabel=$false
            function script:Get-DiskInventory {$script:FakeInventory}
            function script:Get-Partition {
                param($DiskNumber,$DriveLetter)
                if($DriveLetter){return [pscustomobject]@{DiskNumber=$(if($script:BadMapping){8}else{3})}}
                @([pscustomobject]@{PartitionNumber=1;Size=60000000000L;DriveLetter='Z'},[pscustomobject]@{PartitionNumber=2;Size=33554432L;DriveLetter=''})
            }
            function script:Get-Volume {
                param($Partition)
                if($Partition.PartitionNumber -eq 1){return [pscustomobject]@{FileSystem='exFAT';FileSystemLabel='Ventoy'}}
                [pscustomobject]@{FileSystem='FAT';FileSystemLabel=$(if($script:BadLabel){'OTHER'}else{'VTOYEFI'})}
            }
        } (New-FakeDisk)
        Equal (Get-UsbRoot (New-FakeDisk)) 'Z:\'
        & $mod {$script:BadMapping=$true};Reject {Get-UsbRoot (New-FakeDisk)} 'asignacion'
        & $mod {$script:BadMapping=$false;$script:BadLabel=$true};Reject {Get-UsbRoot (New-FakeDisk)} 'volumenes'
    }
    Check 'installer mocked: exact confirmation, physical disk argument and cli_done success' {
        & $mod {
            param($temp,$disk)
            $script:InstallerTemp=$temp;$script:Disk=$disk;$script:Launches=0;$script:WrongConfirmation=$false;$script:CliResult='0'
            function script:Assert-NoVentoyProcess {}
            function script:Assert-Target {param($Expected,[switch]$PartitionChanged);return $script:Disk}
            function script:Receive-VerifiedFile {param($Item,$Folder,$Guard,$Reserve);return (Join-Path $script:InstallerTemp 'fake.zip')}
            function script:Expand-Archive {
                param($LiteralPath,$DestinationPath)
                $null=New-Item -ItemType Directory -Path $DestinationPath
                [IO.File]::WriteAllText((Join-Path $DestinationPath 'Ventoy2Disk.exe'),'never executed')
            }
            function script:Read-Host {param($Prompt);if($script:WrongConfirmation){return 'SI'};return (Get-ConfirmationText $script:Disk)}
            function script:Start-Process {
                param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru)
                $script:Launches++;$script:InstallerArgs=$ArgumentList
                [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'cli_done.txt'),$script:CliResult)
                $p=[pscustomobject]@{};$p|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($ms);return $true};return $p
            }
            function script:Get-UsbRoot {param($Target);return $script:InstallerTemp}
            function script:Get-ControlledFolderPreference {return $null}
        } $temp (New-FakeDisk)
        $result=Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp
        Equal $result.Root $temp
        Equal ((& $mod {$script:InstallerArgs}) -join ' ') 'VTOYCLI /I /PhyDrive:3 /FS:EXFAT'
        Equal (& $mod {$script:Launches}) 1
        & $mod {$script:WrongConfirmation=$true}
        Reject {Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp} 'confirmacion'
        Equal (& $mod {$script:Launches}) 1
        & $mod {$script:WrongConfirmation=$false;$script:CliResult='1'}
        Reject {Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp} 'Ventoy informo'
        Equal (Test-Path -LiteralPath (Join-Path $temp 'ventoy-instalador\Ventoy2Disk.exe')) $true
        & $mod {$script:CliResult='1'}
    }
    Check 'Controlled Folder Access: blocks only when enabled and Ventoy is not allowed' {
        $exe='C:\RESCUSB\estado\ventoy-instalador\ventoy-1.1.18\Ventoy2Disk.exe'
        Equal (Test-ControlledFolderBlocks $null $exe) $false
        Equal (Test-ControlledFolderBlocks ([pscustomobject]@{EnableControlledFolderAccess=0;ControlledFolderAccessAllowedApplications=$null}) $exe) $false
        Equal (Test-ControlledFolderBlocks ([pscustomobject]@{EnableControlledFolderAccess=2;ControlledFolderAccessAllowedApplications=$null}) $exe) $false
        Equal (Test-ControlledFolderBlocks ([pscustomobject]@{EnableControlledFolderAccess=1;ControlledFolderAccessAllowedApplications=$null}) $exe) $true
        Equal (Test-ControlledFolderBlocks ([pscustomobject]@{EnableControlledFolderAccess=3;ControlledFolderAccessAllowedApplications=@('C:\Otro.exe')}) $exe) $true
        Equal (Test-ControlledFolderBlocks ([pscustomobject]@{EnableControlledFolderAccess=1;ControlledFolderAccessAllowedApplications=@($exe.ToUpper())}) $exe) $false
    }
    Check 'blocked Ventoy asks for permission before confirmation and never erases on cancel' {
        & $mod {
            $script:Launches=0;$script:CliResult='0';$script:Allowed=$false;$script:Opened=0
            function script:Get-ControlledFolderPreference {[pscustomobject]@{EnableControlledFolderAccess=1;ControlledFolderAccessAllowedApplications=$(if($script:Allowed){@($script:ExePath)}else{@()})}}
            function script:Set-Clipboard {param($Value);$script:ExePath=$Value}
            function script:Open-RansomwareProtection {$script:Opened++}
            function script:Read-Host {param($Prompt);if($Prompt -like '*permitido*'){return '0'};return (Get-ConfirmationText $script:Disk)}
        }
        try {
            Reject {Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp} 'permiso'
            Equal (& $mod {$script:Launches}) 0;Equal (& $mod {$script:Opened}) 1
            if((& $mod {$script:ExePath}) -notlike '*\ventoy-instalador\*Ventoy2Disk.exe'){throw 'Ruta copiada inesperada'}
            & $mod {
                function script:Read-Host {param($Prompt);if($Prompt -like '*permitido*'){$script:Allowed=$true;return ''};return (Get-ConfirmationText $script:Disk)}
            }
            $null=Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp
            Equal (& $mod {$script:Launches}) 1
        } finally {
            & $mod {
                function script:Get-ControlledFolderPreference {return $null}
                function script:Read-Host {param($Prompt);return (Get-ConfirmationText $script:Disk)}
            }
        }
    }
    Check 'error 5 from Ventoy is explained as a Windows write block' {
        & $mod {
            $script:CliResult='1'
            function script:Start-Process {
                param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$PassThru)
                $script:Launches++
                [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'cli_log.txt'),'WriteFile error bRet:0 WriteSize:512 dwSize:0 ErrCode:5')
                [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'cli_done.txt'),'1')
                $p=[pscustomobject]@{};$p|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($ms);return $true};return $p
            }
            function script:Read-Host {param($Prompt);return (Get-ConfirmationText $script:Disk)}
        }
        Reject {Install-Ventoy (New-FakeDisk) $catalog.ventoy $temp} 'Acceso controlado'
    }
    Check 'image plan continues after failure and reports partial result' {
        & $mod {
            param($temp)
            function script:Get-UsbRoot {param($Target);return $script:InstallerTemp}
            function script:Test-OfficialChecksum {param($Item);if($Item.id -eq 'systemrescue'){throw 'Simulated source failure'}}
            function script:Receive-VerifiedFile {param($Item,$Folder,$Guard,$Reserve);return $script:Fixture}
        } $temp
        $testCatalog=$catalog|ConvertTo-Json -Depth 8|ConvertFrom-Json
        ($testCatalog.images|Where-Object id -eq 'hirens').sha256=$hash
        $failures=Invoke-ImagePlan $testCatalog (New-FakeDisk) $temp @('systemrescue','hirens') $temp
        Equal $failures 1
        $report=Get-Content -LiteralPath (Join-Path $temp 'informe-rescate.json') -Raw|ConvertFrom-Json
        Equal $report.Count 2;Equal $report[0].status 'FALLO';Equal $report[1].status 'VERIFICADO'
    }
    Check 'installer safety flags present; dangerous overrides absent' {
        $text=Get-Content -LiteralPath (Join-Path $base 'Rescate.Core.psm1') -Raw
        if($text -notmatch "'VTOYCLI','/I',\('/PhyDrive:'\+\`$Target.Number\),'/FS:EXFAT'"){throw 'Unexpected installer command'}
        $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$null,[ref]$null)
        $strings=$ast.FindAll({param($a)$a -is [Management.Automation.Language.StringConstantExpressionAst]},$true).Value
        foreach($bad in @('/NOUSBCheck','/NOSB','/GPT','diskpart','Clear-Disk','Format-Volume')) {if($bad -in $strings){throw "Unsafe command $bad"}}
    }
} finally {
    # Delete only the unique directory created above, after checking the absolute boundary.
    $resolved=[IO.Path]::GetFullPath($temp);$boundary=[IO.Path]::GetFullPath($PSScriptRoot)+'\'
    if($resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^usb-rescate-test-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Module Rescate.Core -Force
}
Write-Host "`n$script:passed PASS / $script:failed FAIL. No se modificaron discos USB."
if($script:failed){exit 1};exit 0
