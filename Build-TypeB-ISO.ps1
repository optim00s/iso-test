#requires -RunAsAdministrator
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourceIso,
  [string]$OutputIso,
  [string]$WorkRoot,
  [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$SourceIsoSha256
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$config=Get-Content -LiteralPath (Join-Path $root 'config\build.json') -Raw | ConvertFrom-Json
if (-not $OutputIso) { $OutputIso=Join-Path $root ('output\'+$config.outputIso) }
if (-not (Test-Path -LiteralPath $SourceIso)) { throw "Source ISO not found: $SourceIso" }
$plan=& (Join-Path $root 'scripts\Get-TypeBBuildPlan.ps1') -SourceIso $SourceIso -OutputIso $OutputIso -WorkRoot $WorkRoot
if(@($plan.missingOrWrongSize).Count){throw ("Restore the local assets before building. Missing/wrong size: "+@($plan.missingOrWrongSize).Count)}
if(-not $plan.enoughSpace){throw ("Insufficient build space. Work volume needs "+$plan.requiredWorkFreeGiB+" GiB free; available "+$plan.availableWorkGiB+" GiB. See scripts\Get-TypeBBuildPlan.ps1.")}

if(-not $SourceIsoSha256){ $SourceIsoSha256=[string]$config.sourceIsoSha256 }
if($SourceIsoSha256 -notmatch '^[0-9a-fA-F]{64}$'){ throw 'Supply a trusted -SourceIsoSha256 or pin sourceIsoSha256 in config/build.json.' }
$sourceHash=(Get-FileHash -LiteralPath $SourceIso -Algorithm SHA256).Hash.ToLowerInvariant()
if($sourceHash -ne $SourceIsoSha256){ throw "Windows source ISO SHA256 mismatch. Expected: $SourceIsoSha256; actual: $sourceHash" }
Write-Host "Windows source ISO SHA256: PASS ($sourceHash)"
& (Join-Path $root 'scripts\Test-Prerequisites.ps1')
& (Join-Path $root 'scripts\Test-BuildSecurity.ps1')

$work=Join-Path $plan.workRoot ('iso-'+[guid]::NewGuid().ToString('N'))
$work=[IO.Path]::GetFullPath($work)
$sourcePath=(Resolve-Path -LiteralPath $SourceIso).ProviderPath
if($sourcePath.StartsWith($work+'\',[StringComparison]::OrdinalIgnoreCase)){ throw 'Source ISO must be outside work/iso.' }
$OutputIso=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputIso)
if($OutputIso -eq $sourcePath -or $OutputIso.StartsWith($work+'\',[StringComparison]::OrdinalIgnoreCase)){ throw 'Output ISO must be outside work/iso and different from the original.' }
if(Test-Path -LiteralPath $work){throw 'Unique staging directory already exists.'}
New-Item -ItemType Directory -Force -Path $work | Out-Null

$sourcePath=(Resolve-Path -LiteralPath $SourceIso).ProviderPath
$disk=Get-DiskImage -ImagePath $sourcePath
$mountedHere=$false
try {
  if(-not $disk.Attached){$disk=Mount-DiskImage -ImagePath $sourcePath -Access ReadOnly -PassThru;$mountedHere=$true}
  $vol=$disk | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
  if (-not $vol) { throw 'Mounted ISO has no drive letter.' }
  $source=$vol.DriveLetter+':\\'
  if((Test-Path -LiteralPath (Join-Path $source 'Autounattend.xml')) -or (Test-Path -LiteralPath (Join-Path $source 'sources\$OEM$'))){throw 'Use clean Microsoft Windows source media. Restore assets from the old Type B ISO separately.'}
  Write-Host "Copying original Windows media from $source ..."
  & robocopy.exe $source $work /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -gt 7) { throw "robocopy failed: $LASTEXITCODE" }
}
finally { if($mountedHere){Dismount-DiskImage -ImagePath $sourcePath -ErrorAction SilentlyContinue | Out-Null} }

if (Test-Path -LiteralPath (Join-Path $work 'Autounattend.xml')) { throw 'Source ISO already contains Autounattend.xml. Refusing to overwrite it silently.' }
Copy-Item -LiteralPath (Join-Path $root 'overlay\Autounattend.xml') -Destination (Join-Path $work 'Autounattend.xml')

# Overlay fixed runtime files.
$overlaySources=Join-Path $root 'overlay\sources'
Copy-Item -Path (Join-Path $overlaySources '*') -Destination (Join-Path $work 'sources') -Recurse -Force

# Build target package/config directories under $OEM$/$1.
$targetOffline=Join-Path $work 'sources\$OEM$\$1\TypeB-Offline'
$targetPackages=Join-Path $targetOffline 'Packages'
$targetConfig=Join-Path $targetOffline 'Config'
$targetUbuntu=Join-Path $work 'sources\$OEM$\$1\TypeB-Assets\Ubuntu'
New-Item -ItemType Directory -Force -Path $targetPackages,$targetConfig,$targetUbuntu | Out-Null

Copy-Item -LiteralPath (Join-Path $root 'config\apps.json') -Destination $targetConfig
Copy-Item -LiteralPath (Join-Path $root 'config\vsix.json') -Destination $targetConfig
Copy-Item -LiteralPath (Join-Path $root 'config\build.json') -Destination $targetConfig
Copy-Item -LiteralPath (Join-Path $root 'config\assets.lock.json') -Destination $targetConfig

# Copy all locked package assets except final retained Ubuntu assets.
$lock=Get-Content -LiteralPath (Join-Path $root 'config\assets.lock.json') -Raw | ConvertFrom-Json
foreach($entry in @($lock.files)) {
  $rel=[string]$entry.relativePath
  $src=Join-Path (Join-Path $root 'assets') $rel
  if ($rel.StartsWith('linux/')) {
    $destination=Join-Path $targetUbuntu ($rel.Substring(6))
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $src -Destination $destination -Force
    continue
  }
  $dest=Join-Path $targetPackages $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dest -Force
}

# Runtime lock paths are relative to Packages; remove the retained Ubuntu entries from the target runtime lock.
$runtimeLock=[pscustomobject]@{schemaVersion=1;created=$lock.created;files=@($lock.files | Where-Object { $_.relativePath -notlike 'linux/*' })}
$runtimeLock | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $targetConfig 'assets.lock.json') -Encoding utf8

# Retained Ubuntu assets are verified in the user's context before WSL import/VM copy.
$ubuntuLock=[pscustomobject]@{schemaVersion=1;files=@($lock.files | Where-Object { $_.relativePath -like 'linux/*' } | ForEach-Object {
  [pscustomobject]@{relativePath=([string]$_.relativePath).Substring(6);sha256=$_.sha256;size=$_.size}
})}
$ubuntuLock | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $targetUbuntu 'ubuntu.lock.json') -Encoding utf8

# Mandatory build step: recovery fixes are the canonical runtime shipped by
# every new ISO. No guest-side recovery CD or manual repair is required.
& (Join-Path $root 'scripts\Stage-TypeBRuntime.ps1') -MediaRoot $work
$runtimeManifest=Get-Content -LiteralPath (Join-Path $targetConfig 'automation-runtime.json') -Raw | ConvertFrom-Json
foreach($entry in $runtimeManifest.files){
  if((Get-FileHash -LiteralPath (Join-Path $work $entry.relativePath) -Algorithm SHA256).Hash -ne $entry.sha256){throw 'Final staged runtime hash mismatch.'}
}

$oscdimgCandidates=@(
  "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
  "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
)
$oscdimg=$oscdimgCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
$bios=Join-Path $work 'boot\etfsboot.com'
$uefi=Join-Path $work 'efi\microsoft\boot\efisys.bin'
if (-not (Test-Path -LiteralPath $bios)) { throw 'BIOS boot image missing from source ISO.' }
if (-not (Test-Path -LiteralPath $uefi)) { throw 'UEFI boot image missing from source ISO.' }
New-Item -ItemType Directory -Force -Path (Split-Path $OutputIso -Parent) | Out-Null
if (Test-Path -LiteralPath $OutputIso) { throw 'Output appeared during build; it will not be overwritten.' }
# Let PowerShell quote the complete native argument. Embedded quotes become
# literal filename characters under PowerShell 7's native argument passing.
$boot="-bootdata:2#p0,e,b$bios#pEF,e,b$uefi"
& $oscdimg -m -o -u2 -udfver102 $boot $work $OutputIso
if ($LASTEXITCODE -ne 0) { throw "oscdimg failed: $LASTEXITCODE" }
$hash=(Get-FileHash -LiteralPath $OutputIso -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($OutputIso+'.sha256') -Value ($hash+'  '+[IO.Path]::GetFileName($OutputIso)) -Encoding ascii
$manifest=[pscustomobject]@{
  product=$config.productName; release=$config.release; built=(Get-Date).ToUniversalTime().ToString('o');
  sourceIso=(Resolve-Path -LiteralPath $SourceIso).Path; sourceIsoSha256=$sourceHash;
  outputIso=(Resolve-Path -LiteralPath $OutputIso).Path; outputIsoSha256=$hash; architecture='offline-pre-OOBE-local-install';
  usernamePrecreated=$false; targetRuntimeDownloads=$false; firstLogonLocalWslImport=$true; ubuntuVmPrebuilt=$true;
  runtimeFiles=$runtimeManifest.files; stagingDirectory=$work; acceptanceStatus='PENDING_CLEAN_INSTALL'
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path (Split-Path $OutputIso -Parent) 'build-manifest.json') -Encoding utf8
Write-Host ''
Write-Host '[PASS] Type B ISO built' -ForegroundColor Green
Write-Host $OutputIso
Write-Host "SHA256: $hash"
Write-Host 'Built media candidate only. A clean VM and physical USB installation must pass before IT handoff.'
Write-Host 'NEXT: test this ISO in VMware Workstation Pro using tests\VMWARE-FIRST-CHECKLIST.md.'
