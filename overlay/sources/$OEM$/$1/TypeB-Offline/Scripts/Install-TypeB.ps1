#requires -version 5.1
[CmdletBinding()]
param([ValidateSet('Specialize','SetupComplete')][string]$Phase='Specialize')

$ErrorActionPreference='Stop'
$Root='C:\TypeB-Offline'
$PackageRoot=Join-Path $Root 'Packages'
$ConfigRoot=Join-Path $Root 'Config'
$ProgramDataRoot='C:\ProgramData\TypeB'
$LogRoot=Join-Path $ProgramDataRoot 'Logs'
$StateRoot=Join-Path $ProgramDataRoot 'State'
$AssetsRoot='C:\TypeB-Assets'
$CompleteMarker=Join-Path $StateRoot 'offline-install.complete'
$FailureMarker=Join-Path $StateRoot 'offline-install.failed.json'
$Transcript=Join-Path $LogRoot ('install-'+$Phase+'.log')

New-Item -ItemType Directory -Force -Path $LogRoot,$StateRoot,$AssetsRoot | Out-Null
if (Test-Path -LiteralPath $CompleteMarker) { exit 0 }

Start-Transcript -LiteralPath $Transcript -Append | Out-Null

function Write-Status([string]$Text) {
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Text)
}

function Test-ExitCode([int]$Code,[string]$Name) {
    if ($Code -notin @(0,3010)) { throw "$Name failed with exit code $Code" }
}

function Start-LocalExe([string]$Path,[string]$Arguments,[string]$Name) {
    Write-Status "Installing $Name"
    $p=Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    Test-ExitCode $p.ExitCode $Name
}

function Start-LocalMsi([string]$Path,[string]$Arguments,[string]$Name) {
    $args='/i "'+$Path+'" /qn /norestart '+$Arguments
    Start-LocalExe "$env:SystemRoot\System32\msiexec.exe" $args $Name
}

function Add-SystemPath([string]$PathToAdd) {
    if (-not $PathToAdd) { return }
    $current=[Environment]::GetEnvironmentVariable('Path','Machine')
    $parts=@($current -split ';' | Where-Object { $_ })
    if ($parts -notcontains $PathToAdd) {
        [Environment]::SetEnvironmentVariable('Path',(($parts+$PathToAdd) -join ';'),'Machine')
    }
}

function Get-ProvisionedAppNames {
    @(Get-AppxProvisionedPackage -Online | ForEach-Object DisplayName)
}

function Test-Detection($Detect) {
    if (-not $Detect) { return $false }
    switch ([string]$Detect.type) {
      'file' { return (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$Detect.value))) }
      'fileAll' { return (@($Detect.value | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0) }
      'command' {
        try {
          $parts=[string]$Detect.value -split ' ',2
          $cmd=Get-Command $parts[0] -ErrorAction Stop
          $args=if($parts.Count -gt 1){$parts[1]}else{''}
          $p=Start-Process -FilePath $cmd.Source -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
          return ($p.ExitCode -eq 0)
        } catch { return $false }
      }
      'registryDisplayName' {
        $needle=[string]$Detect.value
        foreach($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
          if (Get-ItemProperty $base -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$needle*" }) { return $true }
        }
        return $false
      }
      'provisionedAppx' { return ((Get-ProvisionedAppNames) -contains [string]$Detect.value) }
      default { return $false }
    }
}

