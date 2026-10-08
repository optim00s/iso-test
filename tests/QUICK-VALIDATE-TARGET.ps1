#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$results=New-Object Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Action){
  try { $pass=[bool](& $Action); $detail=if($pass){'PASS'}else{'Not ready'} }
  catch { $pass=$false; $detail=$_.Exception.Message }
  $results.Add([pscustomobject]@{check=$Name;pass=$pass;detail=$detail})
}
Check 'Machine provisioning' { Test-Path 'C:\ProgramData\TypeB\State\offline-install.complete' }
Check 'Current user provisioning' { Test-Path (Join-Path $env:LOCALAPPDATA 'TypeB\first-logon.complete') }
$apps=Get-Content -LiteralPath 'C:\TypeB-Offline\Config\apps.json' -Raw | ConvertFrom-Json
foreach($app in $apps){
  $current=$app
  Check $app.name {
    switch($current.detect.type){
      'file' { Test-Path -LiteralPath $current.detect.value }
      'fileAll' { @($current.detect.value | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0 }
      'registryDisplayName' {
        $needle=$current.detect.value
        @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName -like "*$needle*").Count -gt 0
      }
      'provisionedAppx' { @(Get-AppxPackage -Name $current.detect.value).Count -gt 0 }
      default { $false }
    }
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
  & wsl.exe -d TypeB-Ubuntu-22.04 --exec bash -lc 'set -e; source /etc/profile.d/typeb-engineering.sh; git lfs version; ssh -V; command -v curl wget tmux ffmpeg ffprobe gcc g++ make cmake; uv --version; conda --version; python --version; uv python find --python-preference only-managed 3.13; docker info; docker compose version' | Out-Host
  $LASTEXITCODE -eq 0
}
Check 'Prepared Ubuntu VM in this profile' { Test-Path (Join-Path $env:USERPROFILE 'Virtual Machines\TypeB-Ubuntu-22.04\TypeB-Ubuntu-22.04.vmx') }
$results | Format-Table -Wrap -AutoSize | Out-Host
if(@($results | Where-Object { -not $_.pass }).Count){ exit 1 }
exit 0
