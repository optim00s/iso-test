#requires -version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceIso,
  [string]$OutputIso,
  [string]$WorkRoot
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Join-Path $root 'config\build.json') -Raw | ConvertFrom-Json
if(-not $OutputIso){$OutputIso=Join-Path $root ('output\'+$config.outputIso)}
if(-not $WorkRoot){$WorkRoot=Join-Path $root 'work'}
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputIso)
$work=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkRoot)
$source=(Resolve-Path -LiteralPath $SourceIso).ProviderPath
if([IO.Path]::GetExtension($source) -ne '.iso' -or [IO.Path]::GetExtension($output) -ne '.iso'){throw 'Source and output must be ISO paths.'}
if($source -eq $output -or (Test-Path -LiteralPath $output)){throw 'An existing ISO cannot be overwritten. Choose a new output path.'}
$lock=Get-Content -LiteralPath (Join-Path $root 'config\assets.lock.json') -Raw | ConvertFrom-Json
if($lock.schemaVersion -ne 1 -or -not @($lock.files).Count){throw 'Asset lock is empty or invalid.'}
[long]$assetBytes=0
$missing=New-Object 'Collections.Generic.List[string]'
$seen=@{}
foreach($entry in $lock.files){
  $relative=[string]$entry.relativePath
  if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|:' -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$entry.size -lt 0 -or $seen.ContainsKey($relative)){throw 'Unsafe or invalid asset lock.'}
  $seen[$relative]=$true
  $assetBytes+=[long]$entry.size
  $path=Join-Path (Join-Path $root 'assets') $relative
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){$missing.Add($relative)}
  elseif((Get-Item -LiteralPath $path).Length -ne [long]$entry.size){$missing.Add($relative+' (wrong size)')}
}
$stageBytes=[long](Get-Item -LiteralPath $source).Length+$assetBytes+2GB
$outputBytes=$stageBytes
$workDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($work))
$outputDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($output))
$sameVolume=$workDrive.Name -eq $outputDrive.Name
$requiredWork=if($sameVolume){$stageBytes+$outputBytes+5GB}else{$stageBytes+5GB}
$requiredOutput=if($sameVolume){0}else{$outputBytes+5GB}
$enough=($workDrive.AvailableFreeSpace -ge $requiredWork -and ($sameVolume -or $outputDrive.AvailableFreeSpace -ge $requiredOutput))
[pscustomobject]@{
  sourceIso=$source;outputIso=$output;workRoot=$work
  lockedAssetCount=@($lock.files).Count
  missingOrWrongSize=@($missing.ToArray())
  estimatedStageGiB=[Math]::Round($stageBytes/1GB,2)
  requiredWorkFreeGiB=[Math]::Round($requiredWork/1GB,2)
  availableWorkGiB=[Math]::Round($workDrive.AvailableFreeSpace/1GB,2)
  requiredOutputFreeGiB=[Math]::Round($requiredOutput/1GB,2)
  availableOutputGiB=[Math]::Round($outputDrive.AvailableFreeSpace/1GB,2)
  enoughSpace=$enough;preflightReady=($enough -and $missing.Count -eq 0)
  hashesVerified=$false;willWriteFiles=$false
}
