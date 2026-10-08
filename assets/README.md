# Offline assets

The final ISO is offline at target deployment time. Put approved installer binaries here before locking/building.

## Windows assets

See `config/apps.json` for exact expected relative file names.

The official 7-Zip 26.04 x64 EXE is unsigned. Its `expectedSha256` in
`config/apps.json` is pinned to the digest of the publisher's
[release asset](https://github.com/ip7z/7zip/releases/tag/26.04).
`Lock-Assets.ps1` rejects any other bytes before writing the asset lock. Updating
this package requires updating the trusted hash pin as well; signed installers
continue to require a valid Authenticode signature.

Prefer machine-wide/offline variants:

- VS Code **System Installer**, not User Installer.
- Qsync `.msi` rather than `.exe` when available.
- Nextcloud `.msi`.
- Microsoft Teams bootstrapper + offline Teams MSIX.
- Windows Terminal MSIX bundle + dependency packages.
- VMware Workstation Pro installer downloaded from the approved Broadcom portal.
- LM Studio approved Windows installer; validate the chosen build's silent/system behavior in VMware.

## Microsoft 365

Place the Office Deployment Tool `setup.exe` in `assets\office`, then run:

```powershell
.\scripts\Prepare-OfficeOffline.ps1
```

This downloads the Office source **on the build machine**. The deployed workstation does not download Office.

The script checks the Microsoft signature on `setup.exe` and writes an integrity
baseline for all local Office files to `assets\office\SHA256SUMS`. To also pin an
approved ODT binary, pass `-ExpectedSetupSha256 '<trusted 64-character SHA256>'`.
If the supplied `setup.exe` is Microsoft's self-extracting ODT download package,
the script extracts and signature-checks the real deployment tool first. It
preserves the original package in `assets\office\odt-source`, then replaces
`assets\office\setup.exe` with the extracted tool. Subsequent hash pins should
use the extracted tool's printed SHA256. Renaming the download package to
`setup.exe` does not by itself turn it into the `/download` deployment tool.
The downloaded Office media hashes are a local baseline, not Microsoft-published
reference hashes. Recheck that baseline without downloading:

```powershell
.\scripts\Prepare-OfficeOffline.ps1 -VerifyOnly
```

## VS Code extensions

Place exactly the six `.vsix` files named in `config\vsix.json` into `assets\vsix`. They are seeded into the Windows Default profile so the first real user inherits them without Internet access.

## Ubuntu

Run:

```powershell
.\scripts\Acquire-UbuntuAssets.ps1
.\scripts\Acquire-LinuxBaseline.ps1
.\scripts\Build-DockerReady-UbuntuWSL.ps1
```

The first script downloads the Ubuntu 22.04.5 Desktop ISO from
`https://releases.ubuntu.com/22.04.5` and the Ubuntu 22.04 LTS WSL root filesystem
`ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz` from
`https://cloud-images.ubuntu.com/wsl/jammy/current`. Each is checked against the
SHA256SUMS from its own Canonical HTTPS directory. Those manifests are stored as
`desktop-SHA256SUMS` and `wsl-SHA256SUMS`, and each verified asset gets a `.sha256`
sidecar. The scripts do not verify Canonical's GPG signatures.

The second script downloads and verifies the Linux baseline installers used by
both the WSL image and the prepared VM.

Run the third script in an elevated PowerShell session with WSL 2 enabled. It
checks the source against `wsl-SHA256SUMS` before import, uses a temporary named
distribution, and produces `TypeB-Ubuntu-22.04-WSL-Docker.tar` plus `.tar.sha256`.
Existing distributions with the builder name are rejected. Existing output is
preserved unless `-Force` is supplied. For a custom `-SourceWsl`, supply a trusted
`-SourceSha256` or an adjacent `wsl-SHA256SUMS` containing that file name.

After preparing the files, run `scripts\Lock-Assets.ps1` and
`scripts\Test-BuildSecurity.ps1` as described in the main README.

Workflow checks with mocked downloads, ODT and WSL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SHA256Workflows.ps1
```

Prepared VM staging and the complete first-logon experience are documented in [README.md](../README.md).
A prepared Ubuntu 22.04 VM folder is mandatory; a Desktop ISO alone is insufficient.
