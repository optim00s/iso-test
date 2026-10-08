#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Repository=Split-Path $PSScriptRoot -Parent
$Sandbox=Join-Path $PSScriptRoot ('.sha256-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Sandbox | Out-Null
$global:TypeBShaTestChecks=0
$global:TypeBShaTestState=@{}

function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $global:TypeBShaTestChecks++
}
function Assert-Throws([scriptblock]$Action,[string]$Pattern) {
    $caught=$null
    try { & $Action } catch { $caught=$_.Exception.Message }
    Assert ($caught -and $caught -match $Pattern) "Expected failure matching '$Pattern'; got '$caught'"
}
function New-Case([string]$Name) {
    $case=Join-Path $Sandbox $Name
    New-Item -ItemType Directory -Path (Join-Path $case 'scripts'),(Join-Path $case 'assets\linux'),(Join-Path $case 'assets\office') -Force | Out-Null
    foreach ($name in @('Prepare-OfficeOffline.ps1','Acquire-UbuntuAssets.ps1','Acquire-LinuxBaseline.ps1','Build-DockerReady-UbuntuWSL.ps1')) {
        $text=Get-Content -LiteralPath (Join-Path $Repository "scripts\$name") -Raw
        # Test only copied scripts with mocked WSL; never invoke real elevated actions.
        $text=$text -replace '(?m)^#requires -RunAsAdministrator\r?\n',''
        $text | Set-Content -LiteralPath (Join-Path $case "scripts\$name") -Encoding utf8
    }
    New-Item -ItemType Directory -Path (Join-Path $case 'config'),(Join-Path $case 'scripts\linux'),(Join-Path $case 'assets\linux\baseline') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Repository 'config\linux-baseline.json') -Destination (Join-Path $case 'config\linux-baseline.json')
    Copy-Item -LiteralPath (Join-Path $Repository 'scripts\linux\Provision-TypeB-Ubuntu.sh') -Destination (Join-Path $case 'scripts\linux\Provision-TypeB-Ubuntu.sh')
    $config=Get-Content (Join-Path $case 'config\linux-baseline.json') -Raw | ConvertFrom-Json
    $baselineLines=foreach($file in @($config.uvArchive,$config.anacondaInstaller)){
      $full=Join-Path $case ('assets\linux\baseline\'+$file)
      'baseline fixture' | Set-Content -LiteralPath $full -Encoding ascii
      "$( (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant())  $file"
    }
    $baselineLines | Set-Content -LiteralPath (Join-Path $case 'assets\linux\baseline\SHA256SUMS') -Encoding ascii
    $global:TypeBShaTestState=@{Root=$case; Downloads=0; Calls=(New-Object Collections.Generic.List[string]); Corrupt=$false; Missing=$false; Duplicate=$false; Existing='Personal-Ubuntu'; BashFailure=$false; ExportFailure=$false; Signature='Valid'; ProcessFailure=$false}
    return $case
}
function Get-PayloadHash([string]$Name) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes("fixture:$Name")))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Invoke-WebRequest {
    param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing)
    if ($Uri.EndsWith('.sha256')) {
        $name=$Uri.Substring($Uri.LastIndexOf('/')+1) -replace '\.sha256$',''
        $line="$(Get-PayloadHash $name)  $name`n"
        if ($global:TypeBShaTestState.InvalidUvChecksum) { $line='not a checksum' }
        if ($global:TypeBShaTestState.WrongUvFilename) { $line="$(Get-PayloadHash $name)  wrong-archive.tar.gz" }
        if ($global:TypeBShaTestState.UvChecksumText) { return [pscustomobject]@{Content=$line} }
        return [pscustomobject]@{Content=[Text.Encoding]::UTF8.GetBytes($line)}
    } elseif ($Uri.EndsWith('/SHA256SUMS')) {
        $name=if ($Uri -match 'cloud-images') { 'ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz' } else { 'ubuntu-22.04.5-desktop-amd64.iso' }
        $line="$(Get-PayloadHash $name) *$name"
        if ($global:TypeBShaTestState.Missing) { $line="$(Get-PayloadHash $name) *wrong-file" }
        if ($global:TypeBShaTestState.Duplicate) { $line+="`n$line" }
        $line | Set-Content -LiteralPath $OutFile -Encoding ascii
    } else {
        $global:TypeBShaTestState.Downloads++
        $name=$Uri.Substring($Uri.LastIndexOf('/')+1)
        $content=if ($global:TypeBShaTestState.Corrupt) { 'corrupted' } else { "fixture:$name" }
        [IO.File]::WriteAllText($OutFile,$content,[Text.Encoding]::ASCII)
    }
}
function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    $status=$global:TypeBShaTestState.Signature
    if($LiteralPath -match '\.odt-extract-' -and $global:TypeBShaTestState.ExtractedSignature){ $status=$global:TypeBShaTestState.ExtractedSignature }
    [pscustomobject]@{Status=$status; SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'}}
}
function Start-Process {
    param([string]$FilePath,[string]$ArgumentList,[string]$WorkingDirectory,[string]$WindowStyle,[switch]$Wait,[switch]$PassThru)
    if($ArgumentList -match '^/quiet /extract:"([^"]+)"$'){
        $directory=$Matches[1]
        if($global:TypeBShaTestState.ExtractionFailure){ return [pscustomobject]@{ExitCode=9} }
        'extracted ODT fixture' | Set-Content -LiteralPath (Join-Path $directory 'setup.exe') -Encoding ascii
        return [pscustomobject]@{ExitCode=0}
    }
    $downloadConfig=$ArgumentList.Substring('/download '.Length).Trim('"')
    [xml]$xml=Get-Content -LiteralPath $downloadConfig -Raw
    Assert ($xml.Configuration.Add.SourcePath -eq $WorkingDirectory) 'Office download path must point to local staging'
    $data=Join-Path $WorkingDirectory 'Office\Data'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    'office fixture' | Set-Content -LiteralPath (Join-Path $data 'payload.cab') -Encoding ascii
    [pscustomobject]@{ExitCode=$(if($global:TypeBShaTestState.ProcessFailure){7}else{0})}
}
function wsl.exe {
    $global:TypeBShaTestState.Calls.Add(($args -join ' '))
    $global:LASTEXITCODE=0
    switch ($args[0]) {
        '-l' { return $global:TypeBShaTestState.Existing }
        '--import' { return }
        '--terminate' { return }
        '--unregister' { return }
        '--export' {
            if ($global:TypeBShaTestState.ExportFailure) { $global:LASTEXITCODE=8; return }
            'docker tar fixture' | Set-Content -LiteralPath $args[2] -Encoding ascii
            return
        }
        '-d' {
            if ($args -contains 'wslpath' -or $args -contains 'bash' -or $args -contains 'cat') {
                Assert ($args -contains '--exec') 'Linux commands must bypass default-shell argument parsing'
            }
            if ($args -contains 'cat') {
                $checks=@{}
                foreach($name in @('git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose')){ $checks[$name]=$true }
                return ([pscustomobject]@{ubuntuVersion='22.04';mode='wsl';python='Python 3.13.5';checks=$checks} | ConvertTo-Json -Depth 5)
            }
            if ($args -contains 'wslpath') {
                Assert ($args[$args.Count-1] -match '^[A-Za-z]:\\') 'Windows path must reach wslpath with its backslashes intact'
                return '/mock/prepare.sh'
            }
            if ($args -contains 'bash') {
                $bashFile=Get-ChildItem -LiteralPath (Join-Path $global:TypeBShaTestState.Root 'assets\linux') -Filter prepare.sh -Recurse -File | Select-Object -First 1
                $bytes=[IO.File]::ReadAllBytes($bashFile.FullName)
                Assert (-not ($bytes -contains 13)) 'Bash script must have LF endings'
                Assert ($bytes[0] -eq [byte][char]'#') 'Bash script must not have a BOM'
                if ($global:TypeBShaTestState.BashFailure) { $global:LASTEXITCODE=9 }
                return
            }
        }
    }
    throw "Unexpected mocked WSL call: $args"
}
function New-Source([string]$Case) {
    $source=Join-Path $Case 'assets\linux\ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz'
    'source fixture' | Set-Content -LiteralPath $source -Encoding ascii
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash *$([IO.Path]::GetFileName($source))" | Set-Content -LiteralPath (Join-Path $Case 'assets\linux\wsl-SHA256SUMS') -Encoding ascii
    return $source
}
function New-Office([string]$Case) {
    'setup fixture' | Set-Content -LiteralPath (Join-Path $Case 'assets\office\setup.exe') -Encoding ascii
    '<Configuration><Add SourcePath="C:\TypeB-Offline\Packages\office" /></Configuration>' | Set-Content -LiteralPath (Join-Path $Case 'assets\office\configuration.xml') -Encoding ascii
}

