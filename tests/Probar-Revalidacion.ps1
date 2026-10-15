#requires -Version 5.1
# Regression probes: tiny local fixtures; no physical storage, network or real installer.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $base 'Rescate.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $base 'Rescusb.UI.psm1') -Force -DisableNameChecking
$mod=Get-Module Rescate.Core
$script:passed=0;$script:failed=0
function Check([string]$Name,[scriptblock]$Body){try{& $Body;$script:passed++;Write-Host "PASS $Name"}catch{$script:failed++;Write-Host "FAIL $Name : $($_.Exception.Message)" -ForegroundColor Red}}
function Equal($Actual,$Expected){if($Actual -cne $Expected){throw "Expected [$Expected], received [$Actual]"}}
function Reject([scriptblock]$Body){$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};if(-not $caught){throw 'Invalid result accepted'}}
$temp=Join-Path $PSScriptRoot ('revalidation-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try{
    $fixture=Join-Path $temp 'valid.iso';$bytes=New-Object byte[] 40960
    [Text.Encoding]::ASCII.GetBytes('CD001').CopyTo($bytes,32769);[IO.File]::WriteAllBytes($fixture,$bytes)
    $hash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $item=[pscustomobject]@{id='fixture';name='Fixture';file='fixture.iso';kind='iso';url='https://example.org/fixture.iso';source='https://example.org';sha256=$hash;budgetBytes=100000L;exactBytes=40960L}
    & $mod {
        param($fixture)
        $script:Fixture=$fixture;$script:Corrupt=$false;$script:NoSpace=$false;$script:TransferCalls=0
        function script:Assert-Space {param($Root,$Required);if($script:NoSpace){throw 'No space'}}
        function script:Invoke-Transfer {
            param($Url,$Destination,$Maximum,[switch]$Resume,[switch]$Microsoft,[switch]$Quiet)
            $script:TransferCalls++
            if(Test-Path -LiteralPath $Destination){throw 'Old corrupt partial was reused'}
            [IO.File]::Copy($script:Fixture,$Destination)
            if($script:Corrupt){$b=[IO.File]::ReadAllBytes($Destination);$b[0]=1;[IO.File]::WriteAllBytes($Destination,$b)}
        }
    } $fixture
    Check 'bad completed download quarantined; next attempt starts clean' {
        $f=Join-Path $temp 'corrupt-transfer'
        & $mod {$script:Corrupt=$true}
        Reject {Receive-VerifiedFile $item $f {}}
        Equal (Test-Path -LiteralPath (Join-Path $f 'fixture.iso.part')) $false
        Equal @(Get-ChildItem -LiteralPath $f -Filter '*.invalid-*.part').Count 1
        & $mod {$script:Corrupt=$false}
        $p=Receive-VerifiedFile $item $f {}
        Equal (Assert-FileHash $p $hash) $hash
    }
    Check 'complete verified partial promoted even without room for another download' {
        $f=Join-Path $temp 'complete-part';$null=New-Item -ItemType Directory -Path $f
        Copy-Item -LiteralPath $fixture -Destination (Join-Path $f 'fixture.iso.part')
        & $mod {$script:NoSpace=$true};$before=& $mod {$script:TransferCalls}
        try{Equal (Receive-VerifiedFile $item $f {}) (Join-Path $f 'fixture.iso');Equal (& $mod {$script:TransferCalls}) $before}
        finally{& $mod {$script:NoSpace=$false}}
    }
    Check 'existing verified local Windows copy reused without a second space reservation' {
        $f=Join-Path $temp 'existing-local';$null=New-Item -ItemType Directory -Path $f
        Copy-Item -LiteralPath $fixture -Destination (Join-Path $f $item.file)
        & $mod {$script:NoSpace=$true}
        try{Equal (Copy-LocalWindows $item $fixture $f {} 0) (Join-Path $f $item.file)}finally{& $mod {$script:NoSpace=$false}}
    }
    Check 'duplicated selection cannot inflate the number of completed tools' {
        $f=Join-Path $temp 'duplicate';$null=New-Item -ItemType Directory -Path $f
        Save-JsonAtomic @{schema=1;language='Spanish';images=@('systemrescue','systemrescue')} (Join-Path $f 'configuracion.json')
        $catalog=Get-Content -LiteralPath (Join-Path $base 'catalogo.json') -Raw|ConvertFrom-Json
        Reject {Get-RescusbSettings $f $catalog}
    }
    & $mod {
        param($root,$expected)
        $script:PlanRoot=$root;$script:PlanPath='';$script:Expected=$expected
        function script:Get-UsbRoot {param($Target);return $script:PlanRoot}
        function script:Test-OfficialChecksum {param($Item)}
        function script:Receive-VerifiedFile {param($Item,$Folder,$Guard,$Reserve,[switch]$Microsoft);return $script:PlanPath}
        function script:Expand-VerifiedIso {
            param($Zip,$Destination,$Maximum,$Guard,[ref]$ExpectedHash)
            if($null -ne $ExpectedHash){$ExpectedHash.Value=$script:Expected}
            return $script:PlanPath
        }
    } $temp $hash
    foreach($kind in @('iso','zipiso')){
        Check "late corruption of $kind is reported as failed and removed from boot menu" {
            $isoDir=Join-Path $temp 'ISO';if(-not(Test-Path -LiteralPath $isoDir)){$null=New-Item -ItemType Directory -Path $isoDir}
            $p=Join-Path $isoDir ($kind+'.iso');Copy-Item -LiteralPath $fixture -Destination $p
            [IO.File]::AppendAllText($p,'corruption-after-earlier-verification')
            & $mod {param($p);$script:PlanPath=$p} $p
            $testItem=$item|ConvertTo-Json|ConvertFrom-Json;$testItem.kind=$kind
            $catalog=[pscustomobject]@{images=@($testItem);reserveBytes=0L}
            Equal (Invoke-ImagePlan $catalog ([pscustomobject]@{}) $temp @('fixture') $temp) 1
            $report=Get-Content -LiteralPath (Join-Path $temp 'informe-rescate.json') -Raw|ConvertFrom-Json
            Equal @($report)[0].status 'FALLO';Equal (Test-Path -LiteralPath $p) $false
        }
    }
}finally{
    $resolved=[IO.Path]::GetFullPath($temp);$boundary=[IO.Path]::GetFullPath($PSScriptRoot)+'\'
    if($resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^revalidation-test-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
    Remove-Module Rescate.Core,Rescusb.UI -Force
}
Write-Host "`n$script:passed PASS / $script:failed FAIL. No network, real installer or USB writes."
if($script:failed){exit 1};exit 0
