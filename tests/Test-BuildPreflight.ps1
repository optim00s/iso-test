#requires -version 5.1
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('test-fixtures\preflight-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts'),(Join-Path $fixture 'config'),(Join-Path $fixture 'assets') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'scripts\Get-TypeBBuildPlan.ps1') -Destination (Join-Path $fixture 'scripts\Get-TypeBBuildPlan.ps1')
Copy-Item -LiteralPath (Join-Path $repository 'config\build.json') -Destination (Join-Path $fixture 'config\build.json')
$source=Join-Path $fixture 'source with spaces.iso'
$output=Join-Path $fixture 'output\result.iso'
[IO.File]::WriteAllText($source,'tiny untrusted source fixture')
$lockPath=Join-Path $fixture 'config\assets.lock.json'
@{schemaVersion=1;files=@(@{relativePath='missing.exe';size=1;sha256=('a'*64)})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath
$plan=& (Join-Path $fixture 'scripts\Get-TypeBBuildPlan.ps1') -SourceIso $source -OutputIso $output
if($plan.preflightReady -or $plan.willWriteFiles -or @($plan.missingOrWrongSize).Count -ne 1 -or (Test-Path (Join-Path $fixture 'work')) -or (Test-Path (Split-Path $output -Parent))){throw 'Incomplete assets did not produce a read-only refusal plan'}
'PASS: missing assets reported without creating media/output'
@{schemaVersion=1;files=@(@{relativePath='large-missing.vmdk';size=([long]1TB);sha256=('a'*64)})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath
$plan=& (Join-Path $fixture 'scripts\Get-TypeBBuildPlan.ps1') -SourceIso $source -OutputIso $output
if($plan.enoughSpace -or $plan.requiredWorkFreeGiB -lt 2048){throw 'Stage plus output disk budget was not enforced'}
'PASS: large locked image requires enough space for staging AND output'
@{schemaVersion=1;files=@(@{relativePath='../outside.exe';size=1;sha256=('a'*64)})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath
$refused=$false
try{& (Join-Path $fixture 'scripts\Get-TypeBBuildPlan.ps1') -SourceIso $source -OutputIso $output | Out-Null}catch{$refused=$_.Exception.Message -match 'Unsafe'}
if(-not $refused){throw 'Unsafe locked path accepted'}
'PASS: unsafe lock path refuses before writes'
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
[IO.File]::WriteAllText($output,'existing ISO')
$before=(Get-FileHash -LiteralPath $output).Hash
$refused=$false
try{& (Join-Path $fixture 'scripts\Get-TypeBBuildPlan.ps1') -SourceIso $source -OutputIso $output | Out-Null}catch{$refused=$_.Exception.Message -match 'overwritten'}
if(-not $refused -or (Get-FileHash -LiteralPath $output).Hash -ne $before){throw 'Existing output was not preserved'}
'PASS: existing ISO refuses overwrite and remains unchanged'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repository 'Build-TypeB-ISO.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Builder syntax error'}
$stageCalls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.Extent.Text -match "^& \(Join-Path .+scripts\\Stage-TypeBRuntime\.ps1"},$true))
$isoCall=$ast.Find({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.Extent.Text.StartsWith('& $oscdimg ')},$true)
if($stageCalls.Count -ne 1 -or -not $isoCall -or $stageCalls[0].Extent.StartOffset -ge $isoCall.Extent.StartOffset){throw 'Mandatory runtime staging must precede ISO creation'}
'PASS: builder stages canonical recovery fixes before oscdimg'
