# Type B offline ISO builder

Start with [README.md](README.md), which includes the installation experience table,
complete Type B requirements, preparation commands and remaining acceptance checks.

Current local release: 4.1. BUILD-NOTES.md describes the integrated recovery
fixes, source checks and build/acceptance steps. The 4.1 media build and internal file integrity checks passed; clean installation and physical USB boot acceptance remain pending (validation/MEDIA-VALIDATION.md). Canonical scripts
live in runtime/ and are staged into every new ISO. Large binary assets are not
included in this source-only copy; IT should not need the old recovery CDs.

The build contains local application payloads and prepared Ubuntu WSL/VM assets.
Windows applications install during specialize before OOBE. Windows Setup owns
one reboot; first-logon initialization registers the verified WSL image and copies
the prepared VM for the actual user. No Windows username/password is precreated.
