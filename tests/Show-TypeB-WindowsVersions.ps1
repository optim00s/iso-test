# Run inside the installed Type B Windows VM, as the signed-in user.
# No packages are installed or downloaded. -IncludeWsl also runs Linux versions.
param([switch]$IncludeWsl)

$ErrorActionPreference = 'Continue'
$failedCommands = [System.Collections.Generic.List[string]]::new()

function Show-VersionCommand {
    param([string]$Command, [string[]]$CommandArguments)
    Write-Host "`n> $Command $($CommandArguments -join ' ')" -ForegroundColor Cyan
    $native = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $native) {
        Write-Warning "$Command was not found on PATH."
        $failedCommands.Add($Command)
        return
    }
    try {
        & $native.Source @CommandArguments 2>&1 | ForEach-Object { Write-Host ([string]$_).Replace([string][char]0, '') }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Exit code: $LASTEXITCODE"
            $failedCommands.Add($Command)
        }
    } catch {
        Write-Warning $_.Exception.Message
        $failedCommands.Add($Command)
    }
}

Show-VersionCommand 'python.exe' @('--version')
Show-VersionCommand 'uv.exe' @('--version')
Show-VersionCommand 'conda' @('--version')
Show-VersionCommand 'git.exe' @('--version')
Show-VersionCommand 'git.exe' @('lfs', 'version')
Show-VersionCommand 'ssh.exe' @('-V')
Show-VersionCommand 'curl.exe' @('--version')
Show-VersionCommand 'wget.exe' @('--no-config', '--version')
Show-VersionCommand 'cmake.exe' @('--version')
Show-VersionCommand 'ffmpeg.exe' @('-hide_banner', '-version')
Show-VersionCommand 'ffprobe.exe' @('-hide_banner', '-version')
Show-VersionCommand 'code.cmd' @('--version')
Show-VersionCommand 'code.cmd' @('--list-extensions', '--show-versions')
Show-VersionCommand 'wsl.exe' @('--version')
Show-VersionCommand 'wsl.exe' @('-l', '-v')

if ($IncludeWsl) {
    $linuxScript = Join-Path $PSScriptRoot 'Show-TypeB-LinuxVersions.sh'
    $distro = 'TypeB-Ubuntu-22.04'
    Write-Host "`n> Linux versions inside $distro" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $linuxScript)) {
        Write-Warning 'Keep Show-TypeB-LinuxVersions.sh beside this PowerShell script.'
        $failedCommands.Add('WSL Linux script')
    } else {
        $linuxPath = & wsl.exe -d $distro --exec wslpath -a -u ($linuxScript.Replace('\', '/'))
        if ($LASTEXITCODE -ne 0 -or -not $linuxPath) {
            Write-Warning 'Could not translate the Linux script path inside WSL.'
            $failedCommands.Add('WSL path')
        } else {
            & wsl.exe -d $distro --exec bash ([string]$linuxPath).Trim()
            if ($LASTEXITCODE -ne 0) { $failedCommands.Add('WSL Linux versions') }
        }
    }
}

if ($failedCommands.Count) {
    Write-Warning ('Commands needing attention: ' + ($failedCommands -join ', '))
    exit 1
}
