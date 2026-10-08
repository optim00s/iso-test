# Type B acceptance: VMware and Rufus

Use a disposable Windows 11 x64 VM for an initial test. The physical Rufus/USB
boot test is a separate required acceptance step. These tests have not yet run.

1. Verify the final Type B ISO against its adjacent SHA256 file.
2. Create a fresh Windows 11 VM without VMware Easy Install. Enable nested
   virtualization if testing WSL2 inside this VM; otherwise use a physical host.
3. Attach the generated Type B ISO. Keep the virtual NIC disconnected during
   application provisioning to prove that local payloads are sufficient.
4. Install Windows normally. No Type B username, password, AutoLogon or disk
   partition layout should be supplied by the unattended file.
5. Confirm application preparation and one Windows Setup-managed reboot happen
   before OOBE. Windows edition-specific OOBE account/network requirements remain.
6. Complete normal OOBE with the intended test account.
7. On first sign-in, allow local WSL import and prepared-VM copy to finish.
   There must be no installer/package download. Record time to usable desktop.
8. Inspect Public Desktop/TypeB-Setup-STATUS.txt and
   Desktop/TypeB-User-STATUS.txt. Both must report PASSED.
9. Inspect machine logs in C:\ProgramData\TypeB\Logs and user logs in
   %LOCALAPPDATA%\TypeB. Neither a failed marker nor a running installer should remain.
10. Run tests/QUICK-VALIDATE-TARGET.ps1 as the same interactive Windows user.
    It must exit 0. Check all configured applications, not just Word/VS Code.
11. Run code --list-extensions. Confirm all six required extension IDs and any
    additional VSIX assets are present without downloads.
12. Check wsl -l -v: TypeB-Ubuntu-22.04 must belong to this user and use version 2.
    Run Linux baseline checks, docker info, and docker compose version offline.
13. Open Start > Type B > Ubuntu 22.04 VM. It must open a prepared Ubuntu VM,
    not an empty VM or the Ubuntu installation wizard. Verify Ubuntu 22.04,
    Git/LFS, SSH, curl, wget, tmux, FFmpeg/ffprobe, GCC/G++/make, CMake, uv,
    conda and uv-managed Python 3.13 inside the guest. Test with its NIC disconnected.
14. Sign out/in again: no repeat import, VM overwrite or setup should occur.
    Optionally create another normal Windows user and test profile inheritance.
15. Check LM Studio is available under Program Files for the real user,
    rather than only in a SYSTEM AppData directory. Office licensing, Teams
    sign-in, cloud/NAS sign-in and LM Studio models are separate user tasks.
16. Prepare a disposable USB with Rufus using the final Type B ISO, GPT/UEFI
    matching the test device. Do not enable Rufus custom user-account/OOBE options;
    they would change the behavior being tested. Confirm the USB target carefully.
17. Boot a disposable physical device with firmware virtualization enabled.
    Repeat the account, app, VSIX, WSL2/Docker and prepared-VM checks. Record the
    Windows source ISO version, hardware, Rufus version, ISO SHA256 and results.

A source Ubuntu ISO and a TAR merely being present does not count as a working
WSL distribution or an installed Ubuntu VM. Any failed required check blocks
acceptance; the status files and logs should explain the failure.
