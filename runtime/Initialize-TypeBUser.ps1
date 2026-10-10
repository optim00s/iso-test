#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TypeB-UserCommon.ps1')
$root='C:\TypeB-Offline'
$ubuntu='C:\TypeB-Assets\Ubuntu'
$userState=Join-Path $env:LOCALAPPDATA 'TypeB'
$complete=Join-Path $userState 'first-logon.complete'
$failed=Join-Path $userState 'first-logon.failed.json'
New-Item -ItemType Directory -Path $userState -Force | Out-Null
if(Test-TypeBComplete $complete){ exit 0 }
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -eq 'S-1-5-18' -or $sid -match '-500$'){exit 21}
$mutex=[Threading.Mutex]::new($false,('Local\TypeB-Initializer-'+$sid))
$held=$false
try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
if(-not $held){$mutex.Dispose();exit 0}
$log=Join-Path $userState 'first-logon.log'
Start-Transcript -LiteralPath $log -Append | Out-Null
function Invoke-Wsl([string[]]$Arguments){
  Invoke-TypeBWsl -Arguments $Arguments
}
function Resolve-TypeBVmwareExecutable {
    foreach($candidate in @('C:\Program Files\VMware\VMware Workstation\vmware.exe','C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe')) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $info=(Get-Item -LiteralPath $candidate -ErrorAction Stop).VersionInfo
            if ($info.ProductName -eq 'VMware Workstation') { return $candidate }
        }
    }
    return $null
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
  Write-TypeBStage 'VS Code' 'Preparing and checking the extensions for the existing Windows profile.'
  $extensionTarget=Join-Path $env:USERPROFILE '.vscode\extensions'
  $code='C:\Program Files\Microsoft VS Code\bin\code.cmd'
  Install-TypeBExtensions -PackageRoot (Join-Path $root 'Packages\vsix') -ManifestPath (Join-Path $root 'Config\vsix.json') -CodePath $code -ExtensionsDirectory $extensionTarget
  Write-TypeBStage 'Ubuntu assets' 'Checking all local Ubuntu assets against SHA256 locks.'
  $lock=Get-Content -LiteralPath (Join-Path $ubuntu 'ubuntu.lock.json') -Raw | ConvertFrom-Json
  if($lock.schemaVersion -ne 1 -or -not @($lock.files).Count){ throw 'Ubuntu asset lock is empty or invalid.' }
  foreach($entry in $lock.files){
    $relative=[string]$entry.relativePath
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':'){ throw 'Unsafe Ubuntu lock path.' }
    $path=Join-Path $ubuntu $relative
    Write-TypeBStage 'Ubuntu assets' ("Checking "+$relative)
    if((Get-TypeBHash $path) -ne $entry.sha256){ throw "Ubuntu asset SHA256 mismatch: $relative" }
  }
  & (Join-Path $ubuntu 'Install-TypeB-Ubuntu-WSL.ps1')
  Write-TypeBStage 'Linux profile' 'Preparing Linux tools for the existing Windows user; no application sign-in is needed.'
  # Derive a Linux name only after Windows OOBE created the real account.
  $linuxUser=$env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9_-]','-'
  if($linuxUser -notmatch '^[a-z_]'){ $linuxUser='user-'+$linuxUser }
  $linuxUser=$linuxUser.Substring(0,[Math]::Min(31,$linuxUser.Length))
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','-u','root','--exec','/usr/local/sbin/typeb-initialize-user',$linuxUser)
  Invoke-Wsl -Arguments @('--terminate','TypeB-Ubuntu-22.04')
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','-u','root','--exec','systemctl','start','docker.service')
  Invoke-Wsl -Arguments @('--set-default','TypeB-Ubuntu-22.04')
  Write-TypeBStage 'Docker and tools' 'Checking installed Linux tool versions and the running Docker daemon.'
  Invoke-Wsl -Arguments @('-d','TypeB-Ubuntu-22.04','--exec','bash','-lc','set -e; source /etc/profile.d/typeb-engineering.sh; git lfs version; ssh -V; curl --version; wget --version; tmux -V; ffmpeg -version; ffprobe -version; gcc --version; g++ --version; make --version; cmake --version; uv --version; conda --version; python --version; uv python find --python-preference only-managed 3.13; docker info; docker compose version')
  Add-Shortcut 'Ubuntu 22.04 WSL' (Join-Path $env:SystemRoot 'System32\wsl.exe') '-d TypeB-Ubuntu-22.04'

  $vmSource=Join-Path $ubuntu 'Ubuntu-22.04-VM'
  $vmDest=Join-Path $env:USERPROFILE 'Virtual Machines\TypeB-Ubuntu-22.04'
  $vmMarker=Join-Path $vmDest 'typeb-vm.json'
  $vmAttempt=Join-Path $vmDest 'typeb-vm-attempt.json'
  $vmEntry=@($lock.files | Where-Object relativePath -eq 'Ubuntu-22.04-VM/TypeB-Ubuntu-22.04.vmx')
  if($vmEntry.Count -ne 1){ throw 'Prepared VMX is not locked.' }
  if(Test-Path -LiteralPath $vmMarker){
    $owner=Get-Content -LiteralPath $vmMarker -Raw | ConvertFrom-Json
    if($owner.sourceVmxSha256 -ne $vmEntry[0].sha256){ throw 'A different Type B VM already exists in this profile.' }
  } else {
    if(Test-Path -LiteralPath $vmAttempt){
      $attemptOwner=Get-Content -LiteralPath $vmAttempt -Raw | ConvertFrom-Json
      if($attemptOwner.schemaVersion -ne 1 -or $attemptOwner.userSid -ne $sid -or $attemptOwner.sourceVmxSha256 -ne $vmEntry[0].sha256){throw 'Existing VM copy belongs to a different user or image.'}
    } elseif((Test-Path -LiteralPath $vmDest) -and @(Get-ChildItem -LiteralPath $vmDest -Force).Count){
      throw 'Unknown files in VM destination; they will not be overwritten.'
    }
    New-Item -ItemType Directory -Path $vmDest -Force | Out-Null
    Write-TypeBJson $vmAttempt ([ordered]@{schemaVersion=1;userSid=$sid;sourceVmxSha256=$vmEntry[0].sha256})
    $needed=[long]0
    foreach($item in Get-ChildItem -LiteralPath $vmSource -File -Recurse){
      $relativeFile=$item.FullName.Substring($vmSource.Length).TrimStart('\')
      $existing=Join-Path $vmDest $relativeFile
      if(-not (Test-Path -LiteralPath $existing) -or (Get-Item -LiteralPath $existing).Length -ne $item.Length){$needed+=$item.Length}
    }
    if((Get-TypeBFreeBytes $vmDest) -lt ($needed+2GB)){throw 'Not enough free guest disk space for the prepared VM copy.'}
    Write-TypeBStage 'Ubuntu VM' 'Copying the prepared VM. An interrupted installer-owned copy resumes automatically.'
    & robocopy.exe $vmSource $vmDest /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if($LASTEXITCODE -gt 7){ throw "Prepared VM copy failed: $LASTEXITCODE" }
    foreach($entry in @($lock.files | Where-Object relativePath -like 'Ubuntu-22.04-VM/*')){
      $file=Join-Path $vmDest (([string]$entry.relativePath).Substring('Ubuntu-22.04-VM/'.Length))
      Write-TypeBStage 'Ubuntu VM verification' ("Checking "+$entry.relativePath)
      if((Get-TypeBHash $file) -ne $entry.sha256){
        # A prior interrupted copy can have the right size/timestamp but bad bytes.
        # Repair only this locked file inside our unfinished, owned VM destination.
        Copy-Item -LiteralPath (Join-Path $ubuntu $entry.relativePath) -Destination $file -Force
        if((Get-TypeBHash $file) -ne $entry.sha256){throw 'Copied VM failed SHA256 verification after repair.'}
      }
    }
    [pscustomobject]@{sourceVmxSha256=$vmEntry[0].sha256} | ConvertTo-Json | Set-Content -LiteralPath $vmMarker -Encoding utf8
  }
  $vmx=Join-Path $vmDest 'TypeB-Ubuntu-22.04.vmx'
  if(-not (Test-Path -LiteralPath $vmx)){ throw 'Prepared VMX is missing from the user profile.' }
  $vmwareExecutable=Resolve-TypeBVmwareExecutable
  if (-not $vmwareExecutable) { throw 'A valid VMware Workstation executable was not found in either Program Files directory.' }
  Add-Shortcut 'Ubuntu 22.04 VM' $vmwareExecutable ('-n "'+$vmx+'"')
  Write-TypeBStage 'Complete' 'Required VS Code extensions, Ubuntu WSL 2, Docker and the prepared VMware VM passed their checks.' 'PASSED'
  Write-TypeBJson $complete ([ordered]@{schemaVersion=3;status='PASSED';timestamp=[DateTime]::UtcNow.ToString('o')})
  Remove-Item -LiteralPath $failed -ErrorAction SilentlyContinue
  Set-Content -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\TypeB-User-STATUS.txt') -Value 'TYPE B USER SETUP: PASSED. Ubuntu WSL2 and the prepared VM are available in Start > Type B.' -Encoding utf8
} catch {
  [pscustomobject]@{error=$_.Exception.Message;log=$log} | ConvertTo-Json | Set-Content -LiteralPath $failed -Encoding utf8
  Set-Content -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\TypeB-User-STATUS.txt') -Value ("TYPE B USER SETUP: FAILED. "+$_.Exception.Message+" See "+$log) -Encoding utf8
  $failureCode=1
  if($_.Exception.Data.Contains('TypeBExitCode')){$failureCode=[int]$_.Exception.Data['TypeBExitCode']}
  $failureStatus=if($failureCode -eq 20){'RESTART OR VIRTUALIZATION REQUIRED'}elseif($failureCode -eq 21){'ATTENTION REQUIRED'}else{'FAILED'}
  Write-TypeBStage 'Stopped' $_.Exception.Message $failureStatus
  exit $failureCode
} finally {
  try{ Stop-Transcript | Out-Null }catch{}
  if($held){$mutex.ReleaseMutex()};$mutex.Dispose()
}
exit 0
