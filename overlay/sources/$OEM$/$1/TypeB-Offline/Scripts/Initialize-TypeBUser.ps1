#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\TypeB-Offline'
$ubuntu='C:\TypeB-Assets\Ubuntu'
$userState=Join-Path $env:LOCALAPPDATA 'TypeB'
$complete=Join-Path $userState 'first-logon.complete'
$failed=Join-Path $userState 'first-logon.failed.json'
New-Item -ItemType Directory -Path $userState -Force | Out-Null
if(Test-Path -LiteralPath $complete){ exit 0 }
$log=Join-Path $userState 'first-logon.log'
Start-Transcript -LiteralPath $log -Append | Out-Null
function Invoke-Wsl([string[]]$Arguments){
  & wsl.exe @Arguments
  if($LASTEXITCODE -ne 0){ throw "WSL local initialization failed: $($Arguments -join ' ') (exit $LASTEXITCODE)." }
}
function Add-Shortcut([string]$Name,[string]$Target,[string]$Arguments){
  $folder=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Type B'
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  $shell=New-Object -ComObject WScript.Shell
  $shortcut=$shell.CreateShortcut((Join-Path $folder ($Name+'.lnk')))
  $shortcut.TargetPath=$Target
  $shortcut.Arguments=$Arguments
  $shortcut.Save()
}
try {
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18'){ throw 'Run the first-logon initializer as the real Windows user, not SYSTEM.' }
  if(-not (Test-Path -LiteralPath 'C:\ProgramData\TypeB\State\offline-install.complete')){ throw 'Machine provisioning did not pass. See C:\ProgramData\TypeB\Logs.' }
  $lock=Get-Content -LiteralPath (Join-Path $ubuntu 'ubuntu.lock.json') -Raw | ConvertFrom-Json
  if($lock.schemaVersion -ne 1 -or -not @($lock.files).Count){ throw 'Ubuntu asset lock is empty or invalid.' }
  foreach($entry in $lock.files){
    $relative=[string]$entry.relativePath
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':'){ throw 'Unsafe Ubuntu lock path.' }
    $path=Join-Path $ubuntu $relative
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256){ throw "Ubuntu asset SHA256 mismatch: $relative" }
  }
  & (Join-Path $ubuntu 'Install-TypeB-Ubuntu-WSL.ps1')
  # Derive a Linux name only after Windows OOBE created the real account.
  $linuxUser=$env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9_-]','-'
  if($linuxUser -notmatch '^[a-z_]'){ $linuxUser='user-'+$linuxUser }
  $linuxUser=$linuxUser.Substring(0,[Math]::Min(31,$linuxUser.Length))
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','-u','root','--exec','/usr/local/sbin/typeb-initialize-user',$linuxUser)
  Invoke-Wsl -Arguments @('--terminate','TypeB-Ubuntu-22.04')
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','-u','root','--exec','systemctl','start','docker.service')
  Invoke-Wsl -Arguments @('--set-default','TypeB-Ubuntu-22.04')
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','--exec','bash','-lc','set -e; source /etc/profile.d/typeb-engineering.sh; git lfs version; ssh -V; curl --version; wget --version; tmux -V; ffmpeg -version; ffprobe -version; gcc --version; g++ --version; make --version; cmake --version; uv --version; conda --version; python --version; uv python find --python-preference only-managed 3.13; docker info; docker compose version')
  Add-Shortcut 'Ubuntu 22.04 WSL' (Join-Path $env:SystemRoot 'System32\wsl.exe') '-d TypeB-Ubuntu-22.04'

  $vmSource=Join-Path $ubuntu 'Ubuntu-22.04-VM'
  $vmDest=Join-Path $env:USERPROFILE 'Virtual Machines\TypeB-Ubuntu-22.04'
  $vmMarker=Join-Path $vmDest 'typeb-vm.json'
  $vmEntry=@($lock.files | Where-Object relativePath -eq 'Ubuntu-22.04-VM/TypeB-Ubuntu-22.04.vmx')
  if($vmEntry.Count -ne 1){ throw 'Prepared VMX is not locked.' }
  if(Test-Path -LiteralPath $vmMarker){
    $owner=Get-Content -LiteralPath $vmMarker -Raw | ConvertFrom-Json
    if($owner.sourceVmxSha256 -ne $vmEntry[0].sha256){ throw 'A different Type B VM already exists in this profile.' }
  } else {
    if((Test-Path -LiteralPath $vmDest) -and @(Get-ChildItem -LiteralPath $vmDest -Force).Count){ throw 'VM destination contains existing files. It will not be overwritten.' }
    New-Item -ItemType Directory -Path $vmDest -Force | Out-Null
    & robocopy.exe $vmSource $vmDest /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if($LASTEXITCODE -gt 7){ throw "Prepared VM copy failed: $LASTEXITCODE" }
    foreach($entry in @($lock.files | Where-Object relativePath -like 'Ubuntu-22.04-VM/*')){
      $file=Join-Path $vmDest (([string]$entry.relativePath).Substring('Ubuntu-22.04-VM/'.Length))
      if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256){ throw 'Copied VM failed SHA256 verification.' }
    }
    [pscustomobject]@{sourceVmxSha256=$vmEntry[0].sha256} | ConvertTo-Json | Set-Content -LiteralPath $vmMarker -Encoding utf8
  }
  $vmx=Join-Path $vmDest 'TypeB-Ubuntu-22.04.vmx'
  if(-not (Test-Path -LiteralPath $vmx)){ throw 'Prepared VMX is missing from the user profile.' }
  Add-Shortcut 'Ubuntu 22.04 VM' 'C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe' ('-n "'+$vmx+'"')
  Set-Content -LiteralPath $complete -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ascii
  Remove-Item -LiteralPath $failed -ErrorAction SilentlyContinue
  Set-Content -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\TypeB-User-STATUS.txt') -Value 'TYPE B USER SETUP: PASSED. Ubuntu WSL2 and the prepared VM are available in Start > Type B.' -Encoding utf8
} catch {
  [pscustomobject]@{error=$_.Exception.Message;log=$log} | ConvertTo-Json | Set-Content -LiteralPath $failed -Encoding utf8
  Set-Content -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\TypeB-User-STATUS.txt') -Value ("TYPE B USER SETUP: FAILED. "+$_.Exception.Message+" See "+$log) -Encoding utf8
  exit 1
} finally { try{ Stop-Transcript | Out-Null }catch{} }
exit 0
