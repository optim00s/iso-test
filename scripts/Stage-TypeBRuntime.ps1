#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$MediaRoot)
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
$media=[IO.Path]::GetFullPath($MediaRoot)
if(-not (Test-Path -LiteralPath (Join-Path $media 'sources\boot.wim'))){throw 'Expected an extracted Windows media tree containing sources\boot.wim.'}
$oem=Join-Path $media 'sources\$OEM$\$1'
$scripts=Join-Path $oem 'TypeB-Offline\Scripts'
$ubuntu=Join-Path $oem 'TypeB-Assets\Ubuntu'
$config=Join-Path $oem 'TypeB-Offline\Config'
foreach($path in @((Join-Path $ubuntu 'ubuntu.lock.json'),(Join-Path $config 'vsix.json'),(Join-Path $config 'apps.json'))){
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Original Type B staged media is incomplete: $path"}
}
$lock=Get-Content -LiteralPath (Join-Path $ubuntu 'ubuntu.lock.json') -Raw | ConvertFrom-Json
if($lock.schemaVersion -ne 1 -or -not @($lock.files).Count){throw 'Invalid Ubuntu lock.'}
foreach($entry in $lock.files){
    $relative=[string]$entry.relativePath
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':'){throw 'Unsafe Ubuntu lock path.'}
    if($relative -eq 'Install-TypeB-Ubuntu-WSL.ps1'){throw 'This media locks the old importer. Update its source lock in the restored builder before integration.'}
    if(-not (Test-Path -LiteralPath (Join-Path $ubuntu $relative) -PathType Leaf)){throw "Missing locked Ubuntu asset: $relative"}
}
$manifest=Get-Content -LiteralPath (Join-Path $config 'vsix.json') -Raw | ConvertFrom-Json
if(@($manifest.required).Count -ne 6){throw 'Expected the six required VS Code extensions.'}
$source=Join-Path $repository 'runtime'
$files=@('Install-TypeB.ps1','Initialize-TypeBUser.ps1','Start-TypeBUserSetup.ps1','TypeB-UserCommon.ps1','Install-TypeB-Ubuntu-WSL.ps1')
foreach($name in $files){
    $path=Join-Path $source $name
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Invalid automation runtime: $name"}
}
$backup=Join-Path $repository ('work\runtime-backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
$written=New-Object 'Collections.Generic.List[object]'
foreach($name in $files){
    $target=if($name -eq 'Install-TypeB-Ubuntu-WSL.ps1'){Join-Path $ubuntu $name}else{Join-Path $scripts $name}
    $existed=Test-Path -LiteralPath $target
    if($existed){Copy-Item -LiteralPath $target -Destination (Join-Path $backup $name)}
    $written.Add([pscustomobject]@{source=Join-Path $source $name;target=$target;existed=$existed;backup=Join-Path $backup $name})
}
try{
    foreach($item in $written){
        Copy-Item -LiteralPath $item.source -Destination $item.target -Force
        if((Get-FileHash -LiteralPath $item.source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $item.target -Algorithm SHA256).Hash){throw 'Runtime copy SHA256 mismatch.'}
    }
    $hashes=@($written | ForEach-Object {[ordered]@{relativePath=$_.target.Substring($media.Length).TrimStart('\').Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.target -Algorithm SHA256).Hash.ToLowerInvariant()}})
    [ordered]@{schemaVersion=1;automationVersion=3;timestamp=[DateTime]::UtcNow.ToString('o');files=$hashes} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $config 'automation-runtime.json') -Encoding utf8
}catch{
    foreach($item in $written){
        if($item.existed){Copy-Item -LiteralPath $item.backup -Destination $item.target -Force}
        elseif(Test-Path -LiteralPath $item.target){Remove-Item -LiteralPath $item.target -Force}
    }
    throw
}
Write-Host 'Automation integrated into staged Windows media. This does not build an ISO or certify a cold installation.'
Write-Host 'Run the restored builder asset/security checks, create the final ISO and manifest, then perform an offline clean-install acceptance test.'
