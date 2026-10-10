#requires -version 5.1
function Get-TypeBFreeBytes([string]$Path) {
    return [IO.DriveInfo]::new([IO.Path]::GetPathRoot($Path)).AvailableFreeSpace
}
function Get-TypeBBootId {
    return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Test-TypeBComplete([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return $false}
    try{$value=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        return ($value.schemaVersion -eq 3 -and $value.status -eq 'PASSED')
    }catch{return $false}
}
function Write-TypeBJson([string]$Path,$Value) {
    $parent=Split-Path $Path -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $tmp=Join-Path $parent ([IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        [IO.File]::WriteAllText($tmp,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $Path){ [IO.File]::Replace($tmp,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($tmp,$Path) }
    } finally { if(Test-Path -LiteralPath $tmp){ Remove-Item -LiteralPath $tmp -Force } }
}
function Write-TypeBStage([string]$Stage,[string]$Message,[string]$Status='RUNNING') {
    $state=Join-Path $env:LOCALAPPDATA 'TypeB'
    $stamp=(Get-Date).ToString('o')
    Write-Host "[$stamp] $Stage : $Message"
    Write-TypeBJson (Join-Path $state 'user-progress.json') ([ordered]@{
        schemaVersion=1;stage=$Stage;status=$Status;message=$Message;timestamp=$stamp;pid=$PID
    })
    $desktop=[Environment]::GetFolderPath('Desktop')
    if($desktop -and (Test-Path -LiteralPath $desktop)){
        $text=@("TYPE B USER SETUP: $Status","Stage: $Stage",$Message,"Updated: $stamp") -join [Environment]::NewLine
        [IO.File]::WriteAllText((Join-Path $desktop 'TypeB-User-STATUS.txt'),$text,[Text.UTF8Encoding]::new($false))
    }
}
function Get-TypeBHash([string]$Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $sha=[Security.Cryptography.SHA256]::Create()
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try {
        $buffer=New-Object byte[] (4MB)
        [long]$done=0
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
            $null=$sha.TransformBlock($buffer,0,$count,$buffer,0)
            $done+=$count
            if($clock.Elapsed.TotalSeconds -ge 10){
                $percent=if($stream.Length){[int](100.0*$done/$stream.Length)}else{100}
                Write-TypeBStage 'SHA256' ("{0}: {1}% ({2:N2}/{3:N2} GiB)" -f [IO.Path]::GetFileName($Path),$percent,($done/1GB),($stream.Length/1GB))
                $clock.Restart()
            }
        }
        $null=$sha.TransformFinalBlock([byte[]]@(),0,0)
        return [BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant()
    } finally { $clock.Stop();$stream.Dispose();$sha.Dispose() }
}
function Test-TypeBAttemptOwner($Owner,[string]$Name,[string]$Hash,[string]$Location,[string]$Sid) {
    if(-not $Owner){return $false}
    return ($Owner.schemaVersion -eq 1 -and $Owner.createdEmpty -eq $true -and
        $Owner.distroName -ceq $Name -and $Owner.sha256 -eq $Hash -and
        $Owner.installLocation -eq $Location -and $Owner.userSid -eq $Sid -and
        [int]$Owner.attemptCount -ge 1 -and [int]$Owner.attemptCount -le 2)
}
function Invoke-TypeBWsl([string[]]$Arguments) {
    $previousPreference=$ErrorActionPreference
    # A recovery CD can be the caller's working directory. WSL cannot always
    # translate that drive; use the existing Windows profile for native launches.
    Push-Location -LiteralPath $env:USERPROFILE
    try{$ErrorActionPreference='Continue';$output=@(& wsl.exe @Arguments 2>&1);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference;Pop-Location}
    foreach($line in $output){Write-Host ([string]$line)}
    if($code -ne 0){
        $message="WSL failed (exit $code): $($Arguments -join ' ')"+[Environment]::NewLine+($output -join [Environment]::NewLine)
        $exception=[InvalidOperationException]::new($message)
        if($message -match 'HCS_E_HYPERV_NOT_INSTALLED|0x80370102|0x80370114|WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED'){
            $exception.Data['TypeBExitCode']=20
        }
        throw $exception
    }
}

function Invoke-TypeBCode([string]$CodePath,[string[]]$Arguments) {
    $previousPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$output=@(& $CodePath @Arguments 2>&1);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    if($code -ne 0){throw ("VS Code CLI failed (exit $code): "+($output -join [Environment]::NewLine))}
    return @($output | ForEach-Object {[string]$_})
}

function Install-TypeBExtensions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$CodePath,
        [Parameter(Mandatory)][string]$ExtensionsDirectory,
        [string]$UserDataDirectory
    )
    if(-not (Test-Path -LiteralPath $CodePath -PathType Leaf)){throw 'VS Code CLI is missing.'}
    $manifest=Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if(-not @($manifest.required).Count){throw 'Required VSIX manifest is empty.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $packages=@()
    # Validate every local archive before modifying the profile. Native VS Code
    # also checks engine compatibility; do not bypass it or edit package.json.
    foreach($name in $manifest.required){
        if($name -notmatch '^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9.-]*\.vsix$'){throw "Unsafe VSIX filename: $name"}
        $path=Join-Path $PackageRoot $name
        $zip=[IO.Compression.ZipFile]::OpenRead($path)
        try{
            $entry=$zip.GetEntry('extension/package.json')
            if(-not $entry){throw "VSIX package manifest is missing: $name"}
            $reader=[IO.StreamReader]::new($entry.Open())
            try{$package=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}
        }finally{$zip.Dispose()}
        $id=([string]$package.publisher+'.'+[string]$package.name).ToLowerInvariant()
        if($id -ne ($name -replace '\.vsix$','').ToLowerInvariant() -or -not $package.version){throw "VSIX identity mismatch: $name"}
        if(@($packages | Where-Object id -eq $id).Count){throw "Duplicate VSIX identity: $id"}
        $packages+= [pscustomobject]@{id=$id;version=[string]$package.version;path=$path;dependencies=@($package.extensionDependencies)}
    }
    foreach($package in $packages){
        foreach($dependency in $package.dependencies){
            if($dependency -and @($packages.id) -notcontains $dependency){throw "Offline VSIX dependency is missing: $dependency"}
        }
    }
    $cli=@('--extensions-dir',$ExtensionsDirectory)
    if($UserDataDirectory){$cli+=@('--user-data-dir',$UserDataDirectory)}
    New-Item -ItemType Directory -Path $ExtensionsDirectory -Force | Out-Null
    $listed=@(Invoke-TypeBCode -CodePath $CodePath -Arguments ($cli+@('--list-extensions','--show-versions')))
    # Install from actual VSIX files, rather than copying unpacked folders.
    # This lets VS Code repair its profile index and obsolete-registration state.
    $missing=@($packages | Where-Object {$listed -notcontains ($_.id+'@'+$_.version)})
    if($missing.Count){
        $install=$cli+@('--force','--do-not-include-pack-dependencies')
        foreach($package in $missing){$install+=@('--install-extension',$package.path)}
        Invoke-TypeBCode -CodePath $CodePath -Arguments $install | ForEach-Object {Write-Host $_}
    }
    $listed=@(Invoke-TypeBCode -CodePath $CodePath -Arguments ($cli+@('--list-extensions','--show-versions')))
    foreach($package in $packages){
        $expected=$package.id+'@'+$package.version
        if($listed -notcontains $expected){throw "VS Code extension is not registered at its packaged version: $expected"}
        Write-Host "VS Code extension PASS: $expected"
    }
}

