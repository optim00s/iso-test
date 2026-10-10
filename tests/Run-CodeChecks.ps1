#requires -version 5.1
[CmdletBinding()]
param([string]$PythonExe='python.exe')
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
$python=(Get-Command $PythonExe -ErrorAction Stop).Source
$windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$files=@(Get-ChildItem -LiteralPath (Join-Path $repository 'runtime'),(Join-Path $repository 'scripts'),$PSScriptRoot -Filter '*.ps1' -Recurse -File | Where-Object {$_.FullName -notmatch '\\test-fixtures\\|\\\.sha256-tests-|\\\.oscdimg-tests-'})
$files+=Get-Item -LiteralPath (Join-Path $repository 'Build-TypeB-ISO.ps1')
foreach($file in $files){
  $tokens=$null;$errors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ('PowerShell syntax error: '+$file.FullName)}
}
Write-Host ('PASS: all '+$files.Count+' PowerShell sources parse')
foreach($file in Get-ChildItem -LiteralPath (Join-Path $repository 'runtime') -File){
  if([IO.File]::ReadAllText($file.FullName) -match '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|winget\s+(install|download)|https?://'){throw 'Offline runtime contains a network primitive.'}
}
[xml]$answer=Get-Content -LiteralPath (Join-Path $repository 'overlay\Autounattend.xml') -Raw
if($answer.SelectSingleNode("//*[local-name()='LocalAccounts' or local-name()='AutoLogon' or local-name()='Password' or local-name()='ProductKey']")){throw 'Unattend contains precreated account/secret settings.'}
Write-Host 'PASS: offline runtime and no precreated Windows account in unattend'
foreach($test in @('Test-TypeBAutomation.ps1','Test-MediaIntegration.ps1','Test-VMwarePaths.ps1','Test-BuildPreflight.ps1','Test-VSCodeProvisioning.ps1','Test-SHA256Workflows.ps1','Test-OscdimgArguments.ps1')){
  & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
  if($LASTEXITCODE -ne 0){throw ('Code check failed: '+$test)}
}
& $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-QsyncPatch.ps1') -PythonExe $python
if($LASTEXITCODE -ne 0){throw 'Code check failed: Test-QsyncPatch.ps1'}
Write-Host 'CODE CHECKS PASSED. No binary assets were downloaded and no Windows/app/WSL installation was performed.'
Write-Host 'This is NOT a clean-install or physical USB boot acceptance result.'
