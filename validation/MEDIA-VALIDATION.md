# Type B 4.1 media validation — 2026-10-10

Result: PASS for the media build and internal file integrity. Clean installation and physical USB boot acceptance: PENDING.

The Windows builder completed with the restored, locked offline assets. Prerequisites, Office SHA-256, Test-BuildAssets and Test-BuildSecurity passed. Oscdimg generated the BIOS/UEFI installation media.

| Artifact | Size / SHA-256 |
| --- | --- |
| TypeB-Windows-AI-Workstation-v4.1.iso | 51,116,107,776 bytes (47.61 GiB) |
| Output ISO SHA-256 | `13aad056af8257453602dd1cff9dc1fc5cfa281354b08cda72bfe7bd2b0e2690` |
| Microsoft Windows source ISO SHA-256 | `bd4307df32bc8af33b39ccecb1174aeb345386630f89a2b86c7a4e36b55ea650` |
| Media build completed (UTC) | 2026-10-10T18:49:56Z |
| Internal file verification completed (UTC) | 2026-10-10T18:52:08Z |

The generated ISO was read back through 7-Zip's binary output and streaming SHA-256, without extracting another full payload to disk. All 84 expected entries were present and matched: 75 locked assets, five canonical runtime scripts, two setup files and two boot images. Asset sizes matched the lock. The BIOS and UEFI boot image bytes matched the stock Microsoft source ISO. Runtime hashes matched the build manifest.

This establishes payload integrity; it does not establish successful firmware boot, installer completion or application behavior on a new machine. The build manifest retains `acceptanceStatus=PENDING_CLEAN_INSTALL`.

Before IT handoff, install this ISO in a fresh VM without recovery CDs and then on a physical laptop using Rufus. Complete normal OOBE and required restarts. Verify all 19 machine components, all six VS Code extensions, WSL 2 Ubuntu 22.04 with Docker server/tools, and the prepared Ubuntu VMware VM's actual boot/tools. No application sign-in is a provisioning requirement; licensing and activation remain separate.

Binary assets, ISOs, temporary staging and raw local logs are excluded from Git. Keep the ISO and its `.iso.sha256` sidecar for testing and transfer. Clone restoration/build instructions are in README.md and BUILD-NOTES.md.
