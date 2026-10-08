#requires -version 5.1
[CmdletBinding()]
param(
  [string]$DistroName='TypeB-Ubuntu-22.04',
  [string]$InstallLocation=(Join-Path $env:LOCALAPPDATA 'WSL\TypeB-Ubuntu-22.04'),
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256
)
$ErrorActionPreference='Stop'
$tar=Join-Path $PSScriptRoot 'TypeB-Ubuntu-22.04-WSL-Docker.tar'
if(-not (Test-Path -LiteralPath $tar -PathType Leaf)){ throw "WSL image missing: $tar" }
if(-not $ExpectedSha256){
  $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ubuntu.lock.json') -Raw | ConvertFrom-Json
  $entries=@($lock.files | Where-Object relativePath -eq 'TypeB-Ubuntu-22.04-WSL-Docker.tar')
  if($entries.Count -ne 1 -or $entries[0].sha256 -notmatch '^[0-9a-fA-F]{64}$'){ throw 'Trusted Ubuntu image SHA256 is missing or ambiguous.' }
  $ExpectedSha256=$entries[0].sha256
}
$hash=(Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash.ToLowerInvariant()
if($hash -ne $ExpectedSha256){ throw 'WSL TAR SHA256 mismatch. Import stopped.' }
if($DistroName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$'){ throw 'Invalid distribution name.' }
$InstallLocation=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallLocation)
$marker=Join-Path $InstallLocation 'typeb-image.json'
$names=@(& wsl.exe -l -q | ForEach-Object { ($_ -replace "`0",'').Trim() } | Where-Object { $_ })
if($LASTEXITCODE -ne 0){ throw 'WSL runtime is not ready. Verify the offline WSL MSI and required reboot.' }
if($names -contains $DistroName){
  if(-not (Test-Path -LiteralPath $marker)){ throw "Existing distribution is not owned by Type B: $DistroName" }
  $owner=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
  if($owner.sha256 -ne $hash -or $owner.distroName -ne $DistroName){ throw 'Existing Type B distribution has a different image identity.' }
  $registrations=@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Get-ItemProperty | Where-Object DistributionName -eq $DistroName)
  if($registrations.Count -ne 1 -or $registrations[0].Version -ne 2){ throw 'The existing Type B distribution is not registered as WSL 2.' }
  Write-Host "Already imported: $DistroName"
  return
}
if((Test-Path -LiteralPath $InstallLocation) -and @(Get-ChildItem -LiteralPath $InstallLocation -Force).Count){ throw 'WSL destination is not empty.' }
New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
& wsl.exe --import $DistroName $InstallLocation $tar --version 2
if($LASTEXITCODE -ne 0){ throw "wsl --import failed: $LASTEXITCODE. No download was attempted." }
[pscustomobject]@{distroName=$DistroName;sha256=$hash} | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding utf8
Write-Host "Imported $DistroName from the verified local image."
