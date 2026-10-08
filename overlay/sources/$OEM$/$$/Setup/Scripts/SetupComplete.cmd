@echo off
setlocal EnableExtensions
rem Fallback only. Install-TypeB.ps1 is idempotent and exits immediately if specialize already completed.
if exist "%SystemDrive%\TypeB-Offline\Scripts\Install-TypeB.ps1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SystemDrive%\TypeB-Offline\Scripts\Install-TypeB.ps1" -Phase SetupComplete
)
exit /b 0
