[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run the builder from an elevated PowerShell session.'
}
$oscdimgCandidates=@(
  "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
  "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
)
$oscdimg=$oscdimgCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $oscdimg) { throw 'oscdimg.exe not found. Install Windows ADK Deployment Tools.' }
Write-Host "oscdimg: $oscdimg"
Write-Host 'Prerequisites: PASS'
