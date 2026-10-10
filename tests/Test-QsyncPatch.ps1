#requires -version 5.1
param([Parameter(Mandatory=$true)][string]$PythonExe)
$ErrorActionPreference='Stop'
$tokens=$null; $parseErrors=$null
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\Install-TypeB.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){ throw ($parseErrors | Out-String) }
# Load ONLY function definitions: never run the installer pipeline on the host.
foreach($name in @('Write-Status','Test-ExitCode','Test-QsyncReady','Get-QsyncChildren','Invoke-QsyncInstall')) {
    $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false) | Where-Object Name -eq $name
    if(@($definition).Count -ne 1){ throw "Missing or duplicate function: $name" }
    Invoke-Expression $definition.Extent.Text
}
$originalDetection=(Get-Command Test-QsyncReady).ScriptBlock
$script:registration=$true; $script:payload=$true
$script:servicePath='"C:\Program Files (x86)\QNAP\Qsync\QsyncSvc.exe"'
$script:folder=$null; $script:ready=$true; $script:trackingFailure=$false
function Test-Detection($Detect){ return $script:registration }
function Test-Path { param($LiteralPath) return $script:payload }
function Get-CimInstance {
    param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction)
    if($ClassName -eq 'Win32_Service'){ return [pscustomobject]@{PathName=$script:servicePath} }
    if($script:trackingFailure){ throw 'Fixture: process tracking unavailable.' }
    if($script:folder -and [IO.File]::Exists((Join-Path $script:folder 'child.json'))){
        $record=Get-Content -LiteralPath (Join-Path $script:folder 'child.json') -Raw | ConvertFrom-Json
        if(Get-Process -Id $record.child -ErrorAction SilentlyContinue){
            return [pscustomobject]@{ProcessId=$record.child;ParentProcessId=$record.parent;ExecutablePath=$PythonExe}
        }
    }
    return @()
}
function Assert($Condition,[string]$Message){ if(-not $Condition){ throw $Message }; Write-Host "PASS: $Message" }
$app=[pscustomobject]@{name='QNAP Qsync Client';detect=@{type='fixture'};args=''}
Assert (Test-QsyncReady $app) 'Registry + files + matching service are required.'
$script:registration=$false
Assert (-not (Test-QsyncReady $app)) 'Files/service alone cannot produce PASS.'
$script:registration=$true; $script:payload=$false
Assert (-not (Test-QsyncReady $app)) 'Missing payload cannot produce PASS.'
$script:payload=$true; $script:servicePath='C:\wrong\QsyncSvc.exe'
Assert (-not (Test-QsyncReady $app)) 'Wrong service executable cannot produce PASS.'
function Test-QsyncReady($App){ return $script:ready }
Remove-Item function:Test-Path
function Run-Fixture([string]$Mode,[int]$Timeout=5,[bool]$Ready=$true){
    $script:folder=Join-Path $env:TEMP ('typeb-qsync-test-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:folder | Out-Null
    $script:ready=$Ready
    $app.args='"'+(Join-Path $PSScriptRoot 'installer-fixture.py')+'" '+$Mode+' "'+$script:folder+'"'
    $errorText=$null
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try { Invoke-QsyncInstall $app $PythonExe -TimeoutSeconds $Timeout }
    catch { $errorText=$_.Exception.Message }
    $timer.Stop()
    $attempts=@(Get-Content -LiteralPath (Join-Path $script:folder 'attempts.txt')).Count
    return [pscustomobject]@{error=$errorText;attempts=$attempts;seconds=$timer.Elapsed.TotalSeconds;folder=$script:folder}
}
$r=Run-Fixture 'child'
$child=Get-Content -LiteralPath (Join-Path $r.folder 'child.json') -Raw | ConvertFrom-Json
Assert (-not $r.error -and $r.seconds -lt 5 -and (Get-Process -Id $child.child -ErrorAction SilentlyContinue)) 'Successful parent returns while persistent child remains alive.'
$r=Run-Fixture 'reboot'
Assert (-not $r.error -and $r.attempts -eq 1) 'Exit 3010 is accepted only with installation verification.'
$r=Run-Fixture 'retry'
Assert (-not $r.error -and $r.attempts -eq 2) 'Failed exit is retried once and successful retry is validated.'
$r=Run-Fixture 'fail'
Assert ($r.error -match 'exit code 7' -and $r.attempts -eq 2) 'Repeated failure stops after two attempts.'
$r=Run-Fixture 'failed-child'
Assert ($r.error -match 'exit code 7' -and $r.attempts -eq 1) 'Active tracked child prevents an overlapping retry.'
$baseCim=(Get-Command Get-CimInstance).ScriptBlock
function Get-CimInstance {
    param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction)
    if($script:folder -and [IO.File]::Exists((Join-Path $script:folder 'attempts.txt'))){ throw 'Fixture: tracking failed after starting the process.' }
    return @()
}
$script:folder=$null
$r=Run-Fixture 'fail'
Assert ($r.error -match 'trackingOK=False' -and $r.attempts -eq 1) 'Unavailable child tracking disables automatic retry.'
Set-Item function:Get-CimInstance -Value $baseCim
$r=Run-Fixture 'hang' 1
$parent=Get-Content -LiteralPath (Join-Path $r.folder 'parent.json') -Raw | ConvertFrom-Json
Assert ($r.error -match 'timed out' -and $r.attempts -eq 1 -and $r.seconds -lt 8 -and -not (Get-Process -Id $parent.parent -ErrorAction SilentlyContinue)) 'Timeout stops only its own parent and does not retry.'
$r=Run-Fixture 'success' 2 $false
Assert ($r.error -match 'verification did not pass' -and $r.attempts -eq 1 -and $r.seconds -lt 8) 'Successful exit without installed product remains a failure.'
$text=[IO.File]::ReadAllText($source)
Assert ($text.Contains("if (`$app.id -eq 'qsync') { Invoke-QsyncInstall `$app `$path } else { Start-LocalExe `$path ([string]`$app.args) `$app.name }")) 'New wait behavior is scoped to Qsync.'
Assert ($text.Contains("`$requiredFailures=@(`$results | Where-Object status -eq 'FAIL')")) 'Required application failure prevents the overall completion marker.'
Write-Host 'Qsync patch checks: PASS. No application was installed; only harmless fixture processes ran.'
