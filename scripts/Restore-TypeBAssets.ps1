#requires -version 5.1
# Restore the current locked binary assets from a final Type B ISO, not a stock Windows ISO.
[CmdletBinding(DefaultParameterSetName='Iso')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Iso')][string]$SourceIso,
    [Parameter(ParameterSetName='Iso')][ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedIsoSha256='3d2c371aecccde68f9beaf3029d76d01da45461155fd1ae1c7b7a126ad95db7d',
    [Parameter(Mandatory=$true,ParameterSetName='Media')][string]$MediaRoot,
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$assets = Join-Path $root 'assets'
$lock = Get-Content -LiteralPath (Join-Path $root 'config\assets.lock.json') -Raw | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or -not @($lock.files).Count) { throw 'Invalid or empty asset lock.' }
$ownedMount = $false
$isoPath = $null
try {
    if ($PSCmdlet.ParameterSetName -eq 'Iso') {
        $isoPath = (Resolve-Path -LiteralPath $SourceIso).ProviderPath
        Write-Host 'Verifying the final ISO SHA256...'
        if ((Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash -ne $ExpectedIsoSha256) {
            throw 'Final ISO SHA256 mismatch. Use the matching Type B ISO, not the original Windows ISO.'
        }
        $disk = Get-DiskImage -ImagePath $isoPath
        if (-not $disk.Attached) {
            $disk = Mount-DiskImage -ImagePath $isoPath -Access ReadOnly -PassThru
            $ownedMount = $true
        }
        $volume = $disk | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
        if (-not $volume) { throw 'The final ISO has no mounted drive letter.' }
        $MediaRoot = $volume.DriveLetter + ':\'
    }
    $media = (Resolve-Path -LiteralPath $MediaRoot).ProviderPath
    $packages = Join-Path $media 'sources\$OEM$\$1\TypeB-Offline\Packages'
    $ubuntu = Join-Path $media 'sources\$OEM$\$1\TypeB-Assets\Ubuntu'
    $seen = @{}
    $plan = foreach ($entry in @($lock.files)) {
        $relative = [string]$entry.relativePath
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|:' -or
            $entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [long]$entry.size -lt 0 -or $seen.ContainsKey($relative)) {
            throw "Invalid asset lock entry: $relative"
        }
        $seen[$relative] = $true
        $source = if ($relative.StartsWith('linux/')) { Join-Path $ubuntu $relative.Substring(6) } else { Join-Path $packages $relative }
        $destination = [IO.Path]::GetFullPath((Join-Path $assets $relative))
        if (-not $destination.StartsWith($assets + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe asset destination.' }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Item -LiteralPath $source).Length -ne [long]$entry.size) {
            throw "Missing or wrong-sized ISO asset: $relative"
        }
        $existing = Test-Path -LiteralPath $destination -PathType Leaf
        if (-not $VerifyOnly -and $existing) {
            if ((Get-Item -LiteralPath $destination).Length -ne [long]$entry.size -or
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $entry.sha256) {
                throw "Existing local asset differs; it was not overwritten: $relative"
            }
        }
        [pscustomobject]@{Relative=$relative;Source=$source;Destination=$destination;Hash=$entry.sha256;Size=[long]$entry.size;Existing=$existing}
    }
    if (-not $VerifyOnly) {
        $required = [long](($plan | Where-Object { -not $_.Existing } | Measure-Object Size -Sum).Sum) + 2GB
        $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
        if ($drive.AvailableFreeSpace -lt $required) { throw ('Insufficient free space. Need at least {0:N2} GiB.' -f ($required/1GB)) }
    }
    foreach ($item in $plan) {
        if ($VerifyOnly) {
            if ((Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash -ne $item.Hash) { throw "ISO asset SHA256 mismatch: $($item.Relative)" }
        } elseif (-not $item.Existing) {
            New-Item -ItemType Directory -Path (Split-Path $item.Destination -Parent) -Force | Out-Null
            $partial = $item.Destination + '.restore-' + [guid]::NewGuid().ToString('N') + '.partial'
            try {
                Copy-Item -LiteralPath $item.Source -Destination $partial
                if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $item.Hash) { throw "Restored asset SHA256 mismatch: $($item.Relative)" }
                Move-Item -LiteralPath $partial -Destination $item.Destination
            } finally {
                $safePartial = [IO.Path]::GetFullPath($partial)
                if ($safePartial.StartsWith($assets + '\',[StringComparison]::OrdinalIgnoreCase) -and
                    [IO.Path]::GetFileName($safePartial) -match '\.restore-[0-9a-f]{32}\.partial$' -and (Test-Path -LiteralPath $safePartial)) {
                    Remove-Item -LiteralPath $safePartial -Force
                }
            }
        }
        Write-Host "SHA256 OK: $($item.Relative)"
    }
    Write-Host ("Locked assets {0}: {1} files." -f $(if ($VerifyOnly) {'verified'} else {'restored/verified'}), $plan.Count)
} finally {
    if ($ownedMount) { Dismount-DiskImage -ImagePath $isoPath | Out-Null }
}
