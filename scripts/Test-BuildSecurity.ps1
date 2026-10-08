[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Test-BuildAssets.ps1')
$unattend=Join-Path $root 'overlay\Autounattend.xml'
[xml]$xml=Get-Content -LiteralPath $unattend -Raw
$text=$xml.OuterXml
foreach($forbidden in @('LocalAccounts','AutoLogon','<Password>','<ProductKey>')) {
  if ($text -match [regex]::Escape($forbidden)) { throw "Forbidden unattended content found: $forbidden" }
}
$runtime=Join-Path $root 'overlay\sources'
foreach($file in Get-ChildItem -LiteralPath $runtime -File -Recurse) {
  $raw=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  if ($raw -and $raw -match '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|winget\s+(install|download)|https?://') {
    throw "Runtime network primitive/URL found in $($file.FullName). Target deployment must be offline."
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'config\assets.lock.json'))) { throw 'assets.lock.json missing. Run Lock-Assets.ps1.' }
$lock=Get-Content -LiteralPath (Join-Path $root 'config\assets.lock.json') -Raw | ConvertFrom-Json
if($lock.schemaVersion -ne 1 -or -not @($lock.files).Count){ throw 'Asset lock is empty or uses an unsupported schema.' }
$paths=@($lock.files | ForEach-Object { $_.relativePath })
if(@($paths | Group-Object | Where-Object Count -gt 1).Count){ throw 'Asset lock contains duplicate paths.' }
$mandatory=New-Object Collections.Generic.List[string]
$apps=Get-Content (Join-Path $root 'config\apps.json') -Raw | ConvertFrom-Json
foreach($app in $apps){
  foreach($property in @('file','secondaryFile','officeConfig')){
    if($app.PSObject.Properties[$property] -and $app.$property){ $mandatory.Add([string]$app.$property) }
  }
}
foreach($folder in @('office','vsix','linux/Ubuntu-22.04-VM','updates','windows/TerminalDependencies','windows/OpenSSH-FoD')){
  $full=Join-Path (Join-Path $root 'assets') $folder
  if(Test-Path -LiteralPath $full){
    foreach($file in Get-ChildItem -LiteralPath $full -Recurse -File){
      if($folder -eq 'vsix' -and $file.Extension -ne '.vsix'){ continue }
      if($folder -eq 'updates' -and $file.Extension -notin @('.cab','.msu')){ continue }
      $mandatory.Add($file.FullName.Substring((Join-Path $root 'assets').Length+1).Replace('\','/'))
    }
  }
}
foreach($relative in @('linux/ubuntu-22.04.5-desktop-amd64.iso','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar.sha256','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json')){ $mandatory.Add($relative) }
foreach($relative in $mandatory){ if($paths -notcontains $relative){ throw "Required asset is not SHA256-locked: $relative" } }
foreach($entry in @($lock.files)) {
  $relative=[string]$entry.relativePath
  if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':'){ throw "Unsafe lock path: $relative" }
  if($entry.sha256 -notmatch '^[0-9a-fA-F]{64}$'){ throw "Invalid SHA256 in asset lock: $relative" }
  $full=Join-Path (Join-Path $root 'assets') ([string]$entry.relativePath)
  if (-not (Test-Path -LiteralPath $full)) { throw "Locked asset missing: $($entry.relativePath)" }
  $actual=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne [string]$entry.sha256) { throw "Locked SHA256 mismatch: $($entry.relativePath)" }
}
Write-Host 'SECURITY CHECK: PASS'
Write-Host '- no username/password/product key/AutoLogon in unattend'
Write-Host '- no target-side download primitive in runtime payload'
Write-Host '- all staged assets match SHA256 lock'
