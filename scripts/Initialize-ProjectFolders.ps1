#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($relative in @(
    'assets\windows\TerminalDependencies', 'assets\windows\OpenSSH-FoD',
    'assets\office', 'assets\vsix', 'assets\updates', 'assets\linux\baseline',
    'assets\linux\Ubuntu-22.04-VM', 'source', 'vm-source', 'work', 'output'
)) {
    New-Item -ItemType Directory -Path (Join-Path $root $relative) -Force | Out-Null
}
Write-Host 'Project folders ready. Binary assets are restored/acquired separately.'
