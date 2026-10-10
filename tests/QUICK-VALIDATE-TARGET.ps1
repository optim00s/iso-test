#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. 'C:\TypeB-Offline\Scripts\TypeB-UserCommon.ps1'
# Import read-only detection functions only; never execute the installer.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile('C:\TypeB-Offline\Scripts\Install-TypeB.ps1',[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Installed runtime does not parse.'}
foreach($name in @('Get-ProvisionedAppNames','Resolve-TypeBVmwareExecutable','Test-Detection','Test-QsyncReady')){
  $definition=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -eq $name)
  if($definition.Count -ne 1){throw 'Installed detection function missing.'}
  Invoke-Expression $definition[0].Extent.Text
}
$results=New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action){
  try { $pass=[bool](& $Action); $detail=if($pass){'PASS'}else{'Not ready'} }
  catch { $pass=$false; $detail=$_.Exception.Message }
  $results.Add([pscustomobject]@{check=$Name;pass=$pass;detail=$detail})
}
Check 'Machine provisioning' { Test-Path 'C:\ProgramData\TypeB\State\offline-install.complete' }
Check 'Current user provisioning' { Test-TypeBComplete (Join-Path $env:LOCALAPPDATA 'TypeB\first-logon.complete') }
$apps=Get-Content -LiteralPath 'C:\TypeB-Offline\Config\apps.json' -Raw | ConvertFrom-Json
foreach($app in $apps){
  $current=$app
  Check $app.name {
    if($current.id -eq 'vmware'){[bool](Resolve-TypeBVmwareExecutable)}
    elseif($current.id -eq 'qsync'){Test-QsyncReady $current}
    elseif($current.detect.type -eq 'provisionedAppx'){@(Get-AppxPackage -Name $current.detect.value).Count -gt 0}
    else{Test-Detection $current.detect}
  }
}
Check 'Windows OpenSSH' { $null=Get-Command ssh.exe -ErrorAction Stop; $true }
Check 'Windows curl' { $null=Get-Command curl.exe -ErrorAction Stop; $true }
Check 'Windows conda on PATH' { & conda --version | Out-Host; $LASTEXITCODE -eq 0 }
Check 'Windows uv on PATH' { & uv --version | Out-Host; $LASTEXITCODE -eq 0 }
Check 'VS Code extensions in current profile' {
  $required=Get-Content -LiteralPath 'C:\TypeB-Offline\Config\vsix.json' -Raw | ConvertFrom-Json
  $installed=@(& 'C:\Program Files\Microsoft VS Code\bin\code.cmd' --list-extensions)
  if($LASTEXITCODE -ne 0){ return $false }
  @($required.required | ForEach-Object { $_ -replace '\.vsix$','' } | Where-Object { $installed -notcontains $_ }).Count -eq 0
}
Check 'Ubuntu Desktop ISO' { Test-Path 'C:\TypeB-Assets\Ubuntu\ubuntu-22.04.5-desktop-amd64.iso' }
Check 'WSL distribution is version 2 for this user' {
  $items=@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Get-ItemProperty | Where-Object DistributionName -eq 'TypeB-Ubuntu-22.04')
  $items.Count -eq 1 -and $items[0].Version -eq 2
}
Check 'WSL engineering baseline and Docker daemon' {
  Invoke-TypeBWsl -Arguments @('-d','TypeB-Ubuntu-22.04','--exec','bash','-lc','set -e; source /etc/profile.d/typeb-engineering.sh; git lfs version; ssh -V; command -v curl wget tmux ffmpeg ffprobe gcc g++ make cmake; uv --version; conda --version; python --version; uv python find --python-preference only-managed 3.13; docker info; docker compose version')
  $true
}
Check 'Prepared Ubuntu VM in this profile' { Test-Path (Join-Path $env:USERPROFILE 'Virtual Machines\TypeB-Ubuntu-22.04\TypeB-Ubuntu-22.04.vmx') }
$results | Format-Table -Wrap -AutoSize | Out-Host
if(@($results | Where-Object { -not $_.pass }).Count){ exit 1 }
exit 0
