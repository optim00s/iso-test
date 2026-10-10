# Code validation — 2026-10-10

Result: PASS for source-level checks. Clean installation and hardware acceptance: PENDING.

Base: optim00s/iso-test commit c19f03f5d71df3b0b5b0d72969ccac135e898b18. Release: 4.1. This report records source checks performed before the media build.

| Check | Result and scope |
| --- | --- |
| Run-CodeChecks.ps1 | PASS: 30 PowerShell sources parse; offline runtime policy; no predefined Windows account, password, AutoLogon or product key in unattend. |
| Test-TypeBAutomation.ps1 | PASS: 18 checks covering ownership, interrupted import, restart boundaries, backup before reset, low disk space, corrupt TAR, completion markers, streaming hashes and WSL argument/current-directory preservation. Native WSL is mocked. |
| Test-MediaIntegration.ps1 | PASS: 2 checks; missing assets refuse before writes; all five canonical runtimes are staged with matching hashes. Tiny synthetic media only. |
| Test-VMwarePaths.ps1 | PASS: 15 checks for both Program Files locations, product detection and prepared VM shortcut. No VMware process or installer executed. |
| Test-BuildPreflight.ps1 | PASS: 5 checks for missing assets, stage plus output capacity, unsafe paths, output preservation and mandatory runtime integration before ISO creation. |
| Test-VSCodeProvisioning.ps1 | PASS: 3 mocked cases; missing archive, already registered packaged version, and successful CLI exit without registration. |
| Native VS Code regression | PASS: actual local Ruff VSIX, isolated extension and user-data directories, real code.cmd. An empty extension index and obsolete copied extension were repaired; exact packaged version appeared in CLI enumeration. Host CLI emitted a nonfatal EPERM directory warning; exit and registration checks passed. No production VS Code profile changed. |
| Test-SHA256Workflows.ps1 | PASS: 127 assertions. Downloads, ODT and WSL are mocked. |
| Test-OscdimgArguments.ps1 | PASS with real Oscdimg on Windows PowerShell 5.1 and PowerShell 7.6, including paths with spaces. Dummy boot images validate argument handling only. |
| git diff --check | Three trailing blank lines in canonical runtime files are preserved to keep their bytes identical to the built ISO. No other whitespace errors. |

Reproduce with tests/Run-CodeChecks.ps1 on Windows with Python and ADK Deployment Tools. Optional native VSIX regression requires a real local VSIX and VS Code on PATH. Test fixtures and raw logs are local generated files, excluded from the delivered source folder.

After these source checks, the locked assets were restored, Test-BuildAssets/Test-BuildSecurity passed, and the 4.1 ISO was built and read back successfully. See [media validation](MEDIA-VALIDATION.md) for actual build evidence and the remaining acceptance tests.

IT acceptance still requires a fresh Windows VM and a physical laptop installed from the new ISO without recovery CDs: all 19 machine components, all six extensions, WSL 2 Ubuntu/Docker/tools, prepared Ubuntu VM boot/tools, normal OOBE and permitted restarts. Source tests cannot establish that the final ISO is problem-free.
