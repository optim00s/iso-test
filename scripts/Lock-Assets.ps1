[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$apps=Get-Content -LiteralPath (Join-Path $root 'config\apps.json') -Raw | ConvertFrom-Json
$vsix=Get-Content -LiteralPath (Join-Path $root 'config\vsix.json') -Raw | ConvertFrom-Json
& (Join-Path $PSScriptRoot 'Test-BuildAssets.ps1')
$items=New-Object Collections.Generic.List[object]
function Add-Lock([string]$Relative,[bool]$RequireSignature,[string]$ExpectedSha256) {
  $Relative=$Relative.Replace('\','/')
  if($items.relativePath -contains $Relative){ return }
  $full=Join-Path (Join-Path $root 'assets') $Relative
  if (-not (Test-Path -LiteralPath $full)) { throw "Required asset missing: assets\$Relative" }
  $file=Get-Item -LiteralPath $full
  $hash=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
  if($ExpectedSha256){
    if($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$'){ throw "Invalid expected SHA256 pin: $Relative" }
    if($hash -ne $ExpectedSha256){ throw "Publisher SHA256 mismatch: $Relative. Expected: $ExpectedSha256; actual: $hash" }
  }
  $sigStatus=$null; $signer=$null
  if ($RequireSignature -and ([IO.Path]::GetExtension($full).ToLowerInvariant() -in @('.exe','.msi','.dll','.ps1'))) {
    $sig=Get-AuthenticodeSignature -LiteralPath $full
    $sigStatus=[string]$sig.Status
    $signer=if($sig.SignerCertificate){$sig.SignerCertificate.Subject}else{$null}
    if ($sig.Status -ne 'Valid') { throw "Required Authenticode signature is not valid: $Relative ($($sig.Status))" }
  }
  $items.Add([pscustomobject]@{relativePath=$Relative.Replace('\','/');sha256=$hash;size=$file.Length;signatureStatus=$sigStatus;signer=$signer})
}
foreach($app in @($apps)) {
  $expected=if($app.PSObject.Properties['expectedSha256']){[string]$app.expectedSha256}else{$null}
  Add-Lock ([string]$app.file) ([bool]$app.requireSignature) $expected
  if ($app.PSObject.Properties['secondaryFile'] -and $app.secondaryFile) { Add-Lock ([string]$app.secondaryFile) $true }
  if ($app.PSObject.Properties['dependencyFolder'] -and $app.dependencyFolder) {
    $dep=Join-Path (Join-Path $root 'assets') ([string]$app.dependencyFolder)
    if (-not (Test-Path -LiteralPath $dep)) { throw "Dependency folder missing: $($app.dependencyFolder)" }
    foreach($f in Get-ChildItem -LiteralPath $dep -File) {
      $relative=$f.FullName.Substring((Join-Path $root 'assets').Length).TrimStart('\')
      Add-Lock $relative $true
    }
  }
}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'assets\vsix') -Filter *.vsix -File){ Add-Lock ('vsix/'+$file.Name) $false }
foreach($relative in @('linux/ubuntu-22.04.5-desktop-amd64.iso','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar.sha256','linux/TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json')) { Add-Lock $relative $false }
# Lock the entire Office source tree, not only setup.exe/configuration.xml.
$officeRoot=Join-Path $root 'assets\office'
foreach($f in Get-ChildItem -LiteralPath $officeRoot -File -Recurse) {
  $relative=$f.FullName.Substring((Join-Path $root 'assets').Length).TrimStart('\')
  if (-not ($items.relativePath -contains $relative.Replace('\','/'))) { Add-Lock $relative $false }
}
foreach($folder in @('linux/Ubuntu-22.04-VM','updates','windows/OpenSSH-FoD')) {
  $full=Join-Path (Join-Path $root 'assets') $folder
  if(Test-Path -LiteralPath $full){
    foreach($file in Get-ChildItem -LiteralPath $full -File -Recurse){
      if($folder -eq 'updates' -and $file.Extension -notin @('.msu','.cab')){ continue }
      Add-Lock ($file.FullName.Substring((Join-Path $root 'assets').Length).TrimStart('\')) $false
    }
  }
}
$lock=[pscustomobject]@{schemaVersion=1;created=(Get-Date).ToUniversalTime().ToString('o');files=@($items | Sort-Object relativePath)}
$path=Join-Path $root 'config\assets.lock.json'
$lock | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Asset lock written: $path"
Write-Host "Files locked: $($items.Count)"
