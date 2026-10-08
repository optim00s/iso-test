# Type B offline ISO builder

Start with [README.md](README.md), which includes the installation experience table,
complete Type B requirements, preparation commands and remaining acceptance checks.

The build contains local application payloads and prepared Ubuntu WSL/VM assets.
Windows applications install during specialize before OOBE. Windows Setup owns
one reboot; first-logon initialization registers the verified WSL image and copies
the prepared VM for the actual user. No Windows username/password is precreated.
