#requires -version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TypeB-UserCommon.ps1')
$script='C:\TypeB-Offline\Scripts\Initialize-TypeBUser.ps1'
$state=Join-Path $env:LOCALAPPDATA 'TypeB'
if(Test-TypeBComplete (Join-Path $state 'first-logon.complete')){exit 0}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -eq 'S-1-5-18' -or $sid -match '-500$'){exit 21}
$mutex=[Threading.Mutex]::new($false,('Local\TypeB-Launcher-'+$sid))
$held=$false
try {
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){exit 0}
    for($attempt=1;$attempt -le 3;$attempt++){
        & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $script
        $code=$LASTEXITCODE
        if($code -eq 0 -or $code -eq 20 -or $code -eq 21){exit $code}
        if($attempt -lt 3){Start-Sleep -Seconds 30}
    }
    exit 1
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}