function Expand-ZipSingleRoot([string]$Archive,[string]$Destination) {
    $temp=Join-Path $env:TEMP ('typeb-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    try {
      Expand-Archive -LiteralPath $Archive -DestinationPath $temp -Force
      $children=@(Get-ChildItem -LiteralPath $temp -Force)
      $source=$temp
      if ($children.Count -eq 1 -and $children[0].PSIsContainer) { $source=$children[0].FullName }
      $resolvedDestination=[IO.Path]::GetFullPath($Destination)
      if(-not $resolvedDestination.StartsWith('C:\Program Files\',[StringComparison]::OrdinalIgnoreCase)){ throw 'Unsafe ZIP destination.' }
      if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
      New-Item -ItemType Directory -Force -Path $Destination | Out-Null
      Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force
    } finally {
      $resolvedTemp=[IO.Path]::GetFullPath($temp)
      if($resolvedTemp.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedTemp) -match '^typeb-[0-9a-f]{32}$'){ Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Seed-VSCodeExtensions {
    $manifest=Get-Content -LiteralPath (Join-Path $ConfigRoot 'vsix.json') -Raw | ConvertFrom-Json
    $target='C:\Users\Default\.vscode\extensions'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach($name in @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'vsix') -Filter *.vsix -File | ForEach-Object Name)) {
      $vsix=Join-Path $PackageRoot ('vsix\'+$name)
      if (-not (Test-Path -LiteralPath $vsix)) { throw "Required VSIX missing: $name" }
      $tmp=Join-Path $env:TEMP ('vsix-'+[guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Force -Path $tmp | Out-Null
      try {
        $zip=Join-Path $tmp 'package.zip'
        Copy-Item -LiteralPath $vsix -Destination $zip
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $pkgJson=Join-Path $tmp 'x\extension\package.json'
        if (-not (Test-Path -LiteralPath $pkgJson)) { throw "Invalid VSIX: $name" }
        $pkg=Get-Content -LiteralPath $pkgJson -Raw | ConvertFrom-Json
        $folder=("{0}.{1}-{2}" -f $pkg.publisher,$pkg.name,$pkg.version).ToLowerInvariant()
        if($folder -notmatch '^[a-z0-9-]+\.[a-z0-9-]+-[a-z0-9.+-]+$'){ throw 'Unsafe VSIX identity.' }
        $dest=Join-Path $target $folder
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $tmp 'x\extension') -Destination $dest -Recurse -Force
      } finally {
        $resolvedTmp=[IO.Path]::GetFullPath($tmp)
        if($resolvedTmp.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedTmp) -match '^vsix-[0-9a-f]{32}$'){ Remove-Item -LiteralPath $resolvedTmp -Recurse -Force -ErrorAction SilentlyContinue }
      }
    }
}

function Register-TypeBFirstLogon {
    $key='HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{6D2ED8DC-4B13-4A87-A900-4995F12B0400}'
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Version' -Value '4,0,0,0' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'IsInstalled' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name 'StubPath' -Value 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\TypeB-Offline\Scripts\Initialize-TypeBUser.ps1' -PropertyType String -Force | Out-Null
    $settings='C:\Users\Default\AppData\Roaming\Code\User'
    New-Item -ItemType Directory -Path $settings -Force | Out-Null
    [pscustomobject]@{'extensions.autoUpdate'=$false;'extensions.autoCheckUpdates'=$false;'update.mode'='none';'python.defaultInterpreterPath'='C:\Program Files\Python313\python.exe'} |
      ConvertTo-Json | Set-Content -LiteralPath (Join-Path $settings 'settings.json') -Encoding utf8
}

function Verify-LockedAssets {
    $lock=Get-Content -LiteralPath (Join-Path $ConfigRoot 'assets.lock.json') -Raw | ConvertFrom-Json
    foreach($entry in @($lock.files)) {
      $path=Join-Path $PackageRoot ([string]$entry.relativePath)
      if (-not (Test-Path -LiteralPath $path)) { throw "Locked asset missing: $($entry.relativePath)" }
      $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($hash -ne [string]$entry.sha256) { throw "SHA256 mismatch: $($entry.relativePath)" }
    }
}


function Install-OfflineUpdates {
    $updateDir=Join-Path $PackageRoot 'updates'
    if (-not (Test-Path -LiteralPath $updateDir)) { return }
    foreach($pkg in Get-ChildItem -LiteralPath $updateDir -File | Where-Object Extension -in @('.msu','.cab')) {
      Write-Status "Applying offline Windows package $($pkg.Name)"
      $p=Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList ('/Online /Add-Package /PackagePath:"'+$pkg.FullName+'" /Quiet /NoRestart') -Wait -PassThru -WindowStyle Hidden
      Test-ExitCode $p.ExitCode $pkg.Name
    }
}

function Enable-WindowsBaseline {
    Write-Status 'Enabling WSL / VirtualMachinePlatform features'
    foreach($feature in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')) {
      $f=Get-WindowsOptionalFeature -Online -FeatureName $feature
      if ($f.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -LimitAccess | Out-Null
      }
    }
    $ssh=Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*' | Select-Object -First 1
    if ($ssh -and $ssh.State -ne 'Installed') {
      $source=Join-Path $PackageRoot 'windows\OpenSSH-FoD'
      if(-not (Test-Path -LiteralPath $source)){ throw 'OpenSSH Client is not installed in the source Windows image. Include the matching offline Features on Demand CABs in assets/windows/OpenSSH-FoD.' }
      Add-WindowsCapability -Online -Name $ssh.Name -Source $source -LimitAccess | Out-Null
    }
    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) { throw 'Windows OpenSSH client is missing.' }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'Windows curl.exe is missing.' }
}

$results=New-Object Collections.Generic.List[object]
try {
  Verify-LockedAssets
  Install-OfflineUpdates
  Enable-WindowsBaseline

  $apps=Get-Content -LiteralPath (Join-Path $ConfigRoot 'apps.json') -Raw | ConvertFrom-Json
  foreach($app in @($apps)) {
    $status='PASS'; $detail=''
    try {
      if (Test-Detection $app.detect) {
        $detail='Already present.'
      } else {
        $path=Join-Path $PackageRoot ([string]$app.file)
        if (-not (Test-Path -LiteralPath $path)) { throw "Package missing: $($app.file)" }
        switch ([string]$app.method) {
          'exe' { Start-LocalExe $path ([string]$app.args) $app.name }
          'bundled' { throw "Bundled component was not installed by its parent package: $($app.name)" }
          'msi' { Start-LocalMsi $path ([string]$app.args) $app.name }
          'copy' {
            $dest=[string]$app.destination
            New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
            Copy-Item -LiteralPath $path -Destination $dest -Force
          }
          'zipSingleRoot' { Expand-ZipSingleRoot $path ([string]$app.destination) }
          'teamsOffline' {
            $msix=Join-Path $PackageRoot ([string]$app.secondaryFile)
            Start-LocalExe $path ('-p -o "'+$msix+'"') $app.name
          }
          'provisionedAppx' {
            $deps=@()
            if ($app.dependencyFolder) {
              $depRoot=Join-Path $PackageRoot ([string]$app.dependencyFolder)
              if (Test-Path -LiteralPath $depRoot) { $deps=@(Get-ChildItem -LiteralPath $depRoot -File | Where-Object Extension -in @('.appx','.msix') | ForEach-Object FullName) }
            }
            if ($deps.Count) { Add-AppxProvisionedPackage -Online -PackagePath $path -DependencyPackagePath $deps -SkipLicense | Out-Null }
            else { Add-AppxProvisionedPackage -Online -PackagePath $path -SkipLicense | Out-Null }
          }
          'officeODT' {
            $cfg=Join-Path $PackageRoot ([string]$app.officeConfig)
            Start-LocalExe $path ('/configure "'+$cfg+'"') $app.name
          }
          default { throw "Unsupported install method: $($app.method)" }
        }
        foreach($p in @($app.systemPathAdd)) { Add-SystemPath ([string]$p) }
        if (-not (Test-Detection $app.detect)) { throw "Post-install detection failed: $($app.name)" }
        $detail='Installed from local ISO payload.'
      }
      foreach($pathToAdd in @($app.systemPathAdd)){ Add-SystemPath ([string]$pathToAdd) }
      if($app.id -eq 'git-lfs'){
        & 'C:\Program Files\Git\cmd\git.exe' lfs install --system
        if($LASTEXITCODE -ne 0){ throw 'Git LFS system configuration failed.' }
      }
    } catch {
      $status='FAIL'; $detail=$_.Exception.Message
      if (-not [bool]$app.required) { $status='WARN' }
    }
    $results.Add([pscustomobject]@{id=$app.id;name=$app.name;status=$status;detail=$detail})
  }

  Seed-VSCodeExtensions

  $requiredFailures=@($results | Where-Object status -eq 'FAIL')
  $resultObj=[pscustomobject]@{phase=$Phase;timestamp=(Get-Date).ToString('o');results=@($results)}
  $resultObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $StateRoot 'offline-install-results.json') -Encoding utf8

  if ($requiredFailures.Count) {
    $resultObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $FailureMarker -Encoding utf8
    $text="TYPE B OFFLINE INSTALL: FAILED`r`n`r`n" + (($requiredFailures | ForEach-Object { "$($_.name): $($_.detail)" }) -join "`r`n") + "`r`n`r`nSee $Transcript"
    Set-Content -LiteralPath 'C:\Users\Public\Desktop\TypeB-Setup-STATUS.txt' -Value $text -Encoding utf8
  } else {
    Register-TypeBFirstLogon
    Set-Content -LiteralPath $CompleteMarker -Value (Get-Date).ToString('o') -Encoding ascii
    Remove-Item -LiteralPath $FailureMarker -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath 'C:\Users\Public\Desktop\TypeB-Setup-STATUS.txt' -Value "TYPE B OFFLINE INSTALL: PASSED`r`nAll required machine-wide packages were validated. Local WSL import and prepared-VM copy run for the real user at first logon; check TypeB-User-STATUS.txt for their result." -Encoding utf8
    if ((Get-Content -LiteralPath (Join-Path $ConfigRoot 'build.json') -Raw | ConvertFrom-Json).cleanupWindowsPackagesAfterSuccess) {
      if([IO.Path]::GetFullPath($PackageRoot) -ne 'C:\TypeB-Offline\Packages'){ throw 'Unsafe package cleanup path.' }
      Remove-Item -LiteralPath $PackageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
} catch {
  $fatal=[pscustomobject]@{phase=$Phase;timestamp=(Get-Date).ToString('o');fatal=$_.Exception.Message}
  $fatal | ConvertTo-Json | Set-Content -LiteralPath $FailureMarker -Encoding utf8
  Set-Content -LiteralPath 'C:\Users\Public\Desktop\TypeB-Setup-STATUS.txt' -Value ("TYPE B OFFLINE INSTALL: FATAL`r`n"+$_.Exception.Message+"`r`nSee "+$Transcript) -Encoding utf8
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}

# Never reboot from SetupComplete/specialize. Windows Setup owns reboot sequencing.
exit 0