try {
    foreach ($mode in @('bytes','text','invalid','wrong-filename','corrupt')) {
        $case=New-Case "linux-baseline-$mode"
        $baselineDirectory=Join-Path $case 'assets\linux\baseline'
        Get-ChildItem -LiteralPath $baselineDirectory -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        $baselineConfigPath=Join-Path $case 'config\linux-baseline.json'
        $baselineConfig=Get-Content -LiteralPath $baselineConfigPath -Raw | ConvertFrom-Json
        $baselineConfig.anacondaSha256=Get-PayloadHash $baselineConfig.anacondaInstaller
        $baselineConfig | ConvertTo-Json | Set-Content -LiteralPath $baselineConfigPath -Encoding utf8
        $global:TypeBShaTestState.UvChecksumText=($mode -eq 'text')
        $global:TypeBShaTestState.InvalidUvChecksum=($mode -eq 'invalid')
        $global:TypeBShaTestState.WrongUvFilename=($mode -eq 'wrong-filename')
        $global:TypeBShaTestState.Corrupt=($mode -eq 'corrupt')
        $acquireBaseline=Join-Path $case 'scripts\Acquire-LinuxBaseline.ps1'
        if ($mode -in @('bytes','text')) {
            & $acquireBaseline
            Assert ($global:TypeBShaTestState.Downloads -eq 2) 'Baseline must download and verify uv and Anaconda'
            $baselineManifest=Get-Content -LiteralPath (Join-Path $baselineDirectory 'SHA256SUMS')
            Assert ($baselineManifest.Count -eq 2 -and $baselineManifest[0] -eq "$(Get-PayloadHash $baselineConfig.uvArchive)  $($baselineConfig.uvArchive)") 'Binary and text checksum responses must produce the correct manifest'
            $manifestBytes=[IO.File]::ReadAllBytes((Join-Path $baselineDirectory 'SHA256SUMS'))
            Assert (-not ($manifestBytes -contains 13)) 'Linux checksum manifest must use LF line endings'
            Assert ($manifestBytes[0] -eq [byte][char]$baselineManifest[0][0]) 'Linux checksum manifest must not have a BOM'
            & $acquireBaseline
            Assert ($global:TypeBShaTestState.Downloads -eq 2) 'Valid baseline installers must be reused'
            'tampered' | Set-Content -LiteralPath (Join-Path $baselineDirectory $baselineConfig.uvArchive)
            Assert-Throws { & $acquireBaseline } 'SHA256 mismatch'
        } else {
            $pattern=if ($mode -eq 'corrupt') {'SHA256 mismatch'} else {'Cannot parse'}
            Assert-Throws { & $acquireBaseline } $pattern
            Assert (-not (Test-Path -LiteralPath (Join-Path $baselineDirectory 'SHA256SUMS'))) 'Failed baseline acquisition must not create a manifest'
            Assert (-not (Test-Path -LiteralPath (Join-Path $baselineDirectory $baselineConfig.uvArchive))) 'Unverified uv payload must not be promoted'
        }
        Assert (-not @(Get-ChildItem -LiteralPath $baselineDirectory -Filter '*.partial').Count) 'Baseline temporary downloads must be cleaned'
    }

    $case=New-Case 'ubuntu-good'
    & (Join-Path $case 'scripts\Acquire-UbuntuAssets.ps1')
    Assert ($global:TypeBShaTestState.Downloads -eq 2) 'Both Ubuntu artifacts must download'
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $case 'assets\linux') -Filter *.sha256) {
        $asset=$file.FullName.Substring(0,$file.FullName.Length-7)
        Assert ((Get-Content $file.FullName).StartsWith((Get-FileHash $asset -Algorithm SHA256).Hash.ToLowerInvariant())) 'Ubuntu sidecar must match content'
    }
    & (Join-Path $case 'scripts\Acquire-UbuntuAssets.ps1')
    Assert ($global:TypeBShaTestState.Downloads -eq 2) 'Existing valid assets must be reused'
    'tampered' | Set-Content -LiteralPath (Join-Path $case 'assets\linux\ubuntu-22.04.5-desktop-amd64.iso')
    Assert-Throws { & (Join-Path $case 'scripts\Acquire-UbuntuAssets.ps1') } 'SHA256 mismatch'
    Assert (-not @(Get-ChildItem (Join-Path $case 'assets\linux') -Filter *.partial).Count) 'Temporary Ubuntu files must be cleaned'

    foreach ($mode in @('Corrupt','Missing','Duplicate')) {
        $case=New-Case "ubuntu-$mode"
        $global:TypeBShaTestState[$mode]=$true
        $pattern=if($mode -eq 'Corrupt'){'SHA256 mismatch'}else{'exactly one'}
        Assert-Throws { & (Join-Path $case 'scripts\Acquire-UbuntuAssets.ps1') } $pattern
        Assert (-not (Test-Path (Join-Path $case 'assets\linux\ubuntu-22.04.5-desktop-amd64.iso'))) 'Invalid download must not be promoted'
        Assert (-not @(Get-ChildItem (Join-Path $case 'assets\linux') -Filter *.partial).Count) 'Failed download temporary files must be cleaned'
    }

    $case=New-Case 'office-good'
    New-Office $case
    & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1')
    & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -VerifyOnly
    [xml]$original=Get-Content (Join-Path $case 'assets\office\configuration.xml')
    Assert ($original.Configuration.Add.SourcePath -eq 'C:\TypeB-Offline\Packages\office') 'Deployment SourcePath must be preserved'
    'tampered' | Set-Content (Join-Path $case 'assets\office\Office\Data\payload.cab')
    Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -VerifyOnly } 'SHA256 verification failed'
    Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -ExpectedSetupSha256 ('0'*64) } 'SHA256 mismatch'
    $global:TypeBShaTestState.Signature='NotSigned'
    Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') } 'valid Microsoft Authenticode'
    $case=New-Case 'office-failure'
    New-Office $case
    $global:TypeBShaTestState.ProcessFailure=$true
    Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') } 'exit code 7'
    Assert (-not @(Get-ChildItem (Join-Path $case 'assets\office') -Filter .download-*.xml -Force).Count) 'Temporary Office configuration must be cleaned'
    Assert (-not (Test-Path (Join-Path $case 'assets\office\SHA256SUMS'))) 'Failed Office download must not produce a manifest'

    $case=New-Case 'office-extractor'
    New-Office $case
    $setup=Join-Path $case 'assets\office\setup.exe'
    [IO.File]::WriteAllText($setup,'SYS.ARGS.EXTRACTPATH The Microsoft Office 2016 Click-to-Run Administrator Tool',[Text.Encoding]::Unicode)
    $originalHash=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
    & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -ExpectedSetupSha256 $originalHash
    Assert ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash) 'The extractor must be replaced by the extracted ODT'
    $backup=Join-Path $case ('assets\office\odt-source\OfficeDeploymentTool-'+$originalHash+'.exe')
    Assert ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -eq $originalHash) 'Original ODT package must be preserved with the same SHA256'
    Assert (Test-Path (Join-Path $case 'assets\office\Office\Data\payload.cab')) 'The actual download must run after extraction'
    Assert (-not @(Get-ChildItem (Join-Path $case 'assets\office') -Directory -Filter .odt-extract-* -Force).Count) 'Extraction directory must be cleaned'
    & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -VerifyOnly

    foreach($mode in @('ExtractionFailure','ExtractedSignature','VerifyOnly')){
        $case=New-Case "office-extractor-$mode"
        New-Office $case
        $setup=Join-Path $case 'assets\office\setup.exe'
        [IO.File]::WriteAllText($setup,'SYS.ARGS.EXTRACTPATH The Microsoft Office 2016 Click-to-Run Administrator Tool',[Text.Encoding]::Unicode)
        $originalHash=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
        switch($mode){
            'ExtractionFailure' { $global:TypeBShaTestState.ExtractionFailure=$true; $pattern='package extraction failed' }
            'ExtractedSignature' { $global:TypeBShaTestState.ExtractedSignature='NotSigned'; $pattern='Extracted ODT setup.exe must have a valid Microsoft signature' }
            'VerifyOnly' { $pattern='self-extracting package' }
        }
        if($mode -eq 'VerifyOnly'){ Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') -VerifyOnly } $pattern }
        else{ Assert-Throws { & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1') } $pattern }
        Assert ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() -eq $originalHash) 'Failed extraction or signature check must preserve the original setup.exe'
        Assert (-not @(Get-ChildItem (Join-Path $case 'assets\office') -Directory -Filter .odt-extract-* -Force).Count) 'Failed extraction must clean its generated directory'
        Assert (-not (Test-Path (Join-Path $case 'assets\office\SHA256SUMS'))) 'Failed extraction must not lock incomplete Office media'
    }

    $case=New-Case 'office-readiness-partial'
    New-Office $case
    Copy-Item -LiteralPath (Join-Path $Repository 'scripts\Test-BuildAssets.ps1') -Destination (Join-Path $case 'scripts\Test-BuildAssets.ps1')
    New-Item -ItemType Directory -Path (Join-Path $case 'assets\windows'),(Join-Path $case 'assets\vsix'),(Join-Path $case 'assets\office\Office\Data') -Force | Out-Null
    '[]' | Set-Content -LiteralPath (Join-Path $case 'config\apps.json')
    '{"required":[]}' | Set-Content -LiteralPath (Join-Path $case 'config\vsix.json')
    'incomplete download' | Set-Content -LiteralPath (Join-Path $case 'assets\office\Office\Data\partial.dat')
    $issues=@(& (Join-Path $case 'scripts\Test-BuildAssets.ps1') -ReportOnly)
    Assert (@($issues | Where-Object { $_.component -eq 'office' -and $_.detail -match 'SHA256SUMS is missing' }).Count -eq 1) 'A partial Office/Data tree must not count as completed offline media'
    & (Join-Path $case 'scripts\Prepare-OfficeOffline.ps1')
    'tampered download' | Set-Content -LiteralPath (Join-Path $case 'assets\office\Office\Data\partial.dat')
    $issues=@(& (Join-Path $case 'scripts\Test-BuildAssets.ps1') -ReportOnly)
    Assert (@($issues | Where-Object { $_.component -eq 'office' -and $_.detail -match 'integrity verification failed' }).Count -eq 1) 'Office readiness must reject modified media even when a manifest exists'

    $case=New-Case 'build-good'
    $source=New-Source $case
    & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1')
    $output=Join-Path $case 'assets\linux\TypeB-Ubuntu-22.04-WSL-Docker.tar'
    Assert ((Get-Content "$output.sha256").StartsWith((Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant())) 'Export sidecar must match TAR'
    $baseline=Get-Content -LiteralPath "$output.baseline.json" -Raw | ConvertFrom-Json
    Assert ($baseline.imageSha256 -eq (Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant()) 'Export baseline report must be bound to the TAR SHA256'
    Assert ($global:TypeBShaTestState.Calls -contains '--unregister TypeB-Ubuntu-Builder') 'Owned temporary distribution must be unregistered'
    Assert (-not @(Get-ChildItem (Join-Path $case 'assets\linux') -Directory -Filter .wsl-build-* -Force).Count) 'Temporary build directory must be removed'
    $count=$global:TypeBShaTestState.Calls.Count
    Assert-Throws { & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1') } 'already exists'
    Assert ($global:TypeBShaTestState.Calls.Count -eq $count) 'Existing output must fail before WSL changes'
    & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1') -Force
    Assert ((Get-Content "$output.sha256").StartsWith((Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant())) 'Forced export must update its checksum'

    $case=New-Case 'build-tamper'
    $source=New-Source $case
    'tampered' | Set-Content $source
    Assert-Throws { & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1') } 'source SHA256 mismatch'
    Assert ($global:TypeBShaTestState.Calls.Count -eq 0) 'Unverified source must never reach WSL'

    $case=New-Case 'build-collision'
    $source=New-Source $case
    $global:TypeBShaTestState.Existing='TypeB-Ubuntu-Builder'
    Assert-Throws { & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1') } 'distribution already exists'
    Assert ($global:TypeBShaTestState.Calls.Count -eq 1) 'Existing distribution must never be imported or unregistered'

    foreach ($mode in @('BashFailure','ExportFailure')) {
        $case=New-Case "build-$mode"
        $source=New-Source $case
        $global:TypeBShaTestState[$mode]=$true
        $pattern=if($mode -eq 'BashFailure'){'Linux/Docker preparation failed'}else{'WSL export failed'}
        Assert-Throws { & (Join-Path $case 'scripts\Build-DockerReady-UbuntuWSL.ps1') } $pattern
        Assert ($global:TypeBShaTestState.Calls -contains '--unregister TypeB-Ubuntu-Builder') 'Failed build must unregister only its owned distribution'
        Assert (-not (Test-Path (Join-Path $case 'assets\linux\TypeB-Ubuntu-22.04-WSL-Docker.tar.sha256'))) 'Failed build must not produce a checksum'
    }
    $case=New-Case 'target-helper'
    $ubuntu=Join-Path $case 'assets\linux'
    $helper=Join-Path $ubuntu 'Install-TypeB-Ubuntu-WSL.ps1'
    Copy-Item -LiteralPath (Join-Path $Repository 'overlay\sources\$OEM$\$1\TypeB-Assets\Ubuntu\Install-TypeB-Ubuntu-WSL.ps1') -Destination $helper
    $tar=Join-Path $ubuntu 'TypeB-Ubuntu-22.04-WSL-Docker.tar'
    'prepared fixture' | Set-Content -LiteralPath $tar -Encoding ascii
    $hash=(Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash
    $location=Join-Path $case 'imported'
    & $helper -ExpectedSha256 $hash -InstallLocation $location
    Assert (Test-Path (Join-Path $location 'typeb-image.json')) 'Local user import must record ownership'
    Assert ($global:TypeBShaTestState.Calls.Count -eq 2) 'Local user import must only list and import'
    $count=$global:TypeBShaTestState.Calls.Count
    'corrupted' | Set-Content -LiteralPath $tar
    Assert-Throws { & $helper -ExpectedSha256 $hash -InstallLocation $location } 'SHA256 mismatch'
    Assert ($global:TypeBShaTestState.Calls.Count -eq $count) 'Corrupt target TAR must not reach WSL'
    $global:TypeBShaTestState.Existing='TypeB-Ubuntu-22.04'
    $hash=(Get-FileHash -LiteralPath $tar -Algorithm SHA256).Hash
    Assert-Throws { & $helper -ExpectedSha256 $hash -InstallLocation (Join-Path $case 'unowned') } 'not owned by Type B'

    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'overlay\sources\$OEM$\$1\TypeB-Offline\Scripts\Initialize-TypeBUser.ps1'),[ref]$tokens,[ref]$errors)
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Wsl'},$true)
    . ([scriptblock]::Create($function.Extent.Text))
    Invoke-Wsl -Arguments @('-d','test-distro','-u','root','--exec','wslpath','-a','-u','C:\TypeB space & marker\prepare.sh') | Out-Null
    Assert ($global:TypeBShaTestState.Calls[$global:TypeBShaTestState.Calls.Count-1] -match 'test-distro -u root --exec wslpath -a -u C:\\TypeB space & marker\\prepare.sh') 'User WSL wrapper must forward every argument'

    $case=New-Case 'source-iso-tamper'
    Copy-Item -LiteralPath (Join-Path $Repository 'config\build.json') -Destination (Join-Path $case 'config\build.json')
    $builderText=(Get-Content -LiteralPath (Join-Path $Repository 'Build-TypeB-ISO.ps1') -Raw) -replace '(?m)^#requires -RunAsAdministrator\r?\n',''
    $builderText | Set-Content -LiteralPath (Join-Path $case 'Build-TypeB-ISO.ps1') -Encoding utf8
    $iso=Join-Path $case 'source.iso'
    'untrusted iso' | Set-Content -LiteralPath $iso
    Assert-Throws { & (Join-Path $case 'Build-TypeB-ISO.ps1') -SourceIso $iso } 'Windows source ISO SHA256 mismatch'
    Assert (-not (Test-Path (Join-Path $case 'work'))) 'Invalid Windows source ISO must fail before media staging'

    $case=New-Case 'vm-staging'
    Copy-Item -LiteralPath (Join-Path $Repository 'scripts\Prepare-UbuntuVM.ps1') -Destination (Join-Path $case 'scripts\Prepare-UbuntuVM.ps1')
    $vm=Join-Path $case 'original-vm'
    New-Item -ItemType Directory -Path $vm | Out-Null
    'guestOS = "ubuntu-64"','scsi0:0.fileName = "disk.vmdk"','scsi0:0.startConnected = "TRUE"','sata0:1.deviceType = "cdrom-image"','sata0:1.fileName = "D:\old.iso"','sata0:1.startConnected = "TRUE"','ethernet0.startConnected = "TRUE"' | Set-Content -LiteralPath (Join-Path $vm 'original.vmx') -Encoding ascii
    'disk fixture' | Set-Content -LiteralPath (Join-Path $vm 'disk.vmdk') -Encoding ascii
    $checks=@{}
    foreach($name in @('git','git-lfs','ssh','curl','wget','tmux','ffmpeg','ffprobe','gcc','g++','make','cmake','uv','conda','python3.13','docker','compose')){ $checks[$name]=$true }
    [pscustomobject]@{ubuntuVersion='22.04';mode='vm';python='Python 3.13.5';checks=$checks} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $vm 'baseline.json')
    & (Join-Path $case 'scripts\Prepare-UbuntuVM.ps1') -SourceVmDirectory $vm
    $staged=Get-Content -LiteralPath (Join-Path $case 'assets\linux\Ubuntu-22.04-VM\TypeB-Ubuntu-22.04.vmx') -Raw
    Assert ($staged -match 'scsi0:0.startConnected = "TRUE"') 'Prepared VM disk must remain connected'
    Assert ($staged -match 'sata0:1.startConnected = "FALSE"' -and $staged -match 'ethernet0.startConnected = "FALSE"') 'Prepared VM must disconnect installer media and network'
    Assert ((Get-Content -LiteralPath (Join-Path $vm 'original.vmx') -Raw) -match 'sata0:1.startConnected = "TRUE"') 'Original VM must not be modified'

    # An unsigned installer with a publisher pin must not be accepted merely
    # because its locally calculated bytes could be written into a fresh lock.
    $case=New-Case 'lock-publisher-pin'
    Copy-Item -LiteralPath (Join-Path $Repository 'scripts\Lock-Assets.ps1') -Destination (Join-Path $case 'scripts\Lock-Assets.ps1')
    "Write-Host 'Fixture asset readiness check.'" | Set-Content -LiteralPath (Join-Path $case 'scripts\Test-BuildAssets.ps1')
    New-Item -ItemType Directory -Path (Join-Path $case 'assets\windows'),(Join-Path $case 'assets\vsix') -Force | Out-Null
    $installer=Join-Path $case 'assets\windows\7z-x64.exe'
    'publisher-verified fixture' | Set-Content -LiteralPath $installer -Encoding ascii
    $pin=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    @([pscustomobject]@{file='windows/7z-x64.exe';requireSignature=$false;expectedSha256=$pin}) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $case 'config\apps.json')
    '{"required":[]}' | Set-Content -LiteralPath (Join-Path $case 'config\vsix.json')
    New-Source $case | Out-Null
    foreach($name in @('ubuntu-22.04.5-desktop-amd64.iso','TypeB-Ubuntu-22.04-WSL-Docker.tar','TypeB-Ubuntu-22.04-WSL-Docker.tar.sha256','TypeB-Ubuntu-22.04-WSL-Docker.tar.baseline.json')){
      'fixture' | Set-Content -LiteralPath (Join-Path $case ('assets\linux\'+$name)) -Encoding ascii
    }
    $global:TypeBShaTestState.Signature='NotSigned'
    & (Join-Path $case 'scripts\Lock-Assets.ps1')
    $lockPath=Join-Path $case 'config\assets.lock.json'
    $entry=(Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json).files | Where-Object relativePath -eq 'windows/7z-x64.exe'
    Assert ($entry.sha256 -eq $pin) 'Unsigned publisher-pinned bytes must be locked successfully'
    $lockHash=(Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash
    'tampered unsigned installer' | Set-Content -LiteralPath $installer -Encoding ascii
    Assert-Throws { & (Join-Path $case 'scripts\Lock-Assets.ps1') } 'Publisher SHA256 mismatch'
    Assert ((Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash -eq $lockHash) 'Rejected installer must leave the last successful lock intact'
    'publisher-verified fixture' | Set-Content -LiteralPath $installer -Encoding ascii
    @([pscustomobject]@{file='windows/7z-x64.exe';requireSignature=$true;expectedSha256=$pin}) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $case 'config\apps.json')
    Assert-Throws { & (Join-Path $case 'scripts\Lock-Assets.ps1') } 'Required Authenticode signature is not valid'

    Write-Host "PASS: $global:TypeBShaTestChecks SHA256 workflow assertions (downloads, ODT and WSL mocked)." -ForegroundColor Green
}
finally {
    $resolved=[IO.Path]::GetFullPath($Sandbox)
    $testsRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
    if ($resolved.StartsWith($testsRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^\.sha256-tests-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}



