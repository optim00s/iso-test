#requires -version 5.1
$ErrorActionPreference='Stop'
$automation=$PSScriptRoot
$repository=Split-Path $PSScriptRoot -Parent
$media=Join-Path $automation ('test-fixtures\media-'+[guid]::NewGuid().ToString('N'))
$oem=Join-Path $media 'sources\$OEM$\$1'
$scripts=Join-Path $oem 'TypeB-Offline\Scripts'
$config=Join-Path $oem 'TypeB-Offline\Config'
$ubuntu=Join-Path $oem 'TypeB-Assets\Ubuntu'
New-Item -ItemType Directory -Path $scripts,$config,$ubuntu -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $media 'sources\boot.wim'),'fake Windows boot fixture')
foreach($path in @((Join-Path $scripts 'Install-TypeB.ps1'),(Join-Path $scripts 'Initialize-TypeBUser.ps1'),(Join-Path $ubuntu 'Install-TypeB-Ubuntu-WSL.ps1'))){
    [IO.File]::WriteAllText($path,'# old fixture runtime')
}
[IO.File]::WriteAllText((Join-Path $config 'apps.json'),'[]')
@{required=@('ms-python.python.vsix','ms-python.vscode-pylance.vsix','ms-toolsai.jupyter.vsix','charliermarsh.ruff.vsix','ms-vscode-remote.remote-ssh.vsix','ms-vscode-remote.remote-wsl.vsix')} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $config 'vsix.json')
@{schemaVersion=1;files=@(@{relativePath='missing.tar';sha256=('0'*64)})} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ubuntu 'ubuntu.lock.json')
$rejected=$false
try{& (Join-Path $repository 'scripts\Stage-TypeBRuntime.ps1') -MediaRoot $media}
catch{$rejected=$_.Exception.Message -match 'Missing locked Ubuntu asset'}
if(-not $rejected -or [IO.File]::ReadAllText((Join-Path $scripts 'Install-TypeB.ps1')) -ne '# old fixture runtime'){
    throw 'Missing assets must refuse integration before writes, for the expected reason.'
}
'PASS: missing locked assets refuse integration before writes'
[IO.File]::WriteAllText((Join-Path $ubuntu 'missing.tar'),'fake prepared tar')
& (Join-Path $repository 'scripts\Stage-TypeBRuntime.ps1') -MediaRoot $media
$manifest=Get-Content -LiteralPath (Join-Path $config 'automation-runtime.json') -Raw | ConvertFrom-Json
if($manifest.files.Count -ne 5){throw 'Runtime manifest has wrong file count.'}
foreach($entry in $manifest.files){
    if((Get-FileHash -LiteralPath (Join-Path $media $entry.relativePath) -Algorithm SHA256).Hash -ne $entry.sha256){
        throw 'Integrated runtime manifest does not match staged bytes.'
    }
}
'PASS: all five runtime files integrate with matching SHA256 manifest'
'No real Windows media or VM was modified by this fixture test.'
