#requires -version 5.1
[CmdletBinding()]
param([switch]$ReportOnly,[string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$assets=Join-Path $root 'assets'
$issues=New-Object Collections.Generic.List[object]
function Add-Issue([string]$Component,[string]$Detail){ $issues.Add([pscustomobject]@{component=$Component;detail=$Detail}) }
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-ZipText([string]$Path,[string]$EntryName){
  $zip=[IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry=$zip.GetEntry($EntryName)
    if(-not $entry){ throw "Archive entry missing: $EntryName" }
    $reader=New-Object IO.StreamReader($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally { $zip.Dispose() }
}
$apps=Get-Content (Join-Path $root 'config\apps.json') -Raw | ConvertFrom-Json
foreach($app in $apps){
  foreach($property in @('file','secondaryFile','officeConfig')){
    if($app.PSObject.Properties[$property] -and $app.$property -and -not (Test-Path -LiteralPath (Join-Path $assets $app.$property) -PathType Leaf)){
      Add-Issue $app.id "Missing: assets/$($app.$property)"
    }
  }
  if($app.PSObject.Properties['dependencyFolder'] -and $app.dependencyFolder){
    $folder=Join-Path $assets $app.dependencyFolder
    if(-not (Test-Path -LiteralPath $folder) -or -not @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object Extension -in @('.appx','.msix')).Count){
      Add-Issue $app.id "Missing offline Appx dependencies in assets/$($app.dependencyFolder) (the supplied Terminal bundle needs Microsoft.UI.Xaml.2.8)."
    }
  }
}
$terminalFolder=Join-Path $assets 'windows\TerminalDependencies'
if(Test-Path -LiteralPath $terminalFolder){
  $xamlFound=$false
  foreach($file in Get-ChildItem -LiteralPath $terminalFolder -File | Where-Object Extension -in @('.appx','.msix')){
    try {
      [xml]$dependency=Read-ZipText $file.FullName 'AppxManifest.xml'
      $identity=$dependency.Package.Identity
      if($identity.Name -eq 'Microsoft.UI.Xaml.2.8' -and $identity.ProcessorArchitecture -in @('x64','neutral') -and
         [version]$identity.Version -ge [version]'8.2305.5001.0' -and $identity.Publisher -eq 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') { $xamlFound=$true }
    } catch { Add-Issue 'windows-terminal' "Invalid dependency package $($file.Name): $($_.Exception.Message)" }
  }
  if(-not $xamlFound){ Add-Issue 'windows-terminal' 'Microsoft.UI.Xaml.2.8 x64/neutral >= 8.2305.5001.0 is required by the supplied Terminal Preview package.' }
}
$configured=@($apps | ForEach-Object { $_.file; if($_.PSObject.Properties['secondaryFile']){ $_.secondaryFile } })
foreach($file in Get-ChildItem -LiteralPath (Join-Path $assets 'windows') -File | Where-Object Extension -in @('.exe','.msi','.zip','.msix','.appx','.msixbundle','.appxbundle')){
  if($configured -notcontains ('windows/'+$file.Name)){ Add-Issue 'windows' "Installer has no install configuration: $($file.Name). Add it to config/apps.json." }
}
$vsix=Get-Content (Join-Path $root 'config\vsix.json') -Raw | ConvertFrom-Json
foreach($name in $vsix.required){ if(-not (Test-Path -LiteralPath (Join-Path $assets ('vsix/'+$name)) -PathType Leaf)){ Add-Issue 'vscode' "Missing: assets/vsix/$name" } }
$extensionIds=New-Object Collections.Generic.List[string]
$extensionPackages=New-Object Collections.Generic.List[object]
foreach($file in Get-ChildItem -LiteralPath (Join-Path $assets 'vsix') -File -Filter *.vsix){
  try {
    $package=Read-ZipText $file.FullName 'extension/package.json' | ConvertFrom-Json
    $id=$package.publisher+'.'+$package.name
    if($package.publisher -notmatch '^[A-Za-z0-9-]+$' -or $package.name -notmatch '^[A-Za-z0-9-]+$' -or $package.version -notmatch '^[A-Za-z0-9.+-]+$'){ throw 'Invalid extension identity.' }
    if($vsix.required -contains $file.Name -and ($file.BaseName -ne $id)){ throw 'Extension identity does not match the required file name.' }
    $extensionIds.Add($id)
    $extensionPackages.Add($package)
  } catch { Add-Issue 'vscode' "$($file.Name): $($_.Exception.Message)" }
}
foreach($package in $extensionPackages){
  foreach($dependency in @($package.extensionDependencies)){
    if($dependency -and $extensionIds -notcontains $dependency){ Add-Issue 'vscode' "Required extension dependency is not staged: $dependency" }
  }
}
if(-not (Test-Path -LiteralPath (Join-Path $assets 'office\Office\Data')) -or
   -not @(Get-ChildItem -LiteralPath (Join-Path $assets 'office\Office\Data') -File -Recurse -ErrorAction SilentlyContinue).Count){
  Add-Issue 'office' 'Offline Office media is absent. Run Prepare-OfficeOffline.ps1.'
}
$officeManifest=Join-Path $assets 'office\SHA256SUMS'
if(-not (Test-Path -LiteralPath $officeManifest -PathType Leaf)){
  Add-Issue 'office' 'Office SHA256SUMS is missing. Wait for Prepare-OfficeOffline.ps1 to complete; a partial Office/Data folder is not ready for the ISO.'
} else {
  try { & (Join-Path $PSScriptRoot 'Prepare-OfficeOffline.ps1') -VerifyOnly }
  catch { Add-Issue 'office' "Office integrity verification failed: $($_.Exception.Message)" }
}
foreach($name in @('ubuntu-22.04.5-desktop-amd64.iso','TypeB-Ubuntu-22.04-WSL-Docker.tar','TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json','Ubuntu-22.04-VM\TypeB-Ubuntu-22.04.vmx','Ubuntu-22.04-VM\baseline.json')){
  if(-not (Test-Path -LiteralPath (Join-Path $assets ('linux/'+$name)) -PathType Leaf)){ Add-Issue 'ubuntu' "Missing: assets/linux/$name" }
}
if(-not @(Get-ChildItem -LiteralPath (Join-Path $assets 'linux\Ubuntu-22.04-VM') -File -Recurse -Filter *.vmdk -ErrorAction SilentlyContinue).Count){ Add-Issue 'ubuntu-vm' 'A prepared Ubuntu 22.04 VM disk is required; a Desktop ISO alone is not an installed VM.' }
foreach($relative in @('linux/TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json','linux/Ubuntu-22.04-VM/baseline.json')) {
  $path=Join-Path $assets $relative
  if(Test-Path -LiteralPath $path){
    try {
      $report=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
      $mode=if($relative -match '/baseline.json$'){'vm'}else{'wsl'}
      if($report.ubuntuVersion -ne '22.04' -or $report.mode -ne $mode -or $report.python -notmatch '^Python 3\.13\.'){ throw 'Ubuntu 22.04 / Python 3.13 / mode does not match.' }
      foreach($check in @('git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose')){
        if($report.checks.PSObject.Properties[$check].Value -ne $true){ throw "Missing passing baseline check: $check" }
      }
      if($mode -eq 'wsl'){
        $tar=Join-Path $assets 'linux\TypeB-Ubuntu-22.04-WSL-Docker.tar'
        if((Test-Path -LiteralPath $tar) -and (Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash -ne $report.imageSha256){ throw 'Baseline report does not match the current TAR SHA256.' }
      }
    } catch { Add-Issue 'linux-baseline' "$relative : $($_.Exception.Message)" }
  }
}
if($ReportPath){
  New-Item -ItemType Directory -Path (Split-Path ([IO.Path]::GetFullPath($ReportPath)) -Parent) -Force | Out-Null
  [pscustomobject]@{ready=($issues.Count -eq 0);issues=@($issues.ToArray())} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding utf8
}
if($ReportOnly){ return $issues.ToArray() }
if($issues.Count){ $issues | Format-Table -Wrap -AutoSize | Out-Host; throw "Build assets incomplete: $($issues.Count) issue(s)." }
Write-Host 'BUILD ASSETS: PASS'
