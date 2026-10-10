#requires -version 5.1
$ErrorActionPreference='Stop'
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime'
. (Join-Path $runtime 'TypeB-UserCommon.ps1')
$testRoot=Join-Path $PSScriptRoot ('test-fixtures\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$savedLocalAppData=$env:LOCALAPPDATA
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-TypeBStage {param($Stage,$Message,$Status)}
function Get-TypeBBootId {return $global:TypeBTest_bootId}
function Get-TypeBFreeBytes {param($Path);return $global:TypeBTest_freeBytes}
function Test-Path {
    param([string]$Path,[string]$LiteralPath,[string]$PathType)
    if($Path -like 'HKCU:*'){return $true}
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Get-ChildItem {
    param([string]$Path,[string]$LiteralPath,[switch]$Force)
    if($Path -like 'HKCU:*'){return $global:TypeBTest_registrations}
    Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}
function Get-ItemProperty {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process{$InputObject}
}
function wsl.exe {
    param([Parameter(ValueFromRemainingArguments)]$Arguments)
    $global:LASTEXITCODE=0
    if($global:TypeBTest_otherRunning){return 'Unrelated-Distro'}
}
function reg.exe {
    param([Parameter(ValueFromRemainingArguments)]$Arguments)
    Assert ($Arguments[0] -eq 'export') 'Unexpected registry operation'
    [IO.File]::WriteAllText($Arguments[2],'mock registry backup')
    $global:LASTEXITCODE=0
}
function New-Registration([int]$State=3) {
    [pscustomobject]@{DistributionName='TypeB-Ubuntu-22.04';State=$State;Version=2;BasePath=$global:TypeBTest_location;VhdFileName='ext4.vhdx';PSPath='Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\TypeB-Test'}
}
function New-Owner([int]$Attempt=1) {
    [pscustomobject]@{schemaVersion=1;createdEmpty=$true;distroName='TypeB-Ubuntu-22.04';sha256=$global:TypeBTest_hash;installLocation=$global:TypeBTest_location;userSid=$sid;attemptCount=$Attempt;bootId='previous-boot'}
}
function Set-Fixture([string]$Name) {
    $global:TypeBTest_freeBytes=1TB
    $global:TypeBTest_fixture=Join-Path $testRoot $Name
    $env:LOCALAPPDATA=Join-Path $global:TypeBTest_fixture 'appdata'
    $global:TypeBTest_location=Join-Path $env:LOCALAPPDATA 'WSL\TypeB-Ubuntu-22.04'
    $global:TypeBTest_journal=Join-Path $env:LOCALAPPDATA 'TypeB\wsl-import-attempt.json'
    $global:TypeBTest_marker=Join-Path $global:TypeBTest_location 'typeb-image.json'
    New-Item -ItemType Directory -Path $global:TypeBTest_fixture,$env:LOCALAPPDATA -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $global:TypeBTest_fixture 'TypeB-Ubuntu-22.04-WSL-Docker.tar'),'locked test TAR')
    $global:TypeBTest_hash=(Get-FileHash -LiteralPath (Join-Path $global:TypeBTest_fixture 'TypeB-Ubuntu-22.04-WSL-Docker.tar') -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-TypeBJson (Join-Path $global:TypeBTest_fixture 'ubuntu.lock.json') ([ordered]@{schemaVersion=1;files=@(@{relativePath='TypeB-Ubuntu-22.04-WSL-Docker.tar';sha256=$global:TypeBTest_hash})})
    $text=[IO.File]::ReadAllText((Join-Path $runtime 'Install-TypeB-Ubuntu-WSL.ps1'))
    $text=$text.Replace(". 'C:\TypeB-Offline\Scripts\TypeB-UserCommon.ps1'",'# Common helpers are already loaded and native WSL is mocked by this test.')
    $global:TypeBTest_importer=Join-Path $global:TypeBTest_fixture 'Install-TypeB-Ubuntu-WSL.ps1'
    [IO.File]::WriteAllText($global:TypeBTest_importer,$text)
    $global:TypeBTest_registrations=@();$global:TypeBTest_imports=0;$global:TypeBTest_resets=0;$global:TypeBTest_mode='success';$global:TypeBTest_otherRunning=$false;$global:TypeBTest_bootId='current-boot'
}
function Invoke-TypeBWsl([string[]]$Arguments) {
    switch($Arguments[0]){
        '--import' {
            Assert ($Arguments.Count -eq 6 -and $Arguments[4] -eq '--version' -and $Arguments[5] -eq '2') 'Import arguments lost or WSL version not forced to 2'
            Assert (Test-Path -LiteralPath $global:TypeBTest_journal) 'Ownership must be persisted BEFORE import'
            $owner=Get-Content -LiteralPath $global:TypeBTest_journal -Raw | ConvertFrom-Json
            Assert (Test-TypeBAttemptOwner $owner $Arguments[1] $global:TypeBTest_hash $global:TypeBTest_location $sid) 'Incorrect advance ownership journal'
            $global:TypeBTest_imports++
            New-Item -ItemType Directory -Path $global:TypeBTest_location -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $global:TypeBTest_location 'ext4.vhdx'),'mock existing disk contents')
            $global:TypeBTest_registrations=@(New-Registration 3)
            if($global:TypeBTest_mode -eq 'interrupt'){throw 'Simulated interruption during import'}
            $global:TypeBTest_registrations=@(New-Registration 1)
        }
        '--shutdown' {}
        '--unregister' {
            Assert ($Arguments.Count -eq 2 -and $Arguments[1] -ceq 'TypeB-Ubuntu-22.04') 'Unexpected reset target'
            $backups=@(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'TypeB-Recovery') -Filter 'ext4.vhdx' -File -Recurse)
            Assert ($backups.Count -eq 1) 'Reset started without a full disk backup'
            Assert ([IO.File]::ReadAllText($backups[0].FullName) -eq 'mock existing disk contents') 'Backup contents changed'
            $owner=Get-Content -LiteralPath $global:TypeBTest_journal -Raw | ConvertFrom-Json
            Assert ($owner.attemptCount -eq 2) 'Recovery bound must be persisted BEFORE reset'
            $global:TypeBTest_resets++
            $global:TypeBTest_registrations=@()
            # This deletes only a tiny fake disk in the test fixture; no native WSL is invoked.
            $fake=Join-Path $global:TypeBTest_location 'ext4.vhdx'
            Assert ([IO.Path]::GetFullPath($fake).StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)) 'Unsafe fixture path'
            Remove-Item -LiteralPath $fake
        }
        '-d' {Assert ($Arguments -contains '/usr/local/sbin/typeb-initialize-user') 'Missing imported image check'}
        default {throw 'Unexpected mocked WSL command'}
    }
}
function Add-Partial {
    New-Item -ItemType Directory -Path $global:TypeBTest_location -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $global:TypeBTest_location 'ext4.vhdx'),'mock existing disk contents')
}
function Expect-Refusal([string]$Name) {
    $refused=$false
    try{& $global:TypeBTest_importer}catch{$refused=$true}
    Assert $refused "$Name unexpectedly succeeded"
    Assert ($global:TypeBTest_resets -eq 0 -and $global:TypeBTest_imports -eq 0) "$Name mutated WSL"
    "PASS: $Name refused without reset/import"
}
try {
    foreach($file in Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $runtime -Filter '*.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ("Syntax error: "+$file.Name)
    }
    'PASS: all runtime files parse under Windows PowerShell 5.1'
    Set-Fixture 'fresh'
    & $global:TypeBTest_importer
    Assert ($global:TypeBTest_imports -eq 1 -and $global:TypeBTest_resets -eq 0 -and (Test-Path -LiteralPath $global:TypeBTest_marker)) 'Fresh import did not complete'
    'PASS: fresh import writes advance ownership and final marker'
    Set-Fixture 'low-space'
    $global:TypeBTest_freeBytes=1MB
    Expect-Refusal 'Insufficient free space'
    Set-Fixture 'interrupted'
    $global:TypeBTest_mode='interrupt'
    try{& $global:TypeBTest_importer}catch{}
    Assert ($global:TypeBTest_imports -eq 1 -and -not (Test-Path -LiteralPath $global:TypeBTest_marker)) 'Interruption marker behavior incorrect'
    $global:TypeBTest_mode='success'
    $global:TypeBTest_bootId='next-boot'
    & $global:TypeBTest_importer
    Assert ($global:TypeBTest_imports -eq 2 -and $global:TypeBTest_resets -eq 1 -and (Test-Path -LiteralPath $global:TypeBTest_marker)) 'Automatic recovery failed'
    'PASS: interrupted import resumes once, with verified backup before reset'
    Set-Fixture 'same-boot';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    $owner=New-Owner;$owner.bootId=$global:TypeBTest_bootId;Write-TypeBJson $global:TypeBTest_journal $owner
    Expect-Refusal 'Same-boot recovery requires restart'
    Set-Fixture 'unknown';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    Expect-Refusal 'Unowned interrupted distro'
    Set-Fixture 'wrong-image';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    $owner=New-Owner;$owner.sha256=('0'*64);Write-TypeBJson $global:TypeBTest_journal $owner
    Expect-Refusal 'Different image journal'
    Set-Fixture 'exhausted';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    Write-TypeBJson $global:TypeBTest_journal (New-Owner 2)
    Expect-Refusal 'Exhausted automatic recovery'
    Set-Fixture 'foreign-path';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    $global:TypeBTest_registrations[0].BasePath='C:\Other-WSL'
    Write-TypeBJson $global:TypeBTest_journal (New-Owner)
    Expect-Refusal 'Foreign registration path'
    Set-Fixture 'other-running';Add-Partial;$global:TypeBTest_registrations=@(New-Registration)
    Write-TypeBJson $global:TypeBTest_journal (New-Owner);$global:TypeBTest_otherRunning=$true
    Expect-Refusal 'Unrelated running distro'
    Set-Fixture 'post-import-crash';Add-Partial;$global:TypeBTest_registrations=@(New-Registration 1)
    Write-TypeBJson $global:TypeBTest_journal (New-Owner)
    & $global:TypeBTest_importer
    Assert ($global:TypeBTest_imports -eq 0 -and $global:TypeBTest_resets -eq 0 -and (Test-Path -LiteralPath $global:TypeBTest_marker)) 'Post-import marker gap was not recovered'
    'PASS: successful import / missing marker gap is recovered without reset'
    Set-Fixture 'orphan';Add-Partial
    Write-TypeBJson $global:TypeBTest_journal (New-Owner)
    & $global:TypeBTest_importer
    $orphans=@(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'TypeB-Recovery') -Filter ext4.vhdx -Recurse -File)
    Assert ($global:TypeBTest_imports -eq 1 -and $global:TypeBTest_resets -eq 0 -and $orphans.Count -eq 1) 'Owned orphan was not preserved'
    'PASS: owned orphan directory is preserved before fresh import'
    Set-Fixture 'bad-tar'
    [IO.File]::AppendAllText((Join-Path $global:TypeBTest_fixture 'TypeB-Ubuntu-22.04-WSL-Docker.tar'),'CORRUPTION')
    Expect-Refusal 'Corrupted TAR'
    $sentinel=Join-Path $testRoot 'completion.json'
    [IO.File]::WriteAllText($sentinel,'partial')
    Assert (-not (Test-TypeBComplete $sentinel)) 'Partial completion marker was accepted'
    Write-TypeBJson $sentinel ([ordered]@{schemaVersion=3;status='PASSED'})
    Assert (Test-TypeBComplete $sentinel) 'Valid completion marker was refused'
    'PASS: partial completion marker cannot suppress preparation'
    $nativeHash=(Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ((Get-TypeBHash $sentinel) -eq $nativeHash) 'Streaming SHA256 differs from Get-FileHash'
    'PASS: progress-reporting SHA256 matches Windows SHA256'
    $large=Join-Path $testRoot 'multiple-blocks.bin'
    $buffer=New-Object byte[] (1MB)
    [Random]::new(42).NextBytes($buffer)
    $stream=[IO.File]::Create($large)
    try{for($block=0;$block -lt 9;$block++){$stream.Write($buffer,0,$buffer.Length)}}finally{$stream.Dispose()}
    Assert ((Get-TypeBHash $large) -eq (Get-FileHash -LiteralPath $large -Algorithm SHA256).Hash.ToLowerInvariant()) 'Multi-block hash mismatch'
    'PASS: multi-block SHA256 matches Windows SHA256'
    $empty=Join-Path $testRoot 'empty.bin'
    [IO.File]::WriteAllBytes($empty,[byte[]]@())
    Assert ((Get-TypeBHash $empty) -eq (Get-FileHash -LiteralPath $empty -Algorithm SHA256).Hash.ToLowerInvariant()) 'Empty-file hash mismatch'
    'PASS: empty-file SHA256 matches Windows SHA256'
    & {
        $tokens=$null;$errors=$null
        $commonAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $runtime 'TypeB-UserCommon.ps1'),[ref]$tokens,[ref]$errors)
        $wrapper=$commonAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-TypeBWsl'},$true)
        . ([scriptblock]::Create($wrapper.Extent.Text))
        function wsl.exe {
            param([Parameter(ValueFromRemainingArguments)]$Arguments)
            Assert ((Get-Location).Path -eq $env:USERPROFILE) 'WSL inherited the recovery media working directory'
            Assert ($Arguments.Count -eq 4 -and $Arguments[0] -eq '-d' -and $Arguments[3] -eq 'true') 'WSL native arguments changed'
            $global:LASTEXITCODE=0
        }
        Push-Location -LiteralPath $testRoot
        try{
            $before=(Get-Location).Path
            Invoke-TypeBWsl -Arguments @('-d','TypeB-Ubuntu-22.04','--exec','true')
            Assert ((Get-Location).Path -eq $before) 'WSL wrapper did not restore its caller directory'
        }finally{Pop-Location}
    }
    'PASS: native WSL starts from the user profile, preserves arguments and restores caller directory'
    'All fault-injection checks passed. Real guest import and cold installation are still required.'
    "Tiny retained fixtures: $testRoot"
}finally{$env:LOCALAPPDATA=$savedLocalAppData}
