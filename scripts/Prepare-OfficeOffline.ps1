#requires -version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedSetupSha256,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Office = Join-Path $Root 'assets\office'
$Setup = Join-Path $Office 'setup.exe'
$Config = Join-Path $Office 'configuration.xml'
$Manifest = Join-Path $Office 'SHA256SUMS'
if (-not (Test-Path -LiteralPath $Setup -PathType Leaf)) { throw 'Place the Microsoft Office Deployment Tool setup.exe in assets\office first.' }
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { throw 'configuration.xml missing.' }

$SetupHash = (Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ExpectedSetupSha256 -and $SetupHash -ne $ExpectedSetupSha256) { throw "ODT setup.exe SHA256 mismatch. Expected: $ExpectedSetupSha256; actual: $SetupHash" }
$Signature = Get-AuthenticodeSignature -LiteralPath $Setup
if ($Signature.Status -ne 'Valid' -or -not $Signature.SignerCertificate -or
    $Signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
    throw "ODT setup.exe must have a valid Microsoft Authenticode signature. Status: $($Signature.Status)"
}
Write-Host "ODT setup.exe SHA256: $SetupHash"

function Test-OdtSelfExtractor([string]$Path) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $Text = [Text.Encoding]::Unicode.GetString($Bytes)
    return ($Text.Contains('SYS.ARGS.EXTRACTPATH') -and
        $Text.Contains('The Microsoft Office 2016 Click-to-Run Administrator Tool'))
}

if (Test-OdtSelfExtractor $Setup) {
    if ($VerifyOnly) { throw 'setup.exe is the ODT self-extracting package, not the extracted deployment tool. Run this script without -VerifyOnly first.' }
    Write-Host 'ODT self-extracting package detected. Extracting the real setup.exe...' -ForegroundColor Cyan
    $ExtractDirectory = Join-Path $Office ('.odt-extract-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $ExtractDirectory | Out-Null
    try {
        $ExtractProcess = Start-Process -FilePath $Setup -ArgumentList ('/quiet /extract:"' + $ExtractDirectory + '"') -WorkingDirectory $Office -WindowStyle Hidden -Wait -PassThru
        if ($ExtractProcess.ExitCode -ne 0) { throw "ODT package extraction failed: $($ExtractProcess.ExitCode)" }
        $ExtractedSetup = Join-Path $ExtractDirectory 'setup.exe'
        if (-not (Test-Path -LiteralPath $ExtractedSetup -PathType Leaf)) { throw 'ODT package did not produce setup.exe.' }
        if (Test-OdtSelfExtractor $ExtractedSetup) { throw 'Extracted setup.exe is still a self-extracting package.' }
        $ExtractedSignature = Get-AuthenticodeSignature -LiteralPath $ExtractedSetup
        if ($ExtractedSignature.Status -ne 'Valid' -or -not $ExtractedSignature.SignerCertificate -or
            $ExtractedSignature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
            throw 'Extracted ODT setup.exe must have a valid Microsoft signature.'
        }
        $SourceDirectory = Join-Path $Office 'odt-source'
        New-Item -ItemType Directory -Path $SourceDirectory -Force | Out-Null
        $SourceBackup = Join-Path $SourceDirectory ('OfficeDeploymentTool-' + $SetupHash + '.exe')
        if (-not (Test-Path -LiteralPath $SourceBackup)) { Copy-Item -LiteralPath $Setup -Destination $SourceBackup }
        if ((Get-FileHash -LiteralPath $SourceBackup -Algorithm SHA256).Hash -ne $SetupHash) { throw 'Original ODT package backup SHA256 mismatch.' }
        Copy-Item -LiteralPath $ExtractedSetup -Destination $Setup -Force
        $SetupHash = (Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host "Extracted ODT setup.exe SHA256: $SetupHash"
        Write-Host "Original signed package preserved: $SourceBackup"
    }
    finally {
        $CleanupPath = [IO.Path]::GetFullPath($ExtractDirectory)
        $CleanupRoot = [IO.Path]::GetFullPath($Office).TrimEnd('\') + '\'
        if ($CleanupPath.StartsWith($CleanupRoot, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($CleanupPath) -match '^\.odt-extract-[0-9a-f]{32}$') {
            if (Test-Path -LiteralPath $CleanupPath) { Remove-Item -LiteralPath $CleanupPath -Recurse -Force }
        }
    }
}

function Get-OfficeHashLines {
    foreach ($File in Get-ChildItem -LiteralPath $Office -File -Recurse | Sort-Object FullName) {
        if ($File.FullName -eq $Manifest) { continue }
        $Relative = $File.FullName.Substring($Office.Length + 1).Replace('\', '/')
        $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $Relative"
    }
}

if ($VerifyOnly) {
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw 'Office SHA256SUMS missing. Run this script without -VerifyOnly first.' }
    $Expected = @(Get-Content -LiteralPath $Manifest)
    $Actual = @(Get-OfficeHashLines)
    if (-not $Expected.Count -or @(Compare-Object -ReferenceObject $Expected -DifferenceObject $Actual).Count) {
        throw 'Office SHA256 verification failed: files were changed, added or removed.'
    }
    Write-Host 'Office SHA256 verification: PASS' -ForegroundColor Green
    return
}

# Use a temporary configuration to stage files locally while keeping the target SourcePath.
$DownloadConfig = Join-Path $Office ('.download-' + [guid]::NewGuid().ToString('N') + '.xml')
try {
    [xml]$Xml = Get-Content -LiteralPath $Config -Raw
    $AddNodes = @($Xml.SelectNodes('/Configuration/Add'))
    if (-not $AddNodes.Count) { throw 'configuration.xml must contain a Configuration/Add element.' }
    foreach ($Add in $AddNodes) { $Add.SetAttribute('SourcePath', $Office) }
    $Xml.Save($DownloadConfig)
    $Process = Start-Process -FilePath $Setup -ArgumentList ('/download "' + $DownloadConfig + '"') -WorkingDirectory $Office -WindowStyle Hidden -Wait -PassThru
    if ($Process.ExitCode -ne 0) { throw "ODT download failed with exit code $($Process.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $DownloadConfig -PathType Leaf) { Remove-Item -LiteralPath $DownloadConfig -Force }
}
$Data = Join-Path $Office 'Office\Data'
if (-not (Test-Path -LiteralPath $Data -PathType Container) -or
    -not @(Get-ChildItem -LiteralPath $Data -File -Recurse).Count) {
    throw "ODT completed but Office\Data is missing or empty. Expected: $Data. Check Office/Click-to-Run logs in $env:TEMP."
}

# Local integrity baseline; these are not vendor-published reference hashes.
Get-OfficeHashLines | Set-Content -LiteralPath $Manifest -Encoding utf8
Write-Host "Office offline media prepared. SHA256 manifest: $Manifest" -ForegroundColor Green
