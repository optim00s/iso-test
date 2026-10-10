#requires -version 5.1
[CmdletBinding()]
param(
    [string]$DistroName='TypeB-Ubuntu-22.04',
    [string]$InstallLocation=(Join-Path $env:LOCALAPPDATA 'WSL\TypeB-Ubuntu-22.04'),
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256
)
$ErrorActionPreference='Stop'
. 'C:\TypeB-Offline\Scripts\TypeB-UserCommon.ps1'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -eq 'S-1-5-18'){throw 'WSL import must run in the existing Windows user profile.'}
$importMutex=[Threading.Mutex]::new($false,('Local\TypeB-WSLImport-'+$sid))
$importHeld=$false
try{$importHeld=$importMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$importHeld=$true}
if(-not $importHeld){$importMutex.Dispose();throw 'Another Type B WSL import is already active.'}
try {
if($DistroName -cne 'TypeB-Ubuntu-22.04'){throw 'Unexpected distribution name.'}
$InstallLocation=[IO.Path]::GetFullPath($InstallLocation).TrimEnd('\')
$expectedLocation=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'WSL\TypeB-Ubuntu-22.04')).TrimEnd('\')
if($InstallLocation -ne $expectedLocation){throw 'Unexpected WSL destination.'}
$tar=Join-Path $PSScriptRoot 'TypeB-Ubuntu-22.04-WSL-Docker.tar'
$lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ubuntu.lock.json') -Raw | ConvertFrom-Json
$entries=@($lock.files | Where-Object relativePath -eq 'TypeB-Ubuntu-22.04-WSL-Docker.tar')
if($lock.schemaVersion -ne 1 -or $entries.Count -ne 1 -or $entries[0].sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Trusted WSL image hash is missing.'}
if($ExpectedSha256 -and $ExpectedSha256 -ne $entries[0].sha256){throw 'Conflicting WSL image hash.'}
$ExpectedSha256=[string]$entries[0].sha256
Write-TypeBStage 'WSL source' 'Verifying the local Ubuntu + Docker TAR.'
$hash=Get-TypeBHash $tar
if($hash -ne $ExpectedSha256){throw 'WSL TAR SHA256 mismatch.'}
$state=Join-Path $env:LOCALAPPDATA 'TypeB'
$journalPath=Join-Path $state 'wsl-import-attempt.json'
$marker=Join-Path $InstallLocation 'typeb-image.json'
$journal=$null
if(Test-Path -LiteralPath $journalPath){$journal=Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json}
$registrations=@()
if(Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'){
    $registrations=@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Get-ItemProperty | Where-Object DistributionName -eq $DistroName)
}
if($registrations.Count -gt 1){throw 'Duplicate WSL registration; automatic reset refused.'}
$owned=Test-TypeBAttemptOwner $journal $DistroName $hash $InstallLocation $sid
$bootId=Get-TypeBBootId
if($registrations.Count){
    $reg=$registrations[0]
    $registeredLocation=[IO.Path]::GetFullPath(([string]$reg.BasePath -replace '^\\\\\?\\','')).TrimEnd('\')
    if($reg.Version -ne 2 -or $registeredLocation -ne $InstallLocation -or
       ($reg.VhdFileName -and $reg.VhdFileName -ne 'ext4.vhdx')){throw 'Existing WSL registration differs; automatic reset refused.'}
    if($reg.State -ne 3){
        if(-not (Test-Path -LiteralPath $marker)){
            # Recover the gap after a successful import, using an advance ownership journal.
            if(-not $owned){throw 'Unowned WSL registration; it will not be changed.'}
            Invoke-TypeBWsl -Arguments @('-d',$DistroName,'-u','root','--exec','test','-x','/usr/local/sbin/typeb-initialize-user')
            Write-TypeBJson $marker ([ordered]@{distroName=$DistroName;sha256=$hash})
        }
        $identity=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if($identity.distroName -cne $DistroName -or $identity.sha256 -ne $hash){throw 'Existing WSL image identity differs.'}
        Write-TypeBStage 'WSL import' 'Existing local WSL 2 import is registered.'
        return
    }
    if(-not $owned -or [int]$journal.attemptCount -ge 2){
        $e=[InvalidOperationException]::new('Interrupted import is unowned or its one automatic recovery was exhausted. Existing disk retained.')
        $e.Data['TypeBExitCode']=21;throw $e
    }
    if(-not $journal.bootId -or $journal.bootId -eq $bootId){
        $e=[InvalidOperationException]::new('Restart Windows before automatic WSL recovery. The original service operation may still be active in this boot.')
        $e.Data['TypeBExitCode']=20;throw $e
    }
    Write-TypeBStage 'WSL recovery' 'Recovering this installer-owned interrupted import; preserving its disk first.'
    $previousPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$running=@(& wsl.exe --list --running --quiet 2>&1);$runningCode=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    $otherRunning=@($running | ForEach-Object {([string]$_).Replace([string][char]0,'').Trim()} | Where-Object {$_ -and $_ -ne $DistroName})
    if($runningCode -ne 0 -or $otherRunning.Count){throw 'Other WSL activity could not be excluded; automatic shutdown/reset refused.'}
    Invoke-TypeBWsl -Arguments @('--shutdown')
    $vhd=Join-Path $InstallLocation 'ext4.vhdx'
    $backup=Join-Path $env:LOCALAPPDATA ('TypeB-Recovery\auto-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    if(Test-Path -LiteralPath $vhd){
        $size=(Get-Item -LiteralPath $vhd).Length
        $free=Get-TypeBFreeBytes $InstallLocation
        if($free -lt ($size+15GB)){throw 'Not enough disk space for verified backup plus reimport; original disk retained.'}
        $saved=Join-Path $backup 'ext4.vhdx'
        Copy-Item -LiteralPath $vhd -Destination $saved
        if((Get-TypeBHash $vhd) -ne (Get-TypeBHash $saved)){throw 'Backup SHA256 mismatch; reset refused.'}
    }
    & reg.exe export $reg.PSPath.Replace('Microsoft.PowerShell.Core\Registry::','') (Join-Path $backup 'registration.reg') /y
    if($LASTEXITCODE -ne 0){throw 'Registry backup failed; reset refused.'}
    # Persist the retry bound before resetting, so interrupted retries remain bounded.
    $journal.attemptCount=2
    $journal.bootId=$bootId
    Write-TypeBJson $journalPath $journal
    Invoke-TypeBWsl -Arguments @('--unregister',$DistroName)
    Write-TypeBStage 'WSL recovery' "Interrupted registration reset; backup retained: $backup"
} elseif(-not $owned -and (Test-Path -LiteralPath $InstallLocation) -and @(Get-ChildItem -LiteralPath $InstallLocation -Force).Count){
    throw 'Unknown files in WSL destination; nothing will be overwritten.'
}
if((Test-Path -LiteralPath $InstallLocation) -and @(Get-ChildItem -LiteralPath $InstallLocation -Force).Count){
    if($registrations.Count -eq 0 -and $owned -and [int]$journal.attemptCount -lt 2){
        # An importer-owned orphan has no registration to unregister. Retain its
        # whole directory with a same-volume move; never delete unknown files.
        if(-not $journal.bootId -or $journal.bootId -eq $bootId){
            $e=[InvalidOperationException]::new('Restart Windows before recovering an installer-owned orphan; no directory was moved.')
            $e.Data['TypeBExitCode']=20;throw $e
        }
        $backup=Join-Path $env:LOCALAPPDATA ('TypeB-Recovery\orphan-'+[guid]::NewGuid().ToString('N'))
        $sourceFull=[IO.Path]::GetFullPath($InstallLocation)
        $targetFull=[IO.Path]::GetFullPath($backup)
        $allowedBackup=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'TypeB-Recovery')).TrimEnd('\')+'\'
        if($sourceFull -ne $expectedLocation -or -not $targetFull.StartsWith($allowedBackup,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe orphan recovery path.'}
        $journal.attemptCount=2
        $journal.bootId=$bootId
        Write-TypeBJson $journalPath $journal
        New-Item -ItemType Directory -Path (Split-Path $backup -Parent) -Force | Out-Null
        Move-Item -LiteralPath $sourceFull -Destination $targetFull
        Write-TypeBStage 'WSL recovery' "Installer-owned orphan directory retained: $backup"
    } else {throw 'WSL destination is not empty; import refused.'}
}
if(-not $journal){
    $journal=[pscustomobject]@{schemaVersion=1;createdEmpty=$true;distroName=$DistroName;sha256=$hash;installLocation=$InstallLocation;userSid=$sid;attemptCount=1;bootId=$bootId}
    Write-TypeBJson $journalPath $journal
} elseif(-not $owned){throw 'Import journal belongs to a different image or user.'}
$free=Get-TypeBFreeBytes $InstallLocation
if($free -lt 15GB){throw 'At least 15 GiB free guest disk space is required before WSL import.'}
New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
Write-TypeBStage 'WSL import' 'Importing local Ubuntu + Docker as WSL 2. Do not restart during import.'
Invoke-TypeBWsl -Arguments @('--import',$DistroName,$InstallLocation,$tar,'--version','2')
Write-TypeBJson $marker ([ordered]@{distroName=$DistroName;sha256=$hash})
Write-TypeBStage 'WSL import' 'Local Ubuntu + Docker image imported successfully.'
} finally {if($importHeld){$importMutex.ReleaseMutex()};$importMutex.Dispose()}

