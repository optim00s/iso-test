#requires -version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$LinuxDir = Join-Path $Root 'assets\linux'
New-Item -ItemType Directory -Force -Path $LinuxDir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Desktop releases and WSL root filesystems have separate Canonical manifests.
$Assets = @(
    @{ BaseUrl = 'https://releases.ubuntu.com/22.04.5';
       Name = 'ubuntu-22.04.5-desktop-amd64.iso'; Manifest = 'desktop-SHA256SUMS' },
    @{ BaseUrl = 'https://cloud-images.ubuntu.com/wsl/jammy/current';
       Name = 'ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz'; Manifest = 'wsl-SHA256SUMS' }
)

foreach ($Asset in $Assets) {
    $Name = $Asset.Name
    $Manifest = Join-Path $LinuxDir $Asset.Manifest
    $ManifestTemp = "$Manifest.partial"
    $Destination = Join-Path $LinuxDir $Name
    $Partial = "$Destination.partial"
    try {
        Write-Host "Fetching Canonical SHA256SUMS for $Name..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "$($Asset.BaseUrl)/SHA256SUMS" -OutFile $ManifestTemp -UseBasicParsing
        $Pattern = '^\s*([0-9A-Fa-f]{64})\s+\*?' + [regex]::Escape($Name) + '\s*$'
        $Entries = @(Get-Content -LiteralPath $ManifestTemp | Where-Object { $_ -match $Pattern })
        if ($Entries.Count -ne 1) { throw "Expected exactly one Canonical SHA256 entry for $Name." }
        $null = $Entries[0] -match $Pattern
        $ExpectedHash = $Matches[1].ToLowerInvariant()

        $Candidate = $Destination
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            Write-Host "Downloading $Name..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri "$($Asset.BaseUrl)/$Name" -OutFile $Partial -UseBasicParsing
            $Candidate = $Partial
        }
        $ActualHash = (Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualHash -ne $ExpectedHash) {
            throw "SHA256 mismatch for $Name. Expected: $ExpectedHash; actual: $ActualHash"
        }
        if ($Candidate -eq $Partial) { Move-Item -LiteralPath $Partial -Destination $Destination }
        Move-Item -LiteralPath $ManifestTemp -Destination $Manifest -Force
        "$ActualHash  $Name" | Set-Content -LiteralPath "$Destination.sha256" -Encoding ascii
        Write-Host "PASS: $Name`nSHA256: $ActualHash" -ForegroundColor Green
    }
    finally {
        foreach ($Temp in @($ManifestTemp, $Partial)) {
            if (Test-Path -LiteralPath $Temp -PathType Leaf) { Remove-Item -LiteralPath $Temp -Force }
        }
    }
}
Write-Host 'Ubuntu assets downloaded and SHA256-verified.' -ForegroundColor Green
