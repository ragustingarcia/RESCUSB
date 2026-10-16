#requires -Version 5.1
# RESCUSB integration tests | No network, physical storage queries or real installer.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
foreach($name in @('Rescate.Core.psm1','Rescusb.Microsoft.psm1','Rescusb.UI.psm1')){Import-Module (Join-Path $base $name) -Force -DisableNameChecking}
$script:passed=0;$script:failed=0
function Check([string]$Name,[scriptblock]$Body){try{& $Body;$script:passed++;Write-Host "PASS $Name"}catch{$script:failed++;Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red}}
function Equal($Actual,$Expected){if($Actual -cne $Expected){throw "Esperado [$Expected], recibido [$Actual]"}}
function Reject([scriptblock]$Body,[string]$Contains=''){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true;if($Contains -and $_.Exception.Message -notlike "*$Contains*"){throw}};if(-not $caught){throw 'Se acepto un estado invalido'}}
function FakeDisk {
    [pscustomobject]@{Number=9;Model='Test USB';Size=64000000000L;BusType='USB';Serial='SAFE-USB';WmiSerial='SAFE-USB';
        UniqueId='DISK-ID';PnpId='USBSTOR\TEST';Path='\\?\USB#TEST';UsbEvidence=$true;RemovableMedia=$true;IsBoot=$false;IsSystem=$false;
        Protected=$false;IsOffline=$false;IsReadOnly=$false;HealthStatus='Healthy';Letters='Z'}
}
$temp=Join-Path $PSScriptRoot ('rescusb-test-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path $temp
$ms=Get-Module Rescusb.Microsoft;$ui=Get-Module Rescusb.UI
$catalog=Get-Content -LiteralPath (Join-Path $base 'catalogo.json') -Raw|ConvertFrom-Json
try{
    $hash='a'*64
    $html='<table><tr><td>Spanish 32-bit</td><td>'+('b'*64)+'</td></tr><tr><td>Spanish 64-bit</td><td>'+$hash+'</td></tr><tr><td>Spanish (Mexico) 64-bit</td><td>'+('c'*64)+'</td></tr></table>'
    Check 'Microsoft SHA bound to exact language and x64' {Equal (Get-MicrosoftHash $html 'Spanish') $hash;Equal (Get-MicrosoftHash $html 'Spanish (Mexico)') ('c'*64);Reject {Get-MicrosoftHash $html 'English'}}
    Check 'conflicting official checksums stop selection' {Reject {Get-MicrosoftHash ($html+'<tr><td>Spanish 64-bit</td><td>'+('d'*64)+'</td></tr>') 'Spanish'}}
    $isoBytes=New-Object byte[] 40960;[Text.Encoding]::ASCII.GetBytes('CD001').CopyTo($isoBytes,32769)
    $toolFolder=Join-Path $temp 'tool-iso';$null=New-Item -ItemType Directory -Path $toolFolder;[IO.File]::WriteAllBytes((Join-Path $toolFolder 'Windows.iso'),$isoBytes)
    & $ms {
        param($html)
        $script:FixtureHtml=$html;$script:Calls=@();$script:HttpFailure=$false;$script:LocalOfficial=''
        function script:Find-RescusbLocalWindows {param($Id,$Hash,$Maximum,$StateFolder);return $script:LocalOfficial}
        # Mounting an ISO and DISM need a real Windows image: the signature check is simulated.
        $script:IsoFolders=@();$script:Tested=@()
        function script:Get-RescusbIsoFolders {param($StateFolder);return $script:IsoFolders}
        function script:Test-RescusbMediaToolIso {param($Path,$Id,$Language);$script:Tested+=[IO.Path]::GetFileName($Path)}
        function script:Invoke-WebRequest {
            param($Uri,$UserAgent,[switch]$UseBasicParsing,$MaximumRedirection,$TimeoutSec)
            $script:Calls+=[string]$Uri
            if($script:HttpFailure){throw 'Network unavailable'}
            if($Uri -notmatch '/software-download/windows(?:11|10ISO)$'){throw 'Unexpected network request'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($script:FixtureHtml);$stream=New-Object IO.MemoryStream;$stream.Write($bytes,0,$bytes.Length);$stream.Position=0
            return [pscustomobject]@{StatusCode=200;RawContentStream=$stream}
        }
    } $html
    $win11=$catalog.images|Where-Object id -eq 'windows11'
    Check 'Windows lookup only reads Microsoft public page and never requests a download link' {
        & $ms {$script:Calls=@()}
        Equal (Resolve-MicrosoftIso $win11 (Join-Path $temp 'none') 'Spanish') $null
        $calls=@(& $ms {$script:Calls});Equal $calls.Count 1
        Equal ([uri]$calls[0]).DnsSafeHost 'www.microsoft.com'
    }
    Check 'ISO matching the published hash is preferred over the tool' {
        & $ms {param($f);$script:LocalOfficial=(Join-Path $f 'Windows.iso');$script:IsoFolders=@($f)} $toolFolder
        $resolved=Resolve-MicrosoftIso $win11 (Join-Path $temp 'official') 'Spanish'
        Equal $resolved.Item.sha256 $hash;Equal ($null -eq $resolved.Item.PSObject.Properties['verification']) $true
        & $ms {$script:LocalOfficial='';$script:IsoFolders=@()}
    }
    Check 'Media Creation Tool ISO accepted by signature when there is no official ISO' {
        & $ms {param($f);$script:IsoFolders=@($f)} $toolFolder
        $resolved=Resolve-MicrosoftIso $win11 (Join-Path $temp 'tool') 'Spanish'
        Equal $resolved.LocalPath (Join-Path $toolFolder 'Windows.iso');Equal $resolved.Item.verification 'firma'
        & $ms {$script:IsoFolders=@()}
    }
    Check 'without Internet a signed tool ISO is still found' {
        & $ms {param($f);$script:HttpFailure=$true;$script:IsoFolders=@($f)} $toolFolder
        Equal (Resolve-MicrosoftIso $win11 (Join-Path $temp 'offline') 'Spanish').Item.verification 'firma'
        & $ms {$script:HttpFailure=$false;$script:IsoFolders=@()}
    }    Check 'SHA-256 with progress matches Get-FileHash across buffers and for empty files' {
        $big=Join-Path $temp 'grande.bin';$bytes=New-Object byte[] 9437185;(New-Object Random 7).NextBytes($bytes);[IO.File]::WriteAllBytes($big,$bytes)
        Equal (Get-Sha256WithProgress $big) (Get-FileHash -LiteralPath $big -Algorithm SHA256).Hash.ToLower()
        $empty=Join-Path $temp 'vacio.bin';[IO.File]::WriteAllBytes($empty,[byte[]]@())
        Equal (Get-Sha256WithProgress $empty) (Get-FileHash -LiteralPath $empty -Algorithm SHA256).Hash.ToLower()
    }
    Check 'Microsoft signature required: system binary accepted, unsigned file rejected' {
        Assert-MicrosoftSignature (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $unsigned=Join-Path $temp 'setup.exe';[IO.File]::WriteAllBytes($unsigned,[byte[]](77,90,0,0));Reject {Assert-MicrosoftSignature $unsigned} 'firma'
    }
    Check 'Media Creation Tool image must be x64, chosen language and right Windows version' {
        $ok=[pscustomobject]@{Architecture=9;Languages=@('es-ES');Version='10.0.26100'}
        Assert-RescusbWindowsImageInfo $ok 'windows11' 'Spanish'
        Reject {Assert-RescusbWindowsImageInfo $ok 'windows10' 'Spanish'} 'otra versión'
        Reject {Assert-RescusbWindowsImageInfo $ok 'windows11' 'English'} 'idioma'
        Reject {Assert-RescusbWindowsImageInfo ([pscustomobject]@{Architecture=12;Languages=@('es-ES');Version='10.0.26100'}) 'windows11' 'Spanish'} 'x64'
        Assert-RescusbWindowsImageInfo ([pscustomobject]@{Architecture=9;Languages=@('es-MX');Version='10.0.19045'}) 'windows10' 'Spanish (Mexico)'
    }
    Check 'signed local ISO gets its own name, hash and recorded verification' {
        $f=Join-Path $temp 'mct';$null=New-Item -ItemType Directory -Path $f
        $p=Join-Path $f 'Windows.iso';$bytes=New-Object byte[] 40960;[Text.Encoding]::ASCII.GetBytes('CD001').CopyTo($bytes,32769);[IO.File]::WriteAllBytes($p,$bytes)
        [IO.File]::WriteAllBytes((Join-Path $f 'Otro.iso'),$bytes)
        & $ms {$script:Tested=@()}
        $state=Join-Path $temp 'mct-state'
        $found=Find-RescusbMediaToolWindows ($catalog.images|Where-Object id -eq 'windows11') 'Spanish' $state @($f)
        Equal (@(& $ms {$script:Tested}) -join ',') 'Windows.iso'
        $h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
        Equal $found.LocalPath $p;Equal $found.Item.sha256 $h;Equal $found.Item.verification 'firma'
        Equal $found.Item.file ('windows11-herramienta-es-ES-'+$h.Substring(0,8)+'.iso')
        Equal (Get-Content -LiteralPath (Join-Path $state 'windows11.json') -Raw|ConvertFrom-Json).verification 'firma'
    }
    Check 'local official ISO accepted only by official SHA and structure' {
        $f=Join-Path $temp 'local';$null=New-Item -ItemType Directory -Path $f
        $p=Join-Path $f 'Win11_Local_x64.iso';$bytes=New-Object byte[] 40960;[Text.Encoding]::ASCII.GetBytes('CD001').CopyTo($bytes,32769);[IO.File]::WriteAllBytes($p,$bytes)
        $h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        # Invoke the unmocked exported function, passing only the test directory.
        Equal (Find-RescusbLocalWindows 'windows11' $h 100000 $temp @($f)) $p
        Equal (Find-RescusbLocalWindows 'windows11' ('f'*64) 100000 $temp @($f)) ''
    }
    Check 'replugged pendrive recognised under a new disk number, never a different one' {
        $same=FakeDisk;$same.Number=5
        $other=FakeDisk;$other.Number=6;$other.Serial='OTHER-USB';$other.WmiSerial='OTHER-USB';$other.UniqueId='OTHER-ID';$other.PnpId='USBSTOR\OTHER';$other.Path='\\?\USB#OTHER'
        Equal (Find-ReconnectedTarget (FakeDisk) @($other,$same)).Number 5
        Equal (Find-ReconnectedTarget (FakeDisk) @($other)) $null
        $bigger=FakeDisk;$bigger.Number=5;$bigger.Size=64100000000L;Equal (Find-ReconnectedTarget (FakeDisk) @($bigger)) $null
    }
    Check 'default settings choose six tools, Windows 10 optional, Spanish x64' {$settings=Get-RescusbSettings (Join-Path $temp 'settings') $catalog;Equal $settings.images.Count 6;Equal ($settings.images -contains 'windows10') $false;Equal $settings.language 'Spanish'}
    Check 'invalid settings cannot add arbitrary tools' {$state=Join-Path $temp 'invalid-settings';$null=New-Item -ItemType Directory -Path $state;Save-JsonAtomic @{schema=1;language='Spanish';images=@('disk-wiper')} (Join-Path $state 'configuracion.json');Reject {Get-RescusbSettings $state $catalog}}
    & $ui {
        $script:FailMicrosoft=$false;$script:Installs=0;$script:ImageRuns=0;$script:ImageFailures=0;$script:PreparedCount=0;$script:SelectedCount=0;$script:JobRoot='';$script:GapAnswer='0';$script:GapPrompts=0
        function script:Test-OfficialChecksum {param($Item)}
        function script:Get-SavedWindowsItem {param($Item,$StateFolder,$Folder);return $null}
        function script:Get-WindowsItem {
            param($Item,$StateFolder,$Language)
            if($script:FailMicrosoft){return $null}
            $copy=$Item|ConvertTo-Json|ConvertFrom-Json;$copy.sha256='a'*64;$copy.url='https://software.download.prss.microsoft.com/Win11_Test_x64.iso'
            return [pscustomobject]@{Item=$copy;LocalPath=''}
        }
        function script:Assert-Target {param($Expected,[switch]$PartitionChanged);return $Expected}
        function script:Install-Ventoy {param($Target,$Item,$StateFolder);$script:Installs++;return [pscustomobject]@{Target=$Target;Root=$script:JobRoot}}
        function script:Invoke-ImagePlan {param($Catalog,$Target,$Root,$Selected,$StateFolder,$Prepared);$script:ImageRuns++;$script:PreparedCount=$Prepared.Count;$script:SelectedCount=@($Selected).Count;return $script:ImageFailures}
        function script:Read-Host {param($Prompt);$script:GapPrompts++;return $script:GapAnswer}
        $script:ToolRuns=0
        function script:Invoke-RescusbMediaTool {param($Id,$StateFolder,$Language);$script:ToolRuns++;$script:FailMicrosoft=$false}
        function script:Get-UsbRoot {param($Target);return $script:JobRoot}
    }
    $settings=[pscustomobject]@{schema=1;language='Spanish';images=@($catalog.images.id)}
    Check 'cancelling while Windows is still to be created never invokes installer or USB writes' {
        $job=Join-Path $temp 'blocked-job';$null=New-Item -ItemType Directory -Path $job
        & $ui {param($r);$script:JobRoot=$r;$script:FailMicrosoft=$true;$script:Installs=0;$script:ImageRuns=0} $job
        Reject {Start-RescusbJob $catalog $settings (FakeDisk) $temp} 'fuente oficial'
        Equal (& $ui {$script:Installs}) 0;Equal (& $ui {$script:ImageRuns}) 0
        Equal @(Get-ChildItem -LiteralPath $job -File).Count 0
    }
    Check 'Windows can be left pending: five tools prepared, never marked ready' {
        $job=Join-Path $temp 'pending-job';$null=New-Item -ItemType Directory -Path $job
        & $ui {param($r);$script:JobRoot=$r;$script:FailMicrosoft=$true;$script:Installs=0;$script:ImageRuns=0;$script:ImageFailures=0;$script:GapAnswer='2'} $job
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp) 2
        Equal (& $ui {$script:Installs}) 1;Equal (& $ui {$script:SelectedCount}) 5
        $status=Get-Content -LiteralPath (Join-Path $job 'RESCUSB-ESTADO.json') -Raw|ConvertFrom-Json
        Equal $status.complete $false;Equal $status.selected.Count 7;Equal (@($status.pending) -join ',') 'windows11,windows10'
        & $ui {$script:FailMicrosoft=$false;$script:GapAnswer='0'}
    }
    Check 'resume after a pending Windows retries it and completes' {
        $job=Join-Path $temp 'pending-job'
        & $ui {param($r);$script:JobRoot=$r;$script:Installs=0;$script:ImageFailures=0;$script:GapPrompts=0} $job
        Save-JsonAtomic @{schema=1;identity=(FakeDisk)} (Join-Path $job 'usb-rescate-identidad.json')
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp -Resume) 0
        Equal (& $ui {$script:Installs}) 0;Equal (& $ui {$script:SelectedCount}) 7;Equal (& $ui {$script:GapPrompts}) 0
        Equal (Get-Content -LiteralPath (Join-Path $job 'RESCUSB-ESTADO.json') -Raw|ConvertFrom-Json).complete $true
    }
    Check 'Enter creates Windows with the tool, then the job completes with all seven' {
        $job=Join-Path $temp 'tool-job';$null=New-Item -ItemType Directory -Path $job
        & $ui {param($r);$script:JobRoot=$r;$script:FailMicrosoft=$true;$script:Installs=0;$script:ImageFailures=0;$script:ToolRuns=0;$script:GapAnswer=''} $job
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp) 0
        Equal (& $ui {$script:ToolRuns}) 2;Equal (& $ui {$script:SelectedCount}) 7
        & $ui {$script:GapAnswer='0'}
    }
    Check 'pendrive briefly missing is retried quietly; one really unplugged is awaited, not abandoned' {
        & $ui {
            $script:Gone=$true;$script:Replugs=0
            function script:Assert-Target {param($Expected,[switch]$PartitionChanged);if($Expected.Number -eq 9 -and $script:Gone){throw 'El USB elegido ya no esta conectado.'};return $Expected}
            function script:Get-DiskInventory {$script:Replugs++;$d=[pscustomobject]@{Number=5};return @($d)}
            function script:Find-ReconnectedTarget {param($Expected,$Inventory);return $Inventory[0]}
            $script:SavedAnswer=$script:GapAnswer;$script:GapAnswer=''
        }
        & $ui {$script:GapPrompts=0}
        Equal (Wait-RescusbTarget (FakeDisk) -DelaySeconds 0).Number 5
        Equal (& $ui {$script:GapPrompts}) 0
        & $ui {function script:Find-ReconnectedTarget {param($Expected,$Inventory);if($script:GapPrompts -gt 0){return $Inventory[0]};return $null}}
        Equal (Wait-RescusbTarget (FakeDisk) -DelaySeconds 0).Number 5
        Equal (& $ui {$script:GapPrompts}) 1
        & $ui {$script:GapAnswer='0'}
        Reject {Wait-RescusbTarget (FakeDisk) -Retries 0} 'no está conectado'
        & $ui {
            $script:GapAnswer=$script:SavedAnswer
            function script:Assert-Target {param($Expected,[switch]$PartitionChanged);return $Expected}
        }
    }
    Check 'complete job automatically passes all seven resolved images and marks readiness' {
        $job=Join-Path $temp 'complete-job';$null=New-Item -ItemType Directory -Path $job
        & $ui {param($r);$script:JobRoot=$r;$script:FailMicrosoft=$false;$script:Installs=0;$script:ImageRuns=0;$script:ImageFailures=0} $job
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp) 0
        Equal (& $ui {$script:Installs}) 1;Equal (& $ui {$script:PreparedCount}) 7
        $status=Get-Content -LiteralPath (Join-Path $job 'RESCUSB-ESTADO.json') -Raw|ConvertFrom-Json
        Equal $status.complete $true;Equal $status.selected.Count 7;Equal $status.bootTested $false
        Equal (Test-Path -LiteralPath (Join-Path $job 'RESCUSB-LEEME.txt')) $true
    }
    Check 'partial downloads never produce a complete readiness marker' {
        $job=Join-Path $temp 'partial-job';$null=New-Item -ItemType Directory -Path $job
        & $ui {param($r);$script:JobRoot=$r;$script:ImageFailures=1} $job
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp) 1
        $status=Get-Content -LiteralPath (Join-Path $job 'RESCUSB-ESTADO.json') -Raw|ConvertFrom-Json
        Equal $status.complete $false;Equal $status.failures 1
    }
    Check 'resume never reinstalls Ventoy' {
        $job=Join-Path $temp 'resume-job';$null=New-Item -ItemType Directory -Path $job
        Save-JsonAtomic @{schema=1;identity=(FakeDisk)} (Join-Path $job 'usb-rescate-identidad.json')
        & $ui {param($r);$script:JobRoot=$r;$script:ImageFailures=0;$script:Installs=0} $job
        Equal (Start-RescusbJob $catalog $settings (FakeDisk) $temp -Resume) 0
        Equal (& $ui {$script:Installs}) 0
    }
    Check 'author identity consistent and no invented public project URL' {
        $identity=[IO.File]::ReadAllText((Join-Path $base 'identidad.json'))|ConvertFrom-Json
        $package=[IO.File]::ReadAllText((Join-Path $base 'package.json'))|ConvertFrom-Json
        Equal $identity.name 'RESCUSB';Equal $identity.author.name 'Rodolfo Agustín García'
        Equal $identity.author.url 'https://ragustingarcia.com/';Equal $identity.publicUrl $null;Equal $identity.repository 'https://github.com/ragustingarcia/RESCUSB'
        Equal $package.author.name $identity.author.name;Equal $package.private $true
    }
    Check 'static SEO graph, local publication boundary and support files complete' {
        $html=[IO.File]::ReadAllText((Join-Path $base 'index.html'))
        $json=[regex]::Match($html,'(?is)<script type="application/ld\+json" id="project-schema">(.*?)</script>').Groups[1].Value|ConvertFrom-Json
        $person=@($json.'@graph'|Where-Object '@type' -eq 'Person')[0]
        $app=@($json.'@graph'|Where-Object '@type' -eq 'SoftwareApplication')[0]
        Equal $person.'@id' 'https://ragustingarcia.com/#person';Equal $app.author.'@id' $person.'@id';Equal $app.operatingSystem 'Windows 10 / Windows 11 x64'
        if($html -notmatch 'name="robots" content="noindex, follow"' -or $html -match 'SCHEMA_JSON_RESCUSB'){throw 'Metadata local incompleta'}
        foreach($file in @('robots.txt','ai.txt','llms.txt','humans.txt','sitemap.xml','SEO-Y-AUTORIA.md','404.html','assets\favicon.svg')){if(-not(Test-Path -LiteralPath (Join-Path $base $file))){throw ('Falta '+$file)}}
        [xml]$map=[IO.File]::ReadAllText((Join-Path $base 'sitemap.xml'));if($map.GetElementsByTagName('loc').Count){throw 'Sitemap inventa URLs de proyecto'}
    }
    Check 'project OG image uses required dimensions and size budget' {
        Add-Type -AssemblyName System.Drawing
        $p=Join-Path $base 'assets\og-image.png';$img=[Drawing.Image]::FromFile($p)
        try{Equal $img.Width 1200;Equal $img.Height 630}finally{$img.Dispose()}
        if((Get-Item -LiteralPath $p).Length -gt 300KB){throw 'Imagen OG demasiado grande'}
    }
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$boundary=[IO.Path]::GetFullPath($PSScriptRoot)+'\'
    if($resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^rescusb-test-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
    foreach($name in @('Rescusb.UI','Rescusb.Microsoft','Rescate.Core')){Remove-Module $name -Force}
}
Write-Host "`n$script:passed PASS / $script:failed FAIL. Sin red, sin instalador real y sin escrituras en USB."
if($script:failed){exit 1};exit 0
