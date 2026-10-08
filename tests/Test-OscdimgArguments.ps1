#requires -version 5.1
[CmdletBinding()]
param(
  [string]$OscdimgPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Build-TypeB-ISO.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){ throw ($errors | Out-String) }
$assignment=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$boot'},$true)
$command=$ast.Find({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.Extent.Text.StartsWith('& $oscdimg ')},$true)
if(-not $assignment -or -not $command){ throw 'Builder boot assignment/native command not found.' }
$sandbox=Join-Path $PSScriptRoot ('.oscdimg-tests-'+[guid]::NewGuid().ToString('N')+' with spaces')
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
  $work=Join-Path $sandbox 'media with spaces'
  New-Item -ItemType Directory -Path $work | Out-Null
  $bios=Join-Path $work 'etfsboot.com'
  $uefi=Join-Path $work 'efisys.bin'
  Copy-Item -LiteralPath (Join-Path $root 'work\iso\boot\etfsboot.com') -Destination $bios
  Copy-Item -LiteralPath (Join-Path $root 'work\iso\efi\microsoft\boot\efisys.bin') -Destination $uefi
  'Oscdimg native-argument regression fixture.' | Set-Content -LiteralPath (Join-Path $work 'payload.txt') -Encoding ascii
  $OutputIso=Join-Path $sandbox 'result with spaces.iso'
  $oscdimg=$OscdimgPath
  . ([scriptblock]::Create($assignment.Extent.Text))
  & ([scriptblock]::Create($command.Extent.Text+"`nif(`$LASTEXITCODE -ne 0){ throw ('Oscdimg exit code: '+`$LASTEXITCODE) }"))
  if(-not (Test-Path -LiteralPath $OutputIso) -or (Get-Item -LiteralPath $OutputIso).Length -lt 1MB){ throw 'Small dual-boot ISO was not produced.' }
  Write-Host "PASS: real Oscdimg accepts builder arguments and paths with spaces (PowerShell $($PSVersionTable.PSVersion))."
} finally {
  $resolved=(Resolve-Path -LiteralPath $sandbox).Path
  $testsRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\')+'\'
  if(-not $resolved.StartsWith($testsRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^\.oscdimg-tests-[0-9a-f]{32} with spaces$'){ throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
