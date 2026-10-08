#requires -version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
  [string]$BuilderName='TypeB-Ubuntu-Builder',
  [string]$SourceWsl,
  [string]$OutputTar,
  [ValidatePattern('^[0-9A-Fa-f]{64}$')]
  [string]$SourceSha256,
  [switch]$Force
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $SourceWsl) { $SourceWsl=Join-Path $root 'assets\linux\ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz' }
if (-not $OutputTar) { $OutputTar=Join-Path $root 'assets\linux\TypeB-Ubuntu-22.04-WSL-Docker.tar' }
if (-not (Test-Path -LiteralPath $SourceWsl -PathType Leaf)) { throw 'Run Acquire-UbuntuAssets.ps1 first.' }
$SourceWsl=(Resolve-Path -LiteralPath $SourceWsl).ProviderPath
$OutputTar=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputTar)
if ($SourceWsl -eq $OutputTar) { throw 'SourceWsl and OutputTar must be different files.' }
if (-not $SourceSha256) {
  $manifest=Join-Path (Split-Path $SourceWsl -Parent) 'wsl-SHA256SUMS'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Canonical wsl-SHA256SUMS missing. Run Acquire-UbuntuAssets.ps1 or supply a trusted -SourceSha256.' }
  $pattern='^\s*([0-9A-Fa-f]{64})\s+\*?'+[regex]::Escape([IO.Path]::GetFileName($SourceWsl))+'\s*$'
  $entries=@(Get-Content -LiteralPath $manifest | Where-Object { $_ -match $pattern })
  if ($entries.Count -ne 1) { throw 'Expected exactly one source-image SHA256 entry in wsl-SHA256SUMS.' }
  $null=$entries[0] -match $pattern
  $SourceSha256=$Matches[1]
}
$actual=(Get-FileHash -LiteralPath $SourceWsl -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $SourceSha256) { throw "WSL source SHA256 mismatch. Expected: $SourceSha256; actual: $actual" }
Write-Host "WSL source SHA256 verified: $actual"
if (-not $BuilderName -or $BuilderName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw 'BuilderName must use only letters, digits, underscores, dots and hyphens.' }
if ((Test-Path -LiteralPath $OutputTar) -and -not $Force) { throw 'OutputTar already exists. Use -Force to replace it.' }
$before=@(& wsl.exe -l -q 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { throw 'Could not list WSL distributions. Enable/update WSL on the build machine first.' }
if ($before -contains $BuilderName) { throw "Builder distribution already exists: $BuilderName. Choose another -BuilderName." }
$linux=Join-Path $root 'assets\linux'
$buildDir=Join-Path $linux ('.wsl-build-'+[guid]::NewGuid().ToString('N'))
$installDir=Join-Path $buildDir 'distro'
$bashFile=Join-Path $buildDir 'prepare.sh'
$partialTar=$OutputTar+'.'+[guid]::NewGuid().ToString('N')+'.partial'
$baselineConfig=Get-Content -LiteralPath (Join-Path $root 'config\linux-baseline.json') -Raw | ConvertFrom-Json
$baselineDir=Join-Path $root 'assets\linux\baseline'
$baselineManifest=Join-Path $baselineDir 'SHA256SUMS'
if (-not (Test-Path -LiteralPath $baselineManifest)) { throw 'Run Acquire-LinuxBaseline.ps1 first.' }
foreach($name in @($baselineConfig.uvArchive,$baselineConfig.anacondaInstaller)) {
  $pattern='^([0-9a-fA-F]{64})\s+\*?'+[regex]::Escape($name)+'$'
  $entries=@(Get-Content -LiteralPath $baselineManifest | Where-Object { $_ -match $pattern })
  if($entries.Count -ne 1){ throw "Baseline SHA256 entry missing or ambiguous: $name" }
  $null=$entries[0] -match $pattern
  $expected=$Matches[1]
  $hash=(Get-FileHash -LiteralPath (Join-Path $baselineDir $name) -Algorithm SHA256).Hash
  if($hash -ne $expected){ throw "Baseline asset SHA256 mismatch: $name" }
}
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $OutputTar -Parent) -Force | Out-Null
$imported=$false
try {
  & wsl.exe --import $BuilderName $installDir $SourceWsl --version 2
  if ($LASTEXITCODE -ne 0) { throw "WSL source-image import failed: $LASTEXITCODE" }
  $imported=$true
  $provision=Join-Path $root 'scripts\linux\Provision-TypeB-Ubuntu.sh'
  [IO.File]::WriteAllText($bashFile, ((Get-Content -LiteralPath $provision -Raw) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
  # --exec avoids shell parsing, which would strip backslashes from Windows paths.
  $linuxBashPath=(& wsl.exe -d $BuilderName -u root --exec wslpath -a -u $bashFile | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $linuxBashPath) { throw 'Could not translate the preparation script path for WSL.' }
  $linuxAssetPath=(& wsl.exe -d $BuilderName -u root --exec wslpath -a -u $baselineDir | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $linuxAssetPath) { throw 'Could not translate the baseline asset directory for WSL.' }
  & wsl.exe -d $BuilderName -u root --exec bash $linuxBashPath $linuxAssetPath $baselineConfig.pythonVersion wsl
  if ($LASTEXITCODE -ne 0) { throw 'Linux/Docker preparation failed.' }
  $reportText=(& wsl.exe -d $BuilderName -u root --exec cat /usr/local/share/typeb/baseline.json | Out-String)
  if($LASTEXITCODE -ne 0){ throw 'Linux baseline report was not produced.' }
  $baselineReport=$reportText | ConvertFrom-Json
  if($baselineReport.ubuntuVersion -ne '22.04' -or $baselineReport.mode -ne 'wsl' -or $baselineReport.python -notmatch '^Python 3\.13\.') { throw 'Ubuntu/Python baseline report is invalid.' }
  foreach($name in @('git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose')) {
    if($baselineReport.checks.PSObject.Properties[$name].Value -ne $true){ throw "Linux baseline check failed: $name" }
  }
  & wsl.exe --terminate $BuilderName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not terminate the builder distribution before export.' }
  & wsl.exe --export $BuilderName $partialTar
  if ($LASTEXITCODE -ne 0) { throw 'WSL export failed.' }
  if (-not (Test-Path -LiteralPath $partialTar -PathType Leaf) -or (Get-Item -LiteralPath $partialTar).Length -eq 0) { throw 'WSL export is missing or empty.' }
  $outputHash=(Get-FileHash -LiteralPath $partialTar -Algorithm SHA256).Hash.ToLowerInvariant()
  Move-Item -LiteralPath $partialTar -Destination $OutputTar -Force:$Force
  "$outputHash  $([IO.Path]::GetFileName($OutputTar))" | Set-Content -LiteralPath "$OutputTar.sha256" -Encoding utf8
  $baselineReport | Add-Member -NotePropertyName imageSha256 -NotePropertyValue $outputHash -Force
  $baselineReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$OutputTar.baseline.json" -Encoding utf8
  Write-Host "Created: $OutputTar`nSHA256: $outputHash`nChecksum: $OutputTar.sha256"
}
finally {
  if ($imported) {
    & wsl.exe --unregister $BuilderName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not remove temporary WSL distribution $BuilderName. Files retained in $buildDir." }
    else { $imported=$false }
  }
  if (Test-Path -LiteralPath $partialTar -PathType Leaf) { Remove-Item -LiteralPath $partialTar -Force }
  # Delete only this run's generated directory, after successful unregistration.
  $cleanupPath=[IO.Path]::GetFullPath($buildDir)
  $cleanupRoot=[IO.Path]::GetFullPath($linux).TrimEnd('\')+'\'
  if (-not $imported -and $cleanupPath.StartsWith($cleanupRoot, [StringComparison]::OrdinalIgnoreCase) -and
      [IO.Path]::GetFileName($cleanupPath) -match '^\.wsl-build-[0-9a-f]{32}$') {
    if (Test-Path -LiteralPath $cleanupPath) { Remove-Item -LiteralPath $cleanupPath -Recurse -Force }
  }
}
