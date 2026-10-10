#requires -version 5.1
[CmdletBinding()]
param([string]$VsixPath,[switch]$Native)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\TypeB-UserCommon.ps1')
$fixture=Join-Path $PSScriptRoot ('test-fixtures\vsix-'+[guid]::NewGuid().ToString('N'))
$packages=Join-Path $fixture 'packages'
$extensions=Join-Path $fixture 'extensions'
$userData=Join-Path $fixture 'user-data'
New-Item -ItemType Directory -Path $packages,$extensions -Force | Out-Null
if($Native -and -not $VsixPath){throw 'Native regression requires a real -VsixPath.'}
if(-not $VsixPath){
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $mockSource=Join-Path $fixture 'mock-vsix\extension'
    New-Item -ItemType Directory -Path $mockSource -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mockSource 'package.json'),'{"publisher":"charliermarsh","name":"ruff","version":"0.0.1","engines":{"vscode":"^1.75.0"}}')
    $VsixPath=Join-Path $fixture 'mock.vsix'
    $mockZip=[IO.Compression.ZipFile]::Open($VsixPath,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $mockEntry=$mockZip.CreateEntry('extension/package.json')
        $mockWriter=[IO.StreamWriter]::new($mockEntry.Open())
        try{$mockWriter.Write([IO.File]::ReadAllText((Join-Path $mockSource 'package.json')))}finally{$mockWriter.Dispose()}
    }finally{$mockZip.Dispose()}
}
Copy-Item -LiteralPath $VsixPath -Destination (Join-Path $packages 'charliermarsh.ruff.vsix')
$manifest=Join-Path $fixture 'vsix.json'
[IO.File]::WriteAllText($manifest,'{"required":["charliermarsh.ruff.vsix"]}')
$code=if($Native){(Get-Command code.cmd -ErrorAction Stop).Source}else{
    $dummyCode=Join-Path $fixture 'code.cmd'
    [IO.File]::WriteAllText($dummyCode,'@exit /b 1')
    $dummyCode
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($VsixPath)
try{
    $reader=[IO.StreamReader]::new($zip.GetEntry('extension/package.json').Open())
    try{$package=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}
}finally{$zip.Dispose()}
$expected=$package.publisher+'.'+$package.name+'@'+$package.version
$script:TypeBVsixTest_archive=Join-Path $packages 'charliermarsh.ruff.vsix'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
& {
    $script:TypeBVsixTest_calls=0
    function Invoke-TypeBCode {param($CodePath,$Arguments);$script:TypeBVsixTest_calls++;throw 'CLI should not start with missing archives'}
    [IO.File]::WriteAllText($manifest,'{"required":["charliermarsh.ruff.vsix","missing.extension.vsix"]}')
    $refused=$false
    try{Install-TypeBExtensions $packages $manifest $code $extensions $userData}catch{$refused=$_.Exception.Message -match 'Could not find file'}
    Assert ($refused -and $script:TypeBVsixTest_calls -eq 0) 'Missing archive did not refuse before CLI mutation'
    'PASS: missing local archive refuses before any CLI call'
}
[IO.File]::WriteAllText($manifest,'{"required":["charliermarsh.ruff.vsix"]}')
& {
    $script:TypeBVsixTest_installs=0
    function Invoke-TypeBCode {
        param($CodePath,$Arguments)
        if($Arguments -contains '--install-extension'){$script:TypeBVsixTest_installs++}
        return $expected
    }
    Install-TypeBExtensions $packages $manifest $code $extensions $userData
    Assert ($script:TypeBVsixTest_installs -eq 0) 'Matching registered version was reinstalled'
    'PASS: registered packaged version is not reinstalled on retry'
}
& {
    $script:TypeBVsixTest_installs=0
    function Invoke-TypeBCode {
        param($CodePath,$Arguments)
        if($Arguments -contains '--install-extension'){
            $script:TypeBVsixTest_installs++
            Assert ($Arguments -contains '--do-not-include-pack-dependencies') 'Optional extension packs could trigger target downloads'
            Assert ($Arguments -contains $script:TypeBVsixTest_archive) 'Installer did not receive the local archive'
        }
    }
    $refused=$false
    try{Install-TypeBExtensions $packages $manifest $code $extensions $userData}catch{$failure=$_.Exception.Message;$refused=$failure -match 'not registered at its packaged version'}
    Assert ($refused -and $script:TypeBVsixTest_installs -eq 1) "Exit zero without registration check failed: installs=$script:TypeBVsixTest_installs; error=$failure"
    'PASS: installer exit zero without registered extension cannot produce PASS'
}
if($Native){
    $unpacked=Join-Path $fixture 'unpacked'
    [IO.Compression.ZipFile]::ExtractToDirectory($VsixPath,$unpacked)
    $folder=$package.publisher+'.'+$package.name+'-'+$package.version
    Copy-Item -LiteralPath (Join-Path $unpacked 'extension') -Destination (Join-Path $extensions $folder) -Recurse
    [IO.File]::WriteAllText((Join-Path $extensions '.obsolete'),('{"'+$folder+'":true}'))
    [IO.File]::WriteAllText((Join-Path $extensions 'extensions.json'),'[]')
    $before=@(Invoke-TypeBCode $code @('--extensions-dir',$extensions,'--user-data-dir',$userData,'--list-extensions','--show-versions'))
    Assert ($before -notcontains $expected) 'Native regression fixture unexpectedly starts registered'
    Install-TypeBExtensions $packages $manifest $code $extensions $userData
    $after=@(Invoke-TypeBCode $code @('--extensions-dir',$extensions,'--user-data-dir',$userData,'--list-extensions','--show-versions'))
    Assert ($after -contains $expected) 'Real CLI did not repair empty index / obsolete state'
    'PASS: real VS Code CLI repairs copied extension with empty index and obsolete=true'
}
"Retained isolated fixture: $fixture"
