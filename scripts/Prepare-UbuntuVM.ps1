#requires -version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourceVmDirectory
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$source=(Resolve-Path -LiteralPath $SourceVmDirectory).ProviderPath.TrimEnd('\')
$destination=Join-Path $root 'assets\linux\Ubuntu-22.04-VM'
if(Test-Path -LiteralPath $destination){ throw 'VM staging directory already exists. Preserve/review it before replacing it.' }
$vmxFiles=@(Get-ChildItem -LiteralPath $source -File -Filter *.vmx)
if($vmxFiles.Count -ne 1){ throw 'SourceVmDirectory must contain exactly one VMware .vmx file.' }
if(@(Get-ChildItem -LiteralPath $source -Directory -Recurse -Filter *.lck).Count){ throw 'Shut down the VM and close VMware before staging it.' }
$vmx=Get-Content -LiteralPath $vmxFiles[0].FullName -Raw
if($vmx -notmatch '(?m)^guestOS\s*=\s*"ubuntu-64"'){ throw 'The prepared VM must be Ubuntu x64.' }
$disks=@([regex]::Matches($vmx,'(?m)^\s*(?:scsi|sata|ide|nvme)\d+:\d+\.fileName\s*=\s*"([^"]+\.vmdk)"'))
if(-not $disks.Count){ throw 'VMX contains no VMDK disk.' }
foreach($disk in $disks){
  $relative=$disk.Groups[1].Value
  $full=[IO.Path]::GetFullPath((Join-Path $source $relative))
  if([IO.Path]::IsPathRooted($relative) -or -not $full.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full)){
    throw "VM disk must exist inside SourceVmDirectory: $relative"
  }
}
if(@(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object Extension -in @('.vmss','.vmem','.vmsn')).Count){ throw 'Use a fully shut-down VM without suspended state or snapshots.' }
foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File -Filter *.vmdk){
  $stream=[IO.File]::OpenRead($file.FullName)
  try { $buffer=New-Object byte[] 65536; $length=$stream.Read($buffer,0,$buffer.Length); $descriptor=[Text.Encoding]::ASCII.GetString($buffer,0,$length) }
  finally { $stream.Dispose() }
  if($descriptor -match 'parentFileNameHint\s*='){ throw 'Use a full clone without parent VMDK links.' }
  foreach($extent in [regex]::Matches($descriptor,'(?m)^\s*(?:RW|RDONLY|NOACCESS)\s+\d+\s+\w+\s+"([^"]+)"')){
    $relative=$extent.Groups[1].Value
    $extentPath=[IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relative))
    if([IO.Path]::IsPathRooted($relative) -or -not $extentPath.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $extentPath)){
      throw "VMDK extent must exist inside the prepared VM folder: $relative"
    }
  }
}
$reportPath=Join-Path $source 'baseline.json'
if(-not (Test-Path -LiteralPath $reportPath)){
  throw 'Run scripts/linux/Provision-TypeB-Ubuntu.sh in the prepared Ubuntu VM with mode vm, then copy /usr/local/share/typeb/baseline.json into SourceVmDirectory.'
}
$report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if($report.ubuntuVersion -ne '22.04' -or $report.mode -ne 'vm' -or $report.python -notmatch '^Python 3\.13\.') { throw 'The VM baseline report must describe Ubuntu 22.04 with Python 3.13 in vm mode.' }
foreach($name in @('git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose')) {
  if($report.checks.PSObject.Properties[$name].Value -ne $true){ throw "VM baseline check missing: $name" }
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
# Copy cold disks and their complete relative tree. Never modify the original VM.
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
$stagedVmx=Join-Path $destination 'TypeB-Ubuntu-22.04.vmx'
if($vmxFiles[0].Name -ne 'TypeB-Ubuntu-22.04.vmx'){
  Move-Item -LiteralPath (Join-Path $destination $vmxFiles[0].Name) -Destination $stagedVmx
}
# Disconnect installation media and network until the deployed user opts in.
$stagedText=Get-Content -LiteralPath $stagedVmx -Raw

foreach($cd in [regex]::Matches($stagedText,'(?m)^\s*((?:ide|sata|scsi)\d+:\d+)\.deviceType\s*=\s*"cdrom-image"')) {
  $prefix=[regex]::Escape($cd.Groups[1].Value)
  $stagedText=$stagedText -replace ('(?m)^('+ $prefix +'\.fileName\s*=\s*)"[^"]+"'), '$1"C:\TypeB-Assets\Ubuntu\ubuntu-22.04.5-desktop-amd64.iso"'
  $stagedText=$stagedText -replace ('(?m)^('+ $prefix +'\.startConnected\s*=\s*)"TRUE"'), '$1"FALSE"'
}
$stagedText=$stagedText -replace '(?m)^(\s*ethernet\d+\.startConnected\s*=\s*)"TRUE"', '$1"FALSE"'
if($stagedText -match '(?m)^\.encoding\s*='){ $stagedText=$stagedText -replace '(?m)^\.encoding\s*=.*$', '.encoding = "UTF-8"' }
else{ $stagedText='.encoding = "UTF-8"'+"`n"+$stagedText }
[IO.File]::WriteAllText($stagedVmx,$stagedText,(New-Object Text.UTF8Encoding($false)))
Write-Host "Prepared VM staged: $destination"
Write-Host 'Run Lock-Assets.ps1 after all assets are prepared.'
